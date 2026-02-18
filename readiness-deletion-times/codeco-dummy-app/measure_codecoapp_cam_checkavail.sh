#!/usr/bin/env bash

# Copyright (c) 2025 Athena RC.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# SPDX-License-Identifier: Apache-2.0
#
# Contributors:
#      George Koukis - author

# measure_codecoapp_cam_simple.sh
#
# Adapted from measure_codecoapp_cam_checkavail.sh to use a simplified
# CodecoApp YAML that:
#   - Does NOT use schedulerName: qos-scheduler
#   - Uses quay.io/rcarroll/codeco/frontend-app:multiarch for frontends
#   - Backend has no serviceChannels
#   - Frontend uses BESTEFFORT serviceClass with maxDelay: "1s"
#   - appName is per-instance: <codecoapp_name>-swmapp
#
# Pod naming follows: <appName>-backend, <appName>-front-end, <appName>-front-end-2, ...
#
# Scaling N:
#   N=1 -> 1 backend + 1 frontend
#   N>1 -> 1 backend + N frontends (front-end, front-end-2, ... front-end-N)
#
# Measurements:
#   deploy_time_ms : from apply until ALL expected pods are Ready
#   delete_time_ms : from delete until CodecoApp is gone AND all pods are gone
#
# Usage:
#   ./measure_codecoapp_cam.sh <iterations> "<frontend_replicas_values>" [namespace]
# Example:
#   ./measure_codecoapp_cam.sh 6 "1 10 25 50" he-codeco-acm

set -u

if [ $# -lt 2 ]; then
  echo "Usage: $0 <iterations> \"<frontend_replicas_values>\" [namespace]"
  echo "Example: $0 6 \"1 10 25 50\" he-codeco-acm"
  exit 1
fi

iterations="$1"
frontend_replicas_values="$2"
namespace="${3:-he-codeco-acm}"

# Tunables
READINESS_TIMEOUT="${READINESS_TIMEOUT:-600}"          # seconds
DELETION_TIMEOUT="${DELETION_TIMEOUT:-600}"            # seconds
POLL_INTERVAL_SEC="${POLL_INTERVAL_SEC:-2}"            # seconds
SLEEP_BETWEEN_ITERATIONS="${SLEEP_BETWEEN_ITERATIONS:-60}" # seconds

# Images
BACKEND_IMAGE="${BACKEND_IMAGE:-quay.io/skupper/hello-world-backend:latest}"
FRONTEND_IMAGE="${FRONTEND_IMAGE:-quay.io/rcarroll/codeco/frontend-app:multiarch}"

# Service names (must match what the operator uses for pod naming)
BACKEND_SERVICE_NAME="${BACKEND_SERVICE_NAME:-backend}"
FRONTEND_BASE_SERVICE_NAME="${FRONTEND_BASE_SERVICE_NAME:-front-end}"

timestamp_now="$(date +%Y%m%d%H%M%S)"
results_file="codeco_dummy_app_cam_simple_${timestamp_now}.txt"

now_ms() { date +%s%3N; }

sanitize_name() {
  local s="$1"
  s="$(echo "${s}" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')"
  [ -z "${s}" ] && s="x"
  [ "${#s}" -gt 63 ] && s="$(echo "${s:0:63}" | sed -E 's/-+$//')"
  echo "${s}"
}

echo "-------------------------------------------" | tee -a "${results_file}"
echo "CAM Simple: Backend=1, Frontend=N Scaling Experiment" | tee -a "${results_file}"
echo "  (no qos-scheduler, BESTEFFORT frontend, multiarch image)" | tee -a "${results_file}"
echo "Timestamp               : ${timestamp_now}" | tee -a "${results_file}"
echo "Namespace               : ${namespace}" | tee -a "${results_file}"
echo "Iterations              : ${iterations}" | tee -a "${results_file}"
echo "Frontend replicas       : ${frontend_replicas_values}" | tee -a "${results_file}"
echo "Backend image           : ${BACKEND_IMAGE}" | tee -a "${results_file}"
echo "Frontend image          : ${FRONTEND_IMAGE}" | tee -a "${results_file}"
echo "Readiness timeout (s)   : ${READINESS_TIMEOUT}" | tee -a "${results_file}"
echo "Deletion timeout (s)    : ${DELETION_TIMEOUT}" | tee -a "${results_file}"
echo "-------------------------------------------" | tee -a "${results_file}"
echo "iteration,frontend_replicas,deploy_time_ms,delete_time_ms,readiness_ok,apply_ok" >> "${results_file}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

debug_dump() {
  local codecoapp_name="$1"
  echo "  -------- DEBUG DUMP --------" | tee -a "${results_file}"
  echo "  codecoapp: ${codecoapp_name}" | tee -a "${results_file}"
  kubectl get codecoapp -n "${namespace}" "${codecoapp_name}" -o yaml 2>/dev/null \
    | sed -n '1,260p' | tee -a "${results_file}" || true
  echo | tee -a "${results_file}"
  kubectl get pods -n "${namespace}" --sort-by=.metadata.creationTimestamp 2>/dev/null \
    | tail -n 60 | tee -a "${results_file}" || true
  kubectl get events -n "${namespace}" --sort-by=.lastTimestamp 2>/dev/null \
    | tail -n 120 | tee -a "${results_file}" || true
  echo "  ----------------------------" | tee -a "${results_file}"
}

pod_exists() {
  kubectl get pod -n "${namespace}" "$1" >/dev/null 2>&1
}

pod_is_ready() {
  local ready
  ready="$(kubectl get pod -n "${namespace}" "$1" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")"
  [ "${ready}" = "True" ]
}

