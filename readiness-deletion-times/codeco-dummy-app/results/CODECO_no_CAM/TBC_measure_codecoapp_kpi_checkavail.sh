#!/bin/bash

# Non-CAM version:
#  - 1 backend (hello-world backend)
#  - N frontend pods (scaled via Deployment replicas)
#
# For each N and each iteration:
#  - Deploy backend + frontend
#  - Wait for Deployments to be Available
#  - Additionally check that the frontend can be reached over HTTP
#    (and, via BACKEND_URL, should talk to the backend)
#  - Measure deployment time (ms) until "working" state
#  - Delete all experiment resources
#  - Measure deletion time (ms)
#
# Results go to:
#   codeco_dummy_app_<timestamp>.txt
#
# Example:
#   ./measure_codecoapp_kpi.sh 2 "1 10" skupper-demo

set -euo pipefail

usage() {
  echo "Usage: $0 <iterations> <frontend_replicas_values> [namespace]"
  echo "  iterations              : number of iterations per replica count (e.g. 3)"
  echo "  frontend_replicas_values: quoted list of frontend replica counts (e.g. \"1 10 20\")"
  echo "  namespace               : (optional) namespace, default: skupper-demo"
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
CONNECTIVITY_TIMEOUT=60      # seconds to wait for HTTP OK from frontend
CONNECTIVITY_RETRY_DELAY=2   # seconds between attempts
CURL_HELPER_POD="curl-tester"

# Results file
timestamp_now=$(date '+%Y%m%d_%H%M%S')
results_file="codeco_dummy_app_${timestamp_now}.txt"

echo "-------------------------------------------" | tee -a "${results_file}"
echo "Backend=1, Frontend=N Scaling Experiment (non-CAM, with connectivity check)" | tee -a "${results_file}"
echo "Timestamp         : ${timestamp_now}" | tee -a "${results_file}"
echo "Namespace         : ${namespace}" | tee -a "${results_file}"
echo "Iterations        : ${iterations}" | tee -a "${results_file}"
echo "Frontend replicas : ${frontend_replicas_values}" | tee -a "${results_file}"
echo "Connectivity timeout (s): ${CONNECTIVITY_TIMEOUT}" | tee -a "${results_file}"
echo "-------------------------------------------" | tee -a "${results_file}"
echo "iteration,frontend_replicas,deploy_time_ms,delete_time_ms,connectivity_ok" >> "${results_file}"

EXPERIMENT_LABEL_KEY="experiment"
EXPERIMENT_LABEL_VAL="codeco_dummy_app"

# Wait until ALL experiment resources in this namespace are gone
wait_for_experiment_resources_deleted() {
  while true; do
    local remaining
    remaining=$(kubectl get pods,deploy,svc -n "${namespace}" \
      -l "${EXPERIMENT_LABEL_KEY}=${EXPERIMENT_LABEL_VAL}" \
      --no-headers 2>/dev/null | wc -l | tr -d ' ')

    [ -z "${remaining}" ] && remaining=0

    if [ "${remaining}" -eq 0 ]; then
      break
    fi

    echo "  Waiting for experiment resources to be deleted... remaining: ${remaining}"
    sleep 0.2
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
    # Run curl inside helper pod; non-zero exit is allowed here
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
wait_for_experiment_resources_deleted
echo "Initial cleanup done."

# Ensure curl helper pod exists and is ready
ensure_curl_helper_pod

for replicas in ${frontend_replicas_values}; do
  echo "============================================================" | tee -a "${results_file}"
  echo "Frontend replicas (N) = ${replicas}, Backend = 1" | tee -a "${results_file}"
  echo "============================================================" | tee -a "${results_file}"

  for (( it=1; it<=iterations; it++ )); do
    echo "------------------------------------------------------------" | tee -a "${results_file}"
    echo "Iteration ${it}/${iterations} for N=${replicas}" | tee -a "${results_file}"
    echo "------------------------------------------------------------" | tee -a "${results_file}"

    # Per-iteration cleanup: ensure no previous experiment resources linger
    kubectl delete deploy,svc -n "${namespace}" \
      -l "${EXPERIMENT_LABEL_KEY}=${EXPERIMENT_LABEL_VAL}" \
      --ignore-not-found=true >/dev/null 2>&1 || true
    wait_for_experiment_resources_deleted

    # -------------------------
    # Deployment timing (including connectivity check)
    # -------------------------
    start_deploy_ms=$(date +%s%3N)

    backend_name="skupper-backend-${replicas}-${it}"
    backend_svc="skupper-backend-${replicas}-${it}"

    frontend_name="skupper-frontend-${replicas}-${it}"
    frontend_svc="skupper-frontend-${replicas}-${it}"

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
    replica-group: "${replicas}"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: skupper-backend
      run: "${it}"
      replica-group: "${replicas}"
  template:
    metadata:
      labels:
        app: skupper-backend
        run: "${it}"
        replica-group: "${replicas}"
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
    replica-group: "${replicas}"
spec:
  selector:
    app: skupper-backend
    run: "${it}"
    replica-group: "${replicas}"
  ports:
  - port: 8080
    targetPort: 8080
EOF

    # Frontend Deployment + Service (N replicas)
    cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${frontend_name}
  namespace: ${namespace}
  labels:
    app: skupper-frontend
    ${EXPERIMENT_LABEL_KEY}: ${EXPERIMENT_LABEL_VAL}
    run: "${it}"
    replica-group: "${replicas}"
spec:
  replicas: ${replicas}
  selector:
    matchLabels:
      app: skupper-frontend
      run: "${it}"
      replica-group: "${replicas}"
  template:
    metadata:
      labels:
        app: skupper-frontend
        run: "${it}"
        replica-group: "${replicas}"
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
    replica-group: "${replicas}"
spec:
  selector:
    app: skupper-frontend
    run: "${it}"
    replica-group: "${replicas}"
  ports:
  - port: 8080
    targetPort: 8080
EOF

    # Wait for both deployments to be Available (all pods Ready)
    kubectl wait --for=condition=available deployment/"${backend_name}" \
      -n "${namespace}" --timeout=600s >/dev/null 2>&1
    kubectl wait --for=condition=available deployment/"${frontend_name}" \
      -n "${namespace}" --timeout=600s >/dev/null 2>&1

    # Now also wait until frontend is actually reachable over HTTP
    frontend_url="http://${frontend_svc}:8080"
    connectivity_ok="true"
    if ! wait_for_connectivity "${frontend_url}" "${CONNECTIVITY_TIMEOUT}"; then
      connectivity_ok="false"
    fi

    end_deploy_ms=$(date +%s%3N)
    deploy_duration_ms=$((end_deploy_ms - start_deploy_ms))

    echo "Deployment completed: N=${replicas}, iteration=${it}, deploy_time=${deploy_duration_ms} ms, connectivity_ok=${connectivity_ok}" | tee -a "${results_file}"

    # -------------------------
    # Deletion timing
    # -------------------------
    start_delete_ms=$(date +%s%3N)

    kubectl delete deploy,svc -n "${namespace}" \
      -l "${EXPERIMENT_LABEL_KEY}=${EXPERIMENT_LABEL_VAL}" \
      --ignore-not-found=true >/dev/null 2>&1 || true

    wait_for_experiment_resources_deleted

    end_delete_ms=$(date +%s%3N)
    delete_duration_ms=$((end_delete_ms - start_delete_ms))

    echo "Deletion completed: N=${replicas}, iteration=${it}, delete_time=${delete_duration_ms} ms" | tee -a "${results_file}"
    echo "${it},${replicas},${deploy_duration_ms},${delete_duration_ms},${connectivity_ok}" >> "${results_file}"
    echo | tee -a "${results_file}"

    echo "Sleeping 60 seconds before next iteration..."
    sleep 60

  done
done

echo "==========================================="
echo "Backend=1, Frontend=N scaling experiment (non-CAM, with connectivity check) completed."
echo "Results written to: ${results_file}"
echo "==========================================="