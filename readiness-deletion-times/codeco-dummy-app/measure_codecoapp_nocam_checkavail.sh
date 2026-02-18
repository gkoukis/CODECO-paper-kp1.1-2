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

# measure_codecoapp_nocam_checkavail.sh
#
# Non-CAM version with N SEPARATE DEPLOYMENTS (fair comparison with CODECO/CAM):
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
#  - Measure deletion time (ms) until pods are actually gone
#
# Resilience: uses set -u (not set -euo pipefail) so transient API errors
# do not abort the script mid-experiment. kubectl wait failures are caught
# explicitly and recorded rather than causing an exit.
#
# Results:
#   codeco_dummy_app_nocam_N_deployments_<timestamp>.txt
#
# Example:
#   ./measure_codecoapp_nocam_checkavail.sh 6 "1 10 25 50" skupper-demo

# -u: error on unbound variables; NOT -e/-o pipefail to survive transient errors
set -u

usage() {
  echo "Usage: $0 <iterations> <frontend_replicas_values> [namespace]"
  echo "  iterations              : number of iterations per replica count (e.g. 3)"
  echo "  frontend_replicas_values: quoted list of frontend counts (e.g. \"1 10 20\")"
  echo "  namespace               : (optional) namespace, default: skupper-demo"
  echo
  echo "NOTE: Creates N separate frontend Deployments (not 1 with N replicas)"
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
  echo "kubectl not found in PATH."
  exit 1
fi

# Ensure namespace exists
if ! kubectl get namespace "${namespace}" >/dev/null 2>&1; then
  echo "Namespace ${namespace} does not exist. Creating..."
  kubectl create namespace "${namespace}" || true
fi

# ---------------------------------------------------------------------------
# Tunables (all overridable via environment variables)
# ---------------------------------------------------------------------------
CONNECTIVITY_TIMEOUT="${CONNECTIVITY_TIMEOUT:-60}"        # seconds to wait for HTTP OK from frontend
CONNECTIVITY_RETRY_DELAY="${CONNECTIVITY_RETRY_DELAY:-2}" # seconds between curl attempts
CURL_HELPER_POD="${CURL_HELPER_POD:-curl-tester}"

POLL_INTERVAL_SEC="${POLL_INTERVAL_SEC:-2}"               # seconds between availability poll iterations
DEPLOY_WAIT_TIMEOUT="${DEPLOY_WAIT_TIMEOUT:-600}"         # seconds total to wait for all deployments Available
DELETE_TIMEOUT="${DELETE_TIMEOUT:-600}"                   # seconds to wait for pods/resources to be gone
DELETE_POLL_DELAY="${DELETE_POLL_DELAY:-1}"               # seconds between delete polling
SLEEP_BETWEEN_ITERATIONS="${SLEEP_BETWEEN_ITERATIONS:-60}" # seconds between iterations

# ---------------------------------------------------------------------------
# Results file
# ---------------------------------------------------------------------------
timestamp_now=$(date '+%Y%m%d_%H%M%S')
results_file="codeco_dummy_app_nocam_N_deployments_${timestamp_now}.txt"

echo "-------------------------------------------" | tee -a "${results_file}"
echo "Backend=1, Frontend=N SEPARATE DEPLOYMENTS Experiment (non-CAM, fair comparison)" | tee -a "${results_file}"
echo "Timestamp               : ${timestamp_now}" | tee -a "${results_file}"
echo "Namespace               : ${namespace}" | tee -a "${results_file}"
echo "Iterations              : ${iterations}" | tee -a "${results_file}"
echo "Frontend counts         : ${frontend_replicas_values}" | tee -a "${results_file}"
echo "Connectivity timeout (s): ${CONNECTIVITY_TIMEOUT}" | tee -a "${results_file}"
echo "Deploy wait timeout (s) : ${DEPLOY_WAIT_TIMEOUT}" | tee -a "${results_file}"
echo "Deletion timeout (s)    : ${DELETE_TIMEOUT}" | tee -a "${results_file}"
echo "NOTE: Creates N separate frontend Deployments (not 1 with N replicas)" | tee -a "${results_file}"
echo "-------------------------------------------" | tee -a "${results_file}"
echo "iteration,frontend_count,deploy_time_ms,delete_time_ms,availability_ok,connectivity_ok,total_deployments" \
  >> "${results_file}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

EXPERIMENT_LABEL_KEY="experiment"
EXPERIMENT_LABEL_VAL="codeco_dummy_app_n_deploy"

now_ms() { date +%s%3N; }

count_labeled() {
  local kind_csv="$1"
  kubectl get ${kind_csv} -n "${namespace}" \
    -l "${EXPERIMENT_LABEL_KEY}=${EXPERIMENT_LABEL_VAL}" \
    --no-headers 2>/dev/null | wc -l | tr -d ' ' || echo "0"
}

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
      echo "  ⚠ Delete wait timed out after ${DELETE_TIMEOUT}s (pods=${p}, deploy=${d}, svc=${s})" \
        | tee -a "${results_file}"
      break
    fi

    echo "  Waiting for actual deletion... pods=${p}, deploy=${d}, svc=${s}" | tee -a "${results_file}"
    sleep "${DELETE_POLL_DELAY}"
  done
}