wait_for_pods_ready() {
  local codecoapp_name="$1"; shift
  local timeout_sec="$1"; shift
  local pods=("$@")
  local start; start="$(date +%s)"

  while true; do
    local all_ok="true"
    local line=""
    for p in "${pods[@]}"; do
      if pod_exists "${p}" && pod_is_ready "${p}"; then
        line+="${p}=OK "
      else
        line+="${p}=WAIT "
        all_ok="false"
      fi
    done
    echo "  ...waiting pod readiness: ${line}" | tee -a "${results_file}"

    [ "${all_ok}" = "true" ] && return 0

    if [ $(( $(date +%s) - start )) -ge "${timeout_sec}" ]; then
      echo "  ⚠ Pod readiness timeout after ${timeout_sec}s" | tee -a "${results_file}"
      debug_dump "${codecoapp_name}"
      return 1
    fi
    sleep "${POLL_INTERVAL_SEC}"
  done
}

wait_for_pods_gone() {
  local timeout_sec="$1"; shift
  local pods=("$@")
  local start; start="$(date +%s)"

  while true; do
    local remaining=0
    local line=""
    for p in "${pods[@]}"; do
      if pod_exists "${p}"; then
        remaining=$((remaining + 1))
        line+="${p}=STILL "
      else
        line+="${p}=GONE "
      fi
    done
    echo "  ...waiting pod deletion: ${line}" | tee -a "${results_file}"

    [ "${remaining}" -eq 0 ] && return 0

    if [ $(( $(date +%s) - start )) -ge "${timeout_sec}" ]; then
      echo "  ⚠ Pod deletion timeout after ${timeout_sec}s" | tee -a "${results_file}"
      return 1
    fi
    sleep 1
  done
}

wait_for_codecoapp_deleted() {
  local name="$1"
  local timeout_sec="$2"
  local start; start="$(date +%s)"
  while true; do
    kubectl get codecoapp -n "${namespace}" "${name}" >/dev/null 2>&1 || return 0
    if [ $(( $(date +%s) - start )) -ge "${timeout_sec}" ]; then
      return 1
    fi
    sleep 1
  done
}

# ---------------------------------------------------------------------------
# YAML builder — simplified spec (no qos-scheduler, no backend serviceChannels)
# ---------------------------------------------------------------------------

apply_codecoapp() {
  local codecoapp_name="$1"
  local replicas="$2"
  # appName drives pod name prefix: <appName>-backend, <appName>-front-end, ...
  local app_name="${codecoapp_name}-swmapp"

  local tmp
  tmp="$(mktemp)"

  cat > "${tmp}" <<EOF
apiVersion: codeco.he-codeco.eu/v1alpha1
kind: CodecoApp
metadata:
  name: ${codecoapp_name}
  namespace: ${namespace}
spec:
  appEnergyLimit: "20"
  appFailureTolerance: ""
  performanceProfile: Greenness
  appName: ${app_name}
  codecoapp-msspec:
  - podspec:
      containers:
      - image: ${BACKEND_IMAGE}
        name: skupper-backend
        ports:
        - containerPort: 8080
          name: skupper-backend
          protocol: TCP
        resources:
          limits:
            cpu: "2"
            memory: 4Gi
    serviceName: ${BACKEND_SERVICE_NAME}
  - podspec:
      containers:
      - image: ${FRONTEND_IMAGE}
        name: front-end
        ports:
        - containerPort: 8080
          protocol: TCP
    serviceChannels:
    - advancedChannelSettings:
        bandwidth: "5M"
        maxDelay: "1s"
      channelName: backend
      serviceClass: BESTEFFORT
      otherService:
        appName: ${app_name}
        port: 8080
        serviceName: ${BACKEND_SERVICE_NAME}
    serviceName: ${FRONTEND_BASE_SERVICE_NAME}
EOF

  # Extra frontends for N > 1
  if [ "${replicas}" -gt 1 ]; then
    for (( i=2; i<=replicas; i++ )); do
      local fe_name="${FRONTEND_BASE_SERVICE_NAME}-${i}"
      cat >> "${tmp}" <<EOF
  - podspec:
      containers:
      - image: ${FRONTEND_IMAGE}
        name: front-end
        ports:
        - containerPort: 8080
          protocol: TCP
    serviceChannels:
    - advancedChannelSettings:
        bandwidth: "5M"
        maxDelay: "1s"
      channelName: backend
      serviceClass: BESTEFFORT
      otherService:
        appName: ${app_name}
        port: 8080
        serviceName: ${BACKEND_SERVICE_NAME}
    serviceName: ${fe_name}
EOF
    done
  fi

  cat >> "${tmp}" <<EOF
  complianceClass: High
  qosClass: Gold
  securityClass: Good
EOF

  kubectl apply -f "${tmp}"
  local rc=$?
  rm -f "${tmp}"
  return ${rc}
}

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------

