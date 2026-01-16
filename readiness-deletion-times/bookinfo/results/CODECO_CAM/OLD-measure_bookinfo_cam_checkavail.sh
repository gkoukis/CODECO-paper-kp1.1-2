#!/bin/bash

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

set -euo pipefail

usage() {
  echo "Usage: $0 <yaml_file> <iterations> [namespace] [node_ip]"
  echo "Example: $0 OLD-CAM-codecoapp-bookinfo-FOR.yaml 6 he-codeco-acm"
  echo "Example: $0 codecoapp-bookinfo-FOR.yaml 6 he-codeco-acm"
}

if [ $# -lt 2 ]; then usage; exit 1; fi

YAML_FILE="$1"
ITERATIONS="$2"
NAMESPACE="${3:-he-codeco-acm}"
NODE_IP="${4:-}"

PODS_READY_TIMEOUT_SEC=600
HTTP_TIMEOUT_SEC=240
HTTP_RETRY_DELAY_SEC=2
CAM_STATUS_TIMEOUT_SEC=240
SLEEP_BETWEEN_ITERS_SEC=10

WAIT_CAM_STATUS="true"

PRODUCTPAGE_NODEPORT="30000"

# IMPORTANT: this is the prefix you are seeing in pod names:
# acm-swm-app-productpage, acm-swm-app-details, ...
POD_PREFIX="acm-swm-app"

SERVICES=("productpage" "details" "reviews" "ratings")

command -v kubectl >/dev/null 2>&1 || { echo "❌ kubectl not found"; exit 1; }
[ -f "${YAML_FILE}" ] || { echo "❌ YAML file not found: ${YAML_FILE}"; exit 1; }

detect_node_ip() {
  local ip
  ip=$(kubectl get nodes -o jsonpath='{range .items[*]}{range .status.addresses[*]}{.type}{"="}{.address}{"\n"}{end}{end}' \
    | awk -F= '$1=="ExternalIP"{print $2; exit}')
  if [ -z "${ip}" ]; then
    ip=$(kubectl get nodes -o jsonpath='{range .items[*]}{range .status.addresses[*]}{.type}{"="}{.address}{"\n"}{end}{end}' \
      | awk -F= '$1=="InternalIP"{print $2; exit}')
  fi
  echo "${ip}"
}

if [ -z "${NODE_IP}" ]; then
  NODE_IP="$(detect_node_ip)"
fi
[ -n "${NODE_IP}" ] || { echo "❌ Could not detect node IP; pass it as 4th argument."; exit 1; }

CODECOAPP_NAME="$(awk '
  $1=="kind:" && $2=="CodecoApp"{incodeco=1}
  incodeco && $1=="name:" {print $2; exit}
' "${YAML_FILE}" | tr -d '"')"
[ -n "${CODECOAPP_NAME}" ] || { echo "❌ Could not detect CodecoApp name from YAML."; exit 1; }

timestamp_now=$(date '+%Y%m%d_%H%M%S')
RESULTS_FILE="bookinfo_cam_kpi_${timestamp_now}.txt"

echo "-------------------------------------------" | tee -a "${RESULTS_FILE}"
echo "Bookinfo CAM KPI Experiment" | tee -a "${RESULTS_FILE}"
echo "YAML file           : ${YAML_FILE}" | tee -a "${RESULTS_FILE}"
echo "Namespace           : ${NAMESPACE}" | tee -a "${RESULTS_FILE}"
echo "CodecoApp name      : ${CODECOAPP_NAME}" | tee -a "${RESULTS_FILE}"
echo "Node IP             : ${NODE_IP}" | tee -a "${RESULTS_FILE}"
echo "Productpage NodePort: ${PRODUCTPAGE_NODEPORT}" | tee -a "${RESULTS_FILE}"
echo "Iterations          : ${ITERATIONS}" | tee -a "${RESULTS_FILE}"
echo "Pod prefix          : ${POD_PREFIX}" | tee -a "${RESULTS_FILE}"
echo "Wait CAM status     : ${WAIT_CAM_STATUS} (timeout ${CAM_STATUS_TIMEOUT_SEC}s)" | tee -a "${RESULTS_FILE}"
echo "-------------------------------------------" | tee -a "${RESULTS_FILE}"
echo "iteration,ready_functional_time_ms,delete_time_ms,cam_status_observed,http_ok" >> "${RESULTS_FILE}"

ensure_ns() {
  if ! kubectl get ns "${NAMESPACE}" >/dev/null 2>&1; then
    kubectl create ns "${NAMESPACE}" >/dev/null
  fi
}

# Find pods by name prefix, returns list of pod names (one per line)
pods_for_service() {
  local svc="$1"
  kubectl get pods -n "${NAMESPACE}" -o name 2>/dev/null \
    | sed 's|^pod/||' \
    | grep -E "^${POD_PREFIX}-${svc}([^-].*)?$" || true
}

cleanup_all() {
  echo "Cleaning up resources (best-effort)..."

  # Delete everything from YAML (non-blocking)
  kubectl delete -f "${YAML_FILE}" -n "${NAMESPACE}" --ignore-not-found=true --wait=false >/dev/null 2>&1 || true
  kubectl delete codecoapp "${CODECOAPP_NAME}" -n "${NAMESPACE}" --ignore-not-found=true --wait=false >/dev/null 2>&1 || true

  # Also delete pods by name prefix (non-blocking), because labels may be missing
  for svc in "${SERVICES[@]}"; do
    while read -r p; do
      [ -n "$p" ] || continue
      kubectl delete pod "$p" -n "${NAMESPACE}" --ignore-not-found=true --wait=false >/dev/null 2>&1 || true
    done < <(pods_for_service "${svc}")
  done

  # Poll until CodecoApp + services + pods gone (visible progress)
  local deadline=$(( $(date +%s) + 180 ))
  while true; do
    local ca_exists=0
    if kubectl get codecoapp "${CODECOAPP_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then ca_exists=1; fi

    local svc_cnt
    svc_cnt=$(kubectl get svc -n "${NAMESPACE}" productpage details reviews ratings \
      --ignore-not-found --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')

    local pod_cnt=0
    for s in "${SERVICES[@]}"; do
      c=$(pods_for_service "$s" | wc -l | tr -d '[:space:]')
      pod_cnt=$((pod_cnt + c))
    done

    if [ "${ca_exists}" -eq 0 ] && [ "${svc_cnt:-0}" -eq 0 ] && [ "${pod_cnt}" -eq 0 ]; then
      echo "✔ Cleanup complete."
      return 0
    fi

    if [ "$(date +%s)" -ge "${deadline}" ]; then
      echo "⚠ Cleanup timeout; continuing anyway. remaining: codecoapp=${ca_exists}, services=${svc_cnt:-0}, pods=${pod_cnt}"
      return 0
    fi

    echo "  Waiting cleanup... codecoapp=${ca_exists}, services=${svc_cnt:-0}, pods=${pod_cnt}"
    sleep 2
  done
}

wait_for_cam_status() {
  local start=$(date +%s)
  while true; do
    local s
    s=$(kubectl get codecoapp "${CODECOAPP_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.appMetrics}' 2>/dev/null || true)
    if [ -n "${s}" ]; then
      return 0
    fi
    if [ $(( $(date +%s) - start )) -ge "${CAM_STATUS_TIMEOUT_SEC}" ]; then
      return 1
    fi
    sleep 1
  done
}

# Wait for each service pod to appear, label it serviceName=<svc>, then wait Ready
wait_for_pods_ready_and_labeled() {
  local deadline=$(( $(date +%s) + PODS_READY_TIMEOUT_SEC ))

  for svc in "${SERVICES[@]}"; do
    echo "Waiting for pod(s) for service '${svc}' to appear..."
    while true; do
      local pods
      pods="$(pods_for_service "${svc}")"

      if [ -n "${pods}" ]; then
        # Apply label required by your Services selectors
        while read -r p; do
          [ -n "$p" ] || continue
          kubectl label pod "$p" -n "${NAMESPACE}" "serviceName=${svc}" --overwrite >/dev/null 2>&1 || true
        done <<< "${pods}"

        # Now wait for readiness for those pods
        while read -r p; do
          [ -n "$p" ] || continue
          kubectl wait --for=condition=Ready pod/"$p" -n "${NAMESPACE}" --timeout="${PODS_READY_TIMEOUT_SEC}s" >/dev/null 2>&1
        done <<< "${pods}"

        echo "✔ Pods Ready + labeled for ${svc}"
        break
      fi

      if [ "$(date +%s)" -ge "${deadline}" ]; then
        echo "❌ Timeout waiting for pods for ${svc}"
        return 1
      fi
      sleep 1
    done
  done
}

wait_for_http_ok() {
  local base="http://${NODE_IP}:${PRODUCTPAGE_NODEPORT}"
  local start=$(date +%s)
  echo "Waiting for HTTP OK from productpage on ${base} ..."
  while true; do
    if curl -fsS -m 3 "${base}/productpage" >/dev/null 2>&1 || curl -fsS -m 3 "${base}/" >/dev/null 2>&1; then
      return 0
    fi
    if [ $(( $(date +%s) - start )) -ge "${HTTP_TIMEOUT_SEC}" ]; then
      return 1
    fi
    sleep "${HTTP_RETRY_DELAY_SEC}"
  done
}

wait_for_deleted() {
  local deadline=$(( $(date +%s) + 300 ))
  while true; do
    local remaining=0

    if kubectl get codecoapp "${CODECOAPP_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
      remaining=$((remaining + 1))
    fi

    local svc_cnt
    svc_cnt=$(kubectl get svc -n "${NAMESPACE}" productpage details reviews ratings \
      --ignore-not-found --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')
    remaining=$((remaining + ${svc_cnt:-0}))

    local pod_cnt=0
    for s in "${SERVICES[@]}"; do
      c=$(pods_for_service "$s" | wc -l | tr -d '[:space:]')
      pod_cnt=$((pod_cnt + c))
    done
    remaining=$((remaining + pod_cnt))

    if [ "${remaining}" -eq 0 ]; then
      return 0
    fi

    if [ "$(date +%s)" -ge "${deadline}" ]; then
      echo "⚠ Deletion wait timeout; remaining objects approx: ${remaining}"
      return 1
    fi
    sleep 0.5
  done
}

ensure_ns

for (( it=1; it<=ITERATIONS; it++ )); do
  echo "============================================================" | tee -a "${RESULTS_FILE}"
  echo "Iteration ${it}/${ITERATIONS}" | tee -a "${RESULTS_FILE}"
  echo "============================================================" | tee -a "${RESULTS_FILE}"

  cleanup_all

  start_ready_ms=$(date +%s%3N)

  kubectl apply -f "${YAML_FILE}" >/dev/null

  cam_ok="true"
  if [ "${WAIT_CAM_STATUS}" = "true" ]; then
    if ! wait_for_cam_status; then cam_ok="false"; fi
  fi

  wait_for_pods_ready_and_labeled

  http_ok="true"
  if ! wait_for_http_ok; then http_ok="false"; fi

  end_ready_ms=$(date +%s%3N)
  ready_ms=$((end_ready_ms - start_ready_ms))

  echo "Ready+Functional completed: iteration=${it}, time=${ready_ms} ms, cam_status=${cam_ok}, http_ok=${http_ok}" | tee -a "${RESULTS_FILE}"

  start_del_ms=$(date +%s%3N)
  kubectl delete -f "${YAML_FILE}" -n "${NAMESPACE}" --ignore-not-found=true --wait=false >/dev/null 2>&1 || true
  kubectl delete codecoapp "${CODECOAPP_NAME}" -n "${NAMESPACE}" --ignore-not-found=true --wait=false >/dev/null 2>&1 || true

  wait_for_deleted || true

  end_del_ms=$(date +%s%3N)
  del_ms=$((end_del_ms - start_del_ms))

  echo "Deletion completed: iteration=${it}, time=${del_ms} ms" | tee -a "${RESULTS_FILE}"
  echo "${it},${ready_ms},${del_ms},${cam_ok},${http_ok}" >> "${RESULTS_FILE}"

  echo "Sleeping ${SLEEP_BETWEEN_ITERS_SEC} seconds before next iteration..." | tee -a "${RESULTS_FILE}"
  sleep "${SLEEP_BETWEEN_ITERS_SEC}"
done

echo "==========================================="
echo "Bookinfo CAM KPI experiment completed."
echo "Results written to: ${RESULTS_FILE}"
echo "==========================================="
