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

# EDIT: change the comparison idea about 

# Non-CAM version with N SEPARATE DEPLOYMENTS (fair comparison with CODECO):
#  - 1 backend deployment (hello-world backend)
#  - N separate frontend deployments (each with 1 replica)
#
# This mirrors what CODECO/CAM does: each frontend is a distinct microservice,
# not N replicas of the same deployment.
#
# For each N and each iteration:
#  - Deploy backend + N separate frontend deployments
#  - Wait for ALL Deployments to be Available
#  - Additionally check that the frontend can be reached over HTTP
#  - Measure deployment time (ms) until "working" state
#  - Delete all experiment resources
#  - Measure deletion time (ms) UNTIL PODS ARE GONE (actual teardown)
#
# Results:
#   codeco_dummy_app_nocam_N_deployments_<timestamp>.txt
#
# Example:
#   ./measure_codecoapp_nocam_checkavail_test.sh 6 "1 10 25 50" skupper-demo

set -euo pipefail

usage() {
  echo "Usage: $0 <iterations> <frontend_replicas_values> [namespace]"
  echo "  iterations              : number of iterations per replica count (e.g. 3)"
  echo "  frontend_replicas_values: quoted list of frontend counts (e.g. \"1 10 20\")"
  echo "  namespace               : (optional) namespace, default: skupper-demo"
  echo
  echo "NOTE: This script creates N SEPARATE frontend Deployments (not 1 Deployment with N replicas)"
  echo "      to fairly compare with CODECO/CAM which creates N separate microservice specs."
  echo
  echo "Example:"
  echo "  $0 3 \"1 10\" skupper-demo"
}