for replicas in ${frontend_replicas_values}; do
  echo "============================================================" | tee -a "${results_file}"
  echo "Frontend replicas (N) = ${replicas}, Backend = 1" | tee -a "${results_file}"
  echo "============================================================" | tee -a "${results_file}"

  for (( it=1; it<=iterations; it++ )); do
    echo "------------------------------------------------------------" | tee -a "${results_file}"
    echo "Iteration ${it}/${iterations} for N=${replicas}" | tee -a "${results_file}"
    echo "------------------------------------------------------------" | tee -a "${results_file}"

    codecoapp_name="$(sanitize_name "cam-n${replicas}-it${it}-${timestamp_now}")"
    app_name="${codecoapp_name}-swmapp"

    # Build expected pod name list
    # Pod names = <appName>-<serviceName>
    expected_pods=("${app_name}-${BACKEND_SERVICE_NAME}" "${app_name}-${FRONTEND_BASE_SERVICE_NAME}")
    if [ "${replicas}" -gt 1 ]; then
      for (( i=2; i<=replicas; i++ )); do
        expected_pods+=("${app_name}-${FRONTEND_BASE_SERVICE_NAME}-${i}")
      done
    fi

    echo "  Expected pods: ${expected_pods[*]}" | tee -a "${results_file}"

    # Best-effort cleanup from any prior failed run with the same name
    kubectl delete codecoapp -n "${namespace}" "${codecoapp_name}" \
      --ignore-not-found=true >/dev/null 2>&1 || true
    wait_for_codecoapp_deleted "${codecoapp_name}" 60 || true
    wait_for_pods_gone 60 "${expected_pods[@]}" || true

    # --- Deploy ---
    start_deploy_ms="$(now_ms)"
    apply_ok="true"
    if ! apply_codecoapp "${codecoapp_name}" "${replicas}" >/dev/null 2>&1; then
      apply_ok="false"
      echo "  ❌ kubectl apply failed for ${codecoapp_name}" | tee -a "${results_file}"
      debug_dump "${codecoapp_name}"
    fi

    readiness_ok="false"
    if [ "${apply_ok}" = "true" ]; then
      if wait_for_pods_ready "${codecoapp_name}" "${READINESS_TIMEOUT}" "${expected_pods[@]}"; then
        readiness_ok="true"
      fi
    fi

    end_deploy_ms="$(now_ms)"
    deploy_ms=$(( end_deploy_ms - start_deploy_ms ))
    echo "Deployment completed: N=${replicas}, iteration=${it}, deploy_time=${deploy_ms}ms, readiness_ok=${readiness_ok}, apply_ok=${apply_ok}" \
      | tee -a "${results_file}"

    # --- Delete ---
    start_delete_ms="$(now_ms)"
    kubectl delete codecoapp -n "${namespace}" "${codecoapp_name}" \
      --ignore-not-found=true >/dev/null 2>&1 || true
    wait_for_codecoapp_deleted "${codecoapp_name}" "${DELETION_TIMEOUT}" || true
    wait_for_pods_gone "${DELETION_TIMEOUT}" "${expected_pods[@]}" || true
    end_delete_ms="$(now_ms)"
    delete_ms=$(( end_delete_ms - start_delete_ms ))

    echo "Deletion completed: N=${replicas}, iteration=${it}, delete_time=${delete_ms}ms" \
      | tee -a "${results_file}"
    echo "${it},${replicas},${deploy_ms},${delete_ms},${readiness_ok},${apply_ok}" >> "${results_file}"
    echo | tee -a "${results_file}"

    if [ "${it}" -lt "${iterations}" ]; then
      echo "Sleeping ${SLEEP_BETWEEN_ITERATIONS}s before next iteration..." | tee -a "${results_file}"
      sleep "${SLEEP_BETWEEN_ITERATIONS}"
    fi
  done
done

echo "===========================================" | tee -a "${results_file}"
echo "CAM Simple scaling experiment completed." | tee -a "${results_file}"
echo "Results written to: ${results_file}" | tee -a "${results_file}"
