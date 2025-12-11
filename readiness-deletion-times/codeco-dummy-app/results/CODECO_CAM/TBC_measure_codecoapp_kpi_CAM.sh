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
#
# Description:
#   Experiment: 1 backend (constant) + N frontends (scaled).
#   For each <frontend_replicas> and each iteration:
#     - Create 1 backend CodecoApp
#     - Create <frontend_replicas> frontend CodecoApps
#     - Measure deployment time (ms)
#     - Delete all those CodecoApps
#     - Measure deletion time (ms)
#
#   Results are appended to:
#     cam_backend1_frontend_scaling_<timestamp>.txt
#
#   NOTE: This uses CodecoApps only. Pods/services created by the ACM/SWM stack
#         are not explicitly waited for; the timing is from CodecoApp applies
#         to their presence/deletion.

set -euo pipefail

# -----------------------------
# Usage
# -----------------------------
usage() {
  echo "Usage: $0 <iterations> <frontend_replicas_values> [namespace]"
  echo "  iterations              : number of iterations per replica count (e.g. 3)"
  echo "  frontend_replicas_values: quoted list of frontend replica counts (e.g. \"1 10 20\")"
  echo "  namespace               : (optional) namespace, default: he-codeco-acm"
  echo
  echo "Example:"
  echo "  $0 3 \"1 10 20\" he-codeco-acm"
}