if [ $# -lt 2 ]; then
  usage
  exit 1
fi

iterations="$1"
frontend_replicas_values="$2"
namespace="${3:-skupper-demo}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "❌ kubectl not found in PATH."
  exit 1
fi

# Ensure namespace exists
if ! kubectl get namespace "${namespace}" >/dev/null 2>&1; then
  echo "Namespace ${namespace} does not exist. Creating..."
  kubectl create namespace "${namespace}"
fi

# Parameters for connectivity checks
CONNECTIVITY_TIMEOUT="${CONNECTIVITY_TIMEOUT:-60}"      # seconds to wait for HTTP OK from frontend
CONNECTIVITY_RETRY_DELAY="${CONNECTIVITY_RETRY_DELAY:-2}"   # seconds between attempts
CURL_HELPER_POD="${CURL_HELPER_POD:-curl-tester}"

# Deletion timing (actual)
DELETE_TIMEOUT="${DELETE_TIMEOUT:-600}"                 # seconds: bound for waiting pods/resources to be gone
DELETE_POLL_DELAY="${DELETE_POLL_DELAY:-1}"             # seconds between delete polling

# Results file
timestamp_now=$(date '+%Y%m%d_%H%M%S')
results_file="codeco_dummy_app_nocam_N_deployments_${timestamp_now}.txt"

echo "-------------------------------------------" | tee -a "${results_file}"
echo "Backend=1, Frontend=N SEPARATE DEPLOYMENTS Experiment (non-CAM, fair comparison)" | tee -a "${results_file}"
echo "Timestamp         : ${timestamp_now}" | tee -a "${results_file}"
echo "Namespace         : ${namespace}" | tee -a "${results_file}"
echo "Iterations        : ${iterations}" | tee -a "${results_file}"
echo "Frontend counts   : ${frontend_replicas_values}" | tee -a "${results_file}"
echo "Connectivity timeout (s): ${CONNECTIVITY_TIMEOUT}" | tee -a "${results_file}"
echo "Deletion timeout (s)    : ${DELETE_TIMEOUT}" | tee -a "${results_file}"
echo "NOTE: Creates N separate frontend Deployments (not 1 with N replicas)" | tee -a "${results_file}"
echo "-------------------------------------------" | tee -a "${results_file}"
echo "iteration,frontend_count,deploy_time_ms,delete_time_ms,connectivity_ok,total_deployments" >> "${results_file}"

EXPERIMENT_LABEL_KEY="experiment"
EXPERIMENT_LABEL_VAL="codeco_dummy_app_n_deploy"

now_ms(){ date +%s%3N; }

count_labeled() {
  local kind_csv="$1"  # e.g. "pod" or "deploy,svc"
  kubectl get ${kind_csv} -n "${namespace}" \
    -l "${EXPERIMENT_LABEL_KEY}=${EXPERIMENT_LABEL_VAL}" \
    --no-headers 2>/dev/null | wc -l | tr -d ' ' || echo "0"
}

# Wait until *pods* and key resources are gone for this experiment label
wait_for_experiment_actual_deleted() {
  local start_ts
  start_ts=$(date +%s)
  while true; do
    local p d s total
    p="$(count_labeled pod)"
    d="$(count_labeled deploy)"
    s="$(count_labeled svc)"
    total=$((p + d + s))

    if [ "${total}" -eq 0 ]; then
      break
    fi

    local now
    now=$(date +%s)
    if [ $((now - start_ts)) -ge "${DELETE_TIMEOUT}" ]; then
      echo "  ⚠ Delete wait timed out after ${DELETE_TIMEOUT}s (pods=${p}, deploy=${d}, svc=${s})" | tee -a "${results_file}"
      break
    fi

    echo "  Waiting for ACTUAL deletion... pods=${p}, deploy=${d}, svc=${s}" | tee -a "${results_file}"
    sleep "${DELETE_POLL_DELAY}"
  done
}

# One-time curl helper pod to probe HTTP inside the cluster
ensure_curl_helper_pod() {
  if kubectl get pod "${CURL_HELPER_POD}" -n "${namespace}" >/dev/null 2>&1; then
    echo "Curl helper pod '${CURL_HELPER_POD}' already exists."
  else
    echo "Creating curl helper pod '${CURL_HELPER_POD}' in namespace '${namespace}'..."
    kubectl run "${CURL_HELPER_POD}" \
      -n "${namespace}" \
      --image=curlimages/curl \
      --restart=Never \
      --command -- sleep 365d >/dev/null 2>&1
  fi

  echo "Waiting for curl helper pod '${CURL_HELPER_POD}' to be Ready..."
  kubectl wait --for=condition=Ready pod/"${CURL_HELPER_POD}" \
    -n "${namespace}" --timeout=300s >/dev/null 2>&1
  echo "Curl helper pod is Ready."
}

# Wait until HTTP connectivity to the given URL succeeds (from curl helper pod),
# or until timeout. Returns 0 if OK, 1 if timeout.
wait_for_connectivity() {
  local url="$1"
  local timeout_sec="$2"
  local start_ts
  start_ts=$(date +%s)

  echo "  Checking connectivity to ${url} (timeout=${timeout_sec}s)..."

  while true; do
    if kubectl exec -n "${namespace}" "${CURL_HELPER_POD}" -- \
        curl -sS -m 3 "${url}" >/dev/null 2>&1; then
      echo "  Connectivity OK for ${url}"
      return 0
    fi

    local now
    now=$(date +%s)
    if [ $((now - start_ts)) -ge "${timeout_sec}" ]; then
      echo "  ❌ Connectivity to ${url} did NOT succeed within ${timeout_sec}s"
      return 1
    fi

    echo "  ...still waiting for connectivity to ${url}"
    sleep "${CONNECTIVITY_RETRY_DELAY}"
  done
}

echo "Initial cleanup: deleting any leftover experiment resources in namespace '${namespace}'..."
kubectl delete deploy,svc -n "${namespace}" \
  -l "${EXPERIMENT_LABEL_KEY}=${EXPERIMENT_LABEL_VAL}" \
  --ignore-not-found=true >/dev/null 2>&1 || true

wait_for_experiment_actual_deleted
echo "Initial cleanup done."

ensure_curl_helper_pod

for num_frontends in ${frontend_replicas_values}; do
  echo "============================================================" | tee -a "${results_file}"
  echo "Frontend Deployments (N) = ${num_frontends}, Backend = 1" | tee -a "${results_file}"
  echo "Total Deployments = $((num_frontends + 1))" | tee -a "${results_file}"
  echo "============================================================" | tee -a "${results_file}"

  for (( it=1; it<=iterations; it++ )); do
    echo "------------------------------------------------------------" | tee -a "${results_file}"
    echo "Iteration ${it}/${iterations} for N=${num_frontends}" | tee -a "${results_file}"
    echo "------------------------------------------------------------" | tee -a "${results_file}"

    # Per-iteration cleanup: ensure no previous experiment resources linger
    kubectl delete deploy,svc -n "${namespace}" \
      -l "${EXPERIMENT_LABEL_KEY}=${EXPERIMENT_LABEL_VAL}" \
      --ignore-not-found=true >/dev/null 2>&1 || true
    wait_for_experiment_actual_deleted

    # -------------------------
    # Deployment timing (including connectivity check)
    # -------------------------
    start_deploy_ms=$(now_ms)

    backend_name="skupper-backend-${num_frontends}-${it}"
    backend_svc="skupper-backend-${num_frontends}-${it}"

    # Backend Deployment + Service (1 replica)
    cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${backend_name}
  namespace: ${namespace}
  labels:
    app: skupper-backend
    ${EXPERIMENT_LABEL_KEY}: ${EXPERIMENT_LABEL_VAL}
    run: "${it}"
    frontend-count: "${num_frontends}"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: skupper-backend
      run: "${it}"
      frontend-count: "${num_frontends}"
  template:
    metadata:
      labels:
        app: skupper-backend
        ${EXPERIMENT_LABEL_KEY}: ${EXPERIMENT_LABEL_VAL}
        run: "${it}"
        frontend-count: "${num_frontends}"
    spec:
      #schedulerName: default-scheduler    
      containers:
      - name: skupper-backend
        image: quay.io/skupper/hello-world-backend:latest
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: ${backend_svc}
  namespace: ${namespace}
  labels:
    app: skupper-backend
    ${EXPERIMENT_LABEL_KEY}: ${EXPERIMENT_LABEL_VAL}
    run: "${it}"
    frontend-count: "${num_frontends}"
spec:
  selector:
    app: skupper-backend
    run: "${it}"
    frontend-count: "${num_frontends}"
  ports:
  - port: 8080
    targetPort: 8080
EOF

    # Create N SEPARATE frontend Deployments (each with 1 replica)
    # This mirrors what CODECO does with N separate microservice specs
    deployment_names=("${backend_name}")
    
    for (( fe=1; fe<=num_frontends; fe++ )); do
      if [ "${fe}" -eq 1 ]; then
        frontend_name="skupper-frontend-${num_frontends}-${it}"
        frontend_svc="skupper-frontend-${num_frontends}-${it}"
      else
        frontend_name="skupper-frontend-${num_frontends}-${it}-${fe}"
        frontend_svc="skupper-frontend-${num_frontends}-${it}-${fe}"
      fi
      
      deployment_names+=("${frontend_name}")

      cat <<EOF | kubectl apply -f - >/dev/null &
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${frontend_name}
  namespace: ${namespace}
  labels:
    app: skupper-frontend
    ${EXPERIMENT_LABEL_KEY}: ${EXPERIMENT_LABEL_VAL}
    run: "${it}"
    frontend-count: "${num_frontends}"
    frontend-index: "${fe}"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: skupper-frontend
      run: "${it}"
      frontend-count: "${num_frontends}"
      frontend-index: "${fe}"
  template:
    metadata:
      labels:
        app: skupper-frontend
        ${EXPERIMENT_LABEL_KEY}: ${EXPERIMENT_LABEL_VAL}
        run: "${it}"
        frontend-count: "${num_frontends}"
        frontend-index: "${fe}"
    spec:
      #schedulerName: default-scheduler      
      containers:
      - name: front-end
        image: quay.io/dekelly/frontend-app:v0.0.2
        env:
        - name: BACKEND_URL
          value: "http://${backend_svc}:8080"
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: ${frontend_svc}
  namespace: ${namespace}
  labels:
    app: skupper-frontend
    ${EXPERIMENT_LABEL_KEY}: ${EXPERIMENT_LABEL_VAL}
    run: "${it}"
    frontend-count: "${num_frontends}"
    frontend-index: "${fe}"
spec:
  selector:
    app: skupper-frontend
    run: "${it}"
    frontend-count: "${num_frontends}"
    frontend-index: "${fe}"
  ports:
  - port: 8080
    targetPort: 8080
EOF
    done
    
    # Wait for all kubectl apply commands to complete
    wait

    # Wait for ALL deployments to be Available
    echo "  Waiting for ${#deployment_names[@]} deployments to be ready..." | tee -a "${results_file}"
    
    for deploy_name in "${deployment_names[@]}"; do
      kubectl wait --for=condition=available deployment/"${deploy_name}" \
        -n "${namespace}" --timeout=600s >/dev/null 2>&1
    done

    echo "  All ${#deployment_names[@]} deployments are ready." | tee -a "${results_file}"

    # Connectivity check: wait until first frontend service responds
    first_frontend_svc="skupper-frontend-${num_frontends}-${it}"
    frontend_url="http://${first_frontend_svc}:8080"
    connectivity_ok="true"
    if ! wait_for_connectivity "${frontend_url}" "${CONNECTIVITY_TIMEOUT}"; then
      connectivity_ok="false"
    fi

    end_deploy_ms=$(now_ms)
    deploy_duration_ms=$((end_deploy_ms - start_deploy_ms))

    total_deployments=$((num_frontends + 1))
    echo "Deployment completed: N=${num_frontends}, iteration=${it}, deploy_time=${deploy_duration_ms} ms, connectivity_ok=${connectivity_ok}, total_deployments=${total_deployments}" | tee -a "${results_file}"

    # -------------------------
    # Deletion timing (ACTUAL)
    # -------------------------
    start_delete_ms=$(now_ms)

    # Delete objects first (this triggers pod termination)
    kubectl delete deploy,svc -n "${namespace}" \
      -l "${EXPERIMENT_LABEL_KEY}=${EXPERIMENT_LABEL_VAL}" \
      --ignore-not-found=true >/dev/null 2>&1 || true

    # Now wait for pods + deploy + svc to be gone
    wait_for_experiment_actual_deleted

    end_delete_ms=$(now_ms)
    delete_duration_ms=$((end_delete_ms - start_delete_ms))

    echo "Deletion completed: N=${num_frontends}, iteration=${it}, delete_time=${delete_duration_ms} ms" | tee -a "${results_file}"
    echo "${it},${num_frontends},${deploy_duration_ms},${delete_duration_ms},${connectivity_ok},${total_deployments}" >> "${results_file}"
    echo | tee -a "${results_file}"

    echo "Sleeping 60 seconds before next iteration..."
    sleep 60

  done
done

echo "==========================================="
echo "Backend=1, Frontend=N SEPARATE DEPLOYMENTS experiment (non-CAM) completed."
echo "Results written to: ${results_file}"
echo "==========================================="