ensure_curl_helper_pod() {
  if kubectl get pod "${CURL_HELPER_POD}" -n "${namespace}" >/dev/null 2>&1; then
    echo "Curl helper pod '${CURL_HELPER_POD}' already exists." | tee -a "${results_file}"
  else
    echo "Creating curl helper pod '${CURL_HELPER_POD}' in namespace '${namespace}'..." \
      | tee -a "${results_file}"
    kubectl run "${CURL_HELPER_POD}" \
      -n "${namespace}" \
      --image=curlimages/curl \
      --restart=Never \
      --command -- sleep 365d >/dev/null 2>&1 || true
  fi

  echo "Waiting for curl helper pod '${CURL_HELPER_POD}' to be Ready..." | tee -a "${results_file}"
  if ! kubectl wait --for=condition=Ready pod/"${CURL_HELPER_POD}" \
      -n "${namespace}" --timeout=300s >/dev/null 2>&1; then
    echo "  ⚠ Curl helper pod did not become Ready within 300s -- connectivity checks will fail" \
      | tee -a "${results_file}"
  else
    echo "Curl helper pod is Ready." | tee -a "${results_file}"
  fi
}

wait_for_connectivity() {
  local url="$1"
  local timeout_sec="$2"
  local start_ts
  start_ts=$(date +%s)

  echo "  Checking connectivity to ${url} (timeout=${timeout_sec}s)..." | tee -a "${results_file}"

  while true; do
    if kubectl exec -n "${namespace}" "${CURL_HELPER_POD}" -- \
        curl -sS -m 3 "${url}" >/dev/null 2>&1; then
      echo "  Connectivity OK for ${url}" | tee -a "${results_file}"
      return 0
    fi

    local now
    now=$(date +%s)
    if [ $((now - start_ts)) -ge "${timeout_sec}" ]; then
      echo "  Connectivity to ${url} did NOT succeed within ${timeout_sec}s" \
        | tee -a "${results_file}"
      return 1
    fi

    echo "  ...still waiting for connectivity to ${url}" | tee -a "${results_file}"
    sleep "${CONNECTIVITY_RETRY_DELAY}"
  done
}

# Wait for ALL deployments in the batch simultaneously (parallel poll).
# Mirrors the CAM wait_for_pods_ready approach: single loop checks every
# deployment each iteration and exits only when ALL are Available at once.
# Returns 0 if all became Available, 1 if timeout was reached.
wait_for_deployments_available() {
  local timeout_sec="$1"; shift
  local deploys=("$@")
  local start; start="$(date +%s)"

  while true; do
    local all_ok="true"
    local line=""
    for d in "${deploys[@]}"; do
      local available
      available="$(kubectl get deployment -n "${namespace}" "${d}" \
        -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "")"
      if [ "${available}" = "True" ]; then
        line+="${d}=OK "
      else
        line+="${d}=WAIT "
        all_ok="false"
      fi
    done
    echo "  ...waiting deployments available: ${line}" | tee -a "${results_file}"

    [ "${all_ok}" = "true" ] && return 0

    if [ $(( $(date +%s) - start )) -ge "${timeout_sec}" ]; then
      echo "  ⚠ Deployment availability timeout after ${timeout_sec}s" | tee -a "${results_file}"
      return 1
    fi
    sleep "${POLL_INTERVAL_SEC}"
  done
}

# ---------------------------------------------------------------------------
# Initial setup
# ---------------------------------------------------------------------------

echo "Initial cleanup: deleting any leftover experiment resources in namespace '${namespace}'..." \
  | tee -a "${results_file}"
kubectl delete deploy,svc -n "${namespace}" \
  -l "${EXPERIMENT_LABEL_KEY}=${EXPERIMENT_LABEL_VAL}" \
  --ignore-not-found=true >/dev/null 2>&1 || true
wait_for_experiment_actual_deleted
echo "Initial cleanup done." | tee -a "${results_file}"

ensure_curl_helper_pod

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------