if [ $# -lt 2 ]; then
  usage
  exit 1
fi

iterations="$1"
frontend_replicas_values="$2"
namespace="${3:-he-codeco-acm}"

# -----------------------------
# Basic checks
# -----------------------------
if ! command -v kubectl >/dev/null 2>&1; then
  echo "❌ kubectl not found in PATH."
  exit 1
fi

if ! kubectl get crd codecoapps.codeco.he-codeco.eu >/dev/null 2>&1; then
  echo "❌ CodecoApp CRD not found. Is the CODECO/ACM operator installed?"
  exit 1
fi

# Ensure namespace exists
if ! kubectl get namespace "${namespace}" >/dev/null 2>&1; then
  echo "Namespace ${namespace} does not exist. Creating..."
  kubectl create namespace "${namespace}"
fi

# -----------------------------
# Result file
# -----------------------------
timestamp_now=$(date '+%Y%m%d_%H%M%S')
results_file="cam_backend1_frontend_scaling_${timestamp_now}.txt"

echo "-------------------------------------------" | tee -a "${results_file}"
echo "CAM Backend=1, Frontend=N Scaling Experiment" | tee -a "${results_file}"
echo "Timestamp         : ${timestamp_now}" | tee -a "${results_file}"
echo "Namespace         : ${namespace}" | tee -a "${results_file}"
echo "Iterations        : ${iterations}" | tee -a "${results_file}"
echo "Frontend replicas : ${frontend_replicas_values}" | tee -a "${results_file}"
echo "-------------------------------------------" | tee -a "${results_file}"
echo "iteration,frontend_replicas,deploy_time_ms,delete_time_ms" >> "${results_file}"

# Label to identify experiment resources
EXPERIMENT_LABEL_KEY="experiment"
EXPERIMENT_LABEL_VAL="cam-backend1-frontend-scaling"

# -----------------------------
# Helper: wait for CodecoApp count
# -----------------------------
wait_for_codecoapps_count() {
  local expected_count="$1"
  local run_id="$2"
  local replicas_str="$3"

  local timeout_sec=300
  local deadline=$(( $(date +%s) + timeout_sec ))

  while [ "$(date +%s)" -lt "${deadline}" ]; do
    current_count=$(kubectl get codecoapp -n "${namespace}" \
      -l "${EXPERIMENT_LABEL_KEY}=${EXPERIMENT_LABEL_VAL},run=${run_id},replica-group=${replicas_str}" \
      --no-headers 2>/dev/null | wc -l || echo 0)

    if [ "${current_count}" -eq "${expected_count}" ]; then
      return 0
    fi

    sleep 1
  done

  echo "⚠ Timeout waiting for ${expected_count} CodecoApps (run=${run_id}, replicas=${replicas_str}), last count=${current_count}"
  return 1
}

# -----------------------------
# Helper: wait until all labelled CodecoApps gone
# -----------------------------
wait_for_codecoapps_deleted() {
  local run_id="$1"
  local replicas_str="$2"

  while true; do
    local remaining
    remaining=$(kubectl get codecoapp -n "${namespace}" \
      -l "${EXPERIMENT_LABEL_KEY}=${EXPERIMENT_LABEL_VAL},run=${run_id},replica-group=${replicas_str}" \
      --no-headers 2>/dev/null | wc -l || echo 0)

    if [ "${remaining}" -eq 0 ]; then
      break
    fi

    echo "  Waiting for CodecoApps to be deleted... remaining: ${remaining}"
    sleep 0.2
  done
}

# -----------------------------
# Main experiment loop
# -----------------------------
for replicas in ${frontend_replicas_values}; do
  echo "============================================================" | tee -a "${results_file}"
  echo "Frontend replicas (N) = ${replicas}, Backend = 1" | tee -a "${results_file}"
  echo "============================================================" | tee -a "${results_file}"

  for (( it=1; it<=iterations; it++ )); do
    echo "------------------------------------------------------------" | tee -a "${results_file}"
    echo "Iteration ${it}/${iterations} for N=${replicas}" | tee -a "${results_file}"
    echo "------------------------------------------------------------" | tee -a "${results_file}"

    # Clean any leftover CodecoApps from previous failed runs for this (run, replicas)
    kubectl delete codecoapp -n "${namespace}" \
      -l "${EXPERIMENT_LABEL_KEY}=${EXPERIMENT_LABEL_VAL},run=${it},replica-group=${replicas}" \
      --ignore-not-found=true >/dev/null 2>&1 || true

    # -------------------------
    # Deployment timing
    # -------------------------
    start_deploy_ms=$(date +%s%3N)

    # 1) Create ONE backend CodecoApp
    backend_app_name="acm-backend-${replicas}-${it}"
    backend_svc="backend-${replicas}-${it}"

    cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: codeco.he-codeco.eu/v1alpha1
kind: CodecoApp
metadata:
  name: ${backend_app_name}
  namespace: ${namespace}
  labels:
    ${EXPERIMENT_LABEL_KEY}: ${EXPERIMENT_LABEL_VAL}
    run: "${it}"
    replica-group: "${replicas}"
spec:
  appEnergyLimit: "20"
  appFailureTolerance: ""
  performanceProfile: Greenness
  appName: acm-swm-app
  codecoapp-msspec:
  - podspec:
      containers:
      - image: quay.io/skupper/hello-world-backend:latest
        name: skupper-backend
        ports:
        - containerPort: 8080
          name: skupper-backend
          protocol: TCP
        resources:
          limits:
            cpu: "2"
            memory: 4Gi
    serviceChannels:
    - advancedChannelSettings:
        minBandwidth: "5"
        frameSize: "100"
        maxDelay: "300000"
        sendInterval: "10"
      channelName: frontend
      otherService:
        appName: acm-swm-app
        port: 9090
        serviceName: front-end-shared-${replicas}-${it}
    serviceName: ${backend_svc}
  complianceClass: High
  qosClass: Gold
  securityClass: Good
EOF

    # 2) Create N frontend CodecoApps, all pointing to the SAME backend
    for (( idx=1; idx<=replicas; idx++ )); do
      frontend_app_name="acm-frontend-${replicas}-${it}-${idx}"
      frontend_svc="front-end-${replicas}-${it}-${idx}"

      cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: codeco.he-codeco.eu/v1alpha1
kind: CodecoApp
metadata:
  name: ${frontend_app_name}
  namespace: ${namespace}
  labels:
    ${EXPERIMENT_LABEL_KEY}: ${EXPERIMENT_LABEL_VAL}
    run: "${it}"
    replica-group: "${replicas}"
spec:
  appEnergyLimit: "20"
  appFailureTolerance: ""
  performanceProfile: Greenness
  appName: acm-swm-app
  codecoapp-msspec:
  - podspec:
      containers:
      - image: quay.io/dekelly/frontend-app:v0.0.2
        name: front-end
        ports:
        - containerPort: 8080
          protocol: TCP
    serviceChannels:
    - advancedChannelSettings:
        minBandwidth: "5"
        frameSize: "100"
        maxDelay: "1000000"
        sendInterval: "10"
      channelName: backend
      otherService:
        appName: acm-swm-app
        port: 8080
        serviceName: ${backend_svc}
    serviceName: ${frontend_svc}
  complianceClass: High
  qosClass: Gold
  securityClass: Good
EOF
    done

    # Total expected CodecoApps: 1 backend + N frontends
    expected_total=$((replicas + 1))

    wait_for_codecoapps_count "${expected_total}" "${it}" "${replicas}" || true

    end_deploy_ms=$(date +%s%3N)
    deploy_duration_ms=$((end_deploy_ms - start_deploy_ms))

    echo "Deployment completed: N=${replicas}, iteration=${it}, deploy_time=${deploy_duration_ms} ms" | tee -a "${results_file}"

    # -------------------------
    # Deletion timing
    # -------------------------
    start_delete_ms=$(date +%s%3N)

    kubectl delete codecoapp -n "${namespace}" \
      -l "${EXPERIMENT_LABEL_KEY}=${EXPERIMENT_LABEL_VAL},run=${it},replica-group=${replicas}" \
      --ignore-not-found=true >/dev/null 2>&1 || true

    wait_for_codecoapps_deleted "${it}" "${replicas}"

    end_delete_ms=$(date +%s%3N)
    delete_duration_ms=$((end_delete_ms - start_delete_ms))

    echo "Deletion completed: N=${replicas}, iteration=${it}, delete_time=${delete_duration_ms} ms" | tee -a "${results_file}"

    # Append CSV line
    echo "${it},${replicas},${deploy_duration_ms},${delete_duration_ms}" >> "${results_file}"

    echo | tee -a "${results_file}"

    # ---------------------------------------------
    # Sleep between iterations (60 seconds)
    # ---------------------------------------------
    if [ "${it}" -lt "${iterations}" ]; then
      echo "Sleeping 60 seconds before next iteration..." | tee -a "${results_file}"
      sleep 60
    fi

  done
done

echo "==========================================="
echo "CAM Backend=1, Frontend=N scaling experiment completed."
echo "Results written to: ${results_file}"
echo "==========================================="