for num_frontends in ${frontend_replicas_values}; do
  echo "============================================================" | tee -a "${results_file}"
  echo "Frontend Deployments (N) = ${num_frontends}, Backend = 1" | tee -a "${results_file}"
  echo "Total Deployments = $((num_frontends + 1))" | tee -a "${results_file}"
  echo "============================================================" | tee -a "${results_file}"

  for (( it=1; it<=iterations; it++ )); do
    echo "------------------------------------------------------------" | tee -a "${results_file}"
    echo "Iteration ${it}/${iterations} for N=${num_frontends}" | tee -a "${results_file}"
    echo "------------------------------------------------------------" | tee -a "${results_file}"

    # Per-iteration cleanup
    kubectl delete deploy,svc -n "${namespace}" \
      -l "${EXPERIMENT_LABEL_KEY}=${EXPERIMENT_LABEL_VAL}" \
      --ignore-not-found=true >/dev/null 2>&1 || true
    wait_for_experiment_actual_deleted

    # -----------------------------------------------------------------------
    # Deploy
    # -----------------------------------------------------------------------
    start_deploy_ms=$(now_ms)

    backend_name="skupper-backend-${num_frontends}-${it}"
    backend_svc="skupper-backend-${num_frontends}-${it}"

    # Backend Deployment + Service
    cat <<MANIFEST | kubectl apply -f - >/dev/null 2>&1 || true
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
MANIFEST

    # N separate frontend Deployments (each 1 replica) — applied in parallel
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

      cat <<MANIFEST | kubectl apply -f - >/dev/null 2>&1 &
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
MANIFEST
    done

    # Wait for all background kubectl apply jobs to finish
    wait

    # Wait for ALL deployments to be Available in parallel (single poll loop)
    echo "  Waiting for ${#deployment_names[@]} deployments to be Available (parallel poll)..." \
      | tee -a "${results_file}"

    availability_ok="true"
    if ! wait_for_deployments_available "${DEPLOY_WAIT_TIMEOUT}" "${deployment_names[@]}"; then
      availability_ok="false"
    fi

    if [ "${availability_ok}" = "true" ]; then
      echo "  All ${#deployment_names[@]} deployments are Available." | tee -a "${results_file}"
    else
      echo "  ⚠ One or more deployments did not become Available." | tee -a "${results_file}"
    fi

    # HTTP connectivity check against first frontend service
    first_frontend_svc="skupper-frontend-${num_frontends}-${it}"
    frontend_url="http://${first_frontend_svc}:8080"
    connectivity_ok="false"
    if [ "${availability_ok}" = "true" ]; then
      if wait_for_connectivity "${frontend_url}" "${CONNECTIVITY_TIMEOUT}"; then
        connectivity_ok="true"
      fi
    else
      echo "  Skipping connectivity check (deployments not all Available)." \
        | tee -a "${results_file}"
    fi

    end_deploy_ms=$(now_ms)
    deploy_duration_ms=$((end_deploy_ms - start_deploy_ms))
    total_deployments=$((num_frontends + 1))

    echo "Deployment completed: N=${num_frontends}, iteration=${it}, deploy_time=${deploy_duration_ms}ms, availability_ok=${availability_ok}, connectivity_ok=${connectivity_ok}, total_deployments=${total_deployments}" \
      | tee -a "${results_file}"

    # -----------------------------------------------------------------------
    # Delete
    # -----------------------------------------------------------------------
    start_delete_ms=$(now_ms)

    kubectl delete deploy,svc -n "${namespace}" \
      -l "${EXPERIMENT_LABEL_KEY}=${EXPERIMENT_LABEL_VAL}" \
      --ignore-not-found=true >/dev/null 2>&1 || true

    wait_for_experiment_actual_deleted

    end_delete_ms=$(now_ms)
    delete_duration_ms=$((end_delete_ms - start_delete_ms))

    echo "Deletion completed: N=${num_frontends}, iteration=${it}, delete_time=${delete_duration_ms}ms" \
      | tee -a "${results_file}"
    echo "${it},${num_frontends},${deploy_duration_ms},${delete_duration_ms},${availability_ok},${connectivity_ok},${total_deployments}" \
      >> "${results_file}"
    echo | tee -a "${results_file}"

    if [ "${it}" -lt "${iterations}" ]; then
      echo "Sleeping ${SLEEP_BETWEEN_ITERATIONS}s before next iteration..." | tee -a "${results_file}"
      sleep "${SLEEP_BETWEEN_ITERATIONS}"
    fi
  done
done

echo "===========================================" | tee -a "${results_file}"
echo "Backend=1, Frontend=N SEPARATE DEPLOYMENTS experiment (non-CAM) completed." | tee -a "${results_file}"
echo "Results written to: ${results_file}" | tee -a "${results_file}"
echo "==========================================="
