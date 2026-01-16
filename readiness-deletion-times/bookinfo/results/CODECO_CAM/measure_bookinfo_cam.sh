#!/bin/bash
set -euo pipefail

# Measurement script for 6-microservice bookinfo (fair comparison with vanilla K8s)
# Expected pods: details, ratings, reviews-v1, reviews-v2, reviews-v3, productpage
#
# Features:
# - Deletes CodecoApp after each iteration to prevent accumulation
# - Checks acm-operator-controller-manager health before next iteration
# - 60 second sleep between iterations
#
# Usage:
#   ./measure_bookinfo_cam.sh <yaml_file> <iterations> [namespace] [node_ip]
#
# Example:
#   ./measure_bookinfo_cam.sh codecoapp-bookinfo-cam.yaml 6 he-codeco-acm

usage() {
  echo "Usage: $0 <yaml_file> <iterations> [namespace] [node_ip]"
  echo "Example: $0 codecoapp-bookinfo-cam.yaml 6 bookinfo"
}

if [ $# -lt 2 ]; then usage; exit 1; fi

YAML_FILE="$1"
ITERATIONS="$2"
NAMESPACE="${3:-he-codeco-acm}"
NODE_IP="${4:-}"

# Timeouts
PODS_READY_TIMEOUT_SEC=600
HTTP_TIMEOUT_SEC=240
HTTP_RETRY_DELAY_SEC=2
SLEEP_BETWEEN_ITERS_SEC=60
OPERATOR_CHECK_TIMEOUT_SEC=120

PRODUCTPAGE_NODEPORT="30000"

# Pod prefix used by ACM operator
POD_PREFIX="acm-swm-app"

# 6 services matching vanilla K8s bookinfo
SERVICES=("productpage" "details" "ratings" "reviews-v1" "reviews-v2" "reviews-v3")

# Operator namespace and label selector
OPERATOR_NAMESPACE="${OPERATOR_NAMESPACE:-he-codeco-acm}"
OPERATOR_LABEL="${OPERATOR_LABEL:-control-plane=controller-manager}"

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

# Extract CodecoApp name from YAML
CODECOAPP_NAME="$(awk '
  $1=="kind:" && $2=="CodecoApp"{incodeco=1}
  incodeco && $1=="name:" {print $2; exit}
' "${YAML_FILE}" | tr -d '"')"
[ -n "${CODECOAPP_NAME}" ] || { echo "❌ Could not detect CodecoApp name from YAML."; exit 1; }

timestamp_now=$(date '+%Y%m%d_%H%M%S')
RESULTS_FILE="bookinfo_cam_${timestamp_now}.txt"

echo "-------------------------------------------" | tee -a "${RESULTS_FILE}"
echo "Bookinfo CAM KPI Experiment (6 Microservices - Fair Comparison)" | tee -a "${RESULTS_FILE}"
echo "YAML file           : ${YAML_FILE}" | tee -a "${RESULTS_FILE}"
echo "Namespace           : ${NAMESPACE}" | tee -a "${RESULTS_FILE}"
echo "CodecoApp name      : ${CODECOAPP_NAME}" | tee -a "${RESULTS_FILE}"
echo "Node IP             : ${NODE_IP}" | tee -a "${RESULTS_FILE}"
echo "Productpage NodePort: ${PRODUCTPAGE_NODEPORT}" | tee -a "${RESULTS_FILE}"
echo "Iterations          : ${ITERATIONS}" | tee -a "${RESULTS_FILE}"
echo "Pod prefix          : ${POD_PREFIX}" | tee -a "${RESULTS_FILE}"
echo "Expected services   : ${SERVICES[*]}" | tee -a "${RESULTS_FILE}"
echo "Total pods expected : ${#SERVICES[@]}" | tee -a "${RESULTS_FILE}"
echo "Operator namespace  : ${OPERATOR_NAMESPACE}" | tee -a "${RESULTS_FILE}"
echo "-------------------------------------------" | tee -a "${RESULTS_FILE}"
echo "iteration,pods_ready_time_ms,functional_time_ms,delete_time_ms,http_ok,all_pods_found" >> "${RESULTS_FILE}"

ensure_ns() {
  if ! kubectl get ns "${NAMESPACE}" >/dev/null 2>&1; then
    kubectl create ns "${NAMESPACE}" >/dev/null
  fi
}

pods_for_service() {
  local svc="$1"
  kubectl get pods -n "${NAMESPACE}" -o name 2>/dev/null \
    | sed 's|^pod/||' \
    | grep -E "^${POD_PREFIX}-${svc}$" || true
}

# Check if the acm-operator-controller-manager is healthy (not in CrashLoopBackOff)
check_operator_health() {
  local timeout_sec="${1:-${OPERATOR_CHECK_TIMEOUT_SEC}}"
  local deadline=$(( $(date +%s) + timeout_sec ))

  echo "  Checking acm-operator-controller-manager health..."

  while true; do
    # Find the operator pod (name may vary)
    local operator_pod
    operator_pod=$(kubectl get pods -n "${OPERATOR_NAMESPACE}" -l "${OPERATOR_LABEL}" -o name 2>/dev/null | head -1 | sed 's|^pod/||' || true)

    # Also try by name pattern if label doesn't work
    if [ -z "${operator_pod}" ]; then
      operator_pod=$(kubectl get pods -n "${OPERATOR_NAMESPACE}" -o name 2>/dev/null | grep "acm-operator-controller" | head -1 | sed 's|^pod/||' || true)
    fi

    if [ -z "${operator_pod}" ]; then
      echo "  ⚠ Could not find acm-operator-controller-manager pod"
      if [ "$(date +%s)" -ge "${deadline}" ]; then
        echo "  ❌ Timeout waiting for operator pod to appear"
        return 1
      fi
      sleep 2
      continue
    fi

    # Get pod status
    local pod_status
    pod_status=$(kubectl get pod "${operator_pod}" -n "${OPERATOR_NAMESPACE}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")

    # Check for CrashLoopBackOff in container statuses
    local container_status
    container_status=$(kubectl get pod "${operator_pod}" -n "${OPERATOR_NAMESPACE}" -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null || echo "")

    # Check if pod is Ready
    local ready_status
    ready_status=$(kubectl get pod "${operator_pod}" -n "${OPERATOR_NAMESPACE}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")

    if [ "${container_status}" = "CrashLoopBackOff" ]; then
      echo "  ⚠ Operator pod ${operator_pod} is in CrashLoopBackOff, waiting..."
    elif [ "${pod_status}" = "Running" ] && [ "${ready_status}" = "True" ]; then
      echo "  ✓ Operator pod ${operator_pod} is healthy (Running and Ready)"
      return 0
    else
      echo "  ...Operator pod status: ${pod_status}, ready: ${ready_status}, waiting..."
    fi

    if [ "$(date +%s)" -ge "${deadline}" ]; then
      echo "  ❌ Timeout waiting for operator to become healthy"
      return 1
    fi

    sleep 3
  done
}

cleanup_all() {
  echo "Cleaning up resources (best-effort)..."

  # Delete CodecoApp explicitly
  kubectl delete codecoapp "${CODECOAPP_NAME}" -n "${NAMESPACE}" --ignore-not-found=true --wait=false >/dev/null 2>&1 || true

  # Delete other YAML resources
  kubectl delete -f "${YAML_FILE}" -n "${NAMESPACE}" --ignore-not-found=true --wait=false >/dev/null 2>&1 || true

  # Delete pods by name prefix
  for svc in "${SERVICES[@]}"; do
    local p
    p="$(pods_for_service "${svc}")"
    if [ -n "$p" ]; then
      kubectl delete pod "$p" -n "${NAMESPACE}" --ignore-not-found=true --wait=false >/dev/null 2>&1 || true
    fi
  done

  local deadline=$(( $(date +%s) + 180 ))
  while true; do
    local ca_exists=0
    if kubectl get codecoapp "${CODECOAPP_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then ca_exists=1; fi

    local svc_cnt
    svc_cnt=$(kubectl get svc -n "${NAMESPACE}" productpage details reviews ratings \
      --ignore-not-found --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')

    local pod_cnt=0
    for s in "${SERVICES[@]}"; do
      local p
      p="$(pods_for_service "$s")"
      [ -n "$p" ] && pod_cnt=$((pod_cnt + 1))
    done

    if [ "${ca_exists}" -eq 0 ] && [ "${svc_cnt:-0}" -eq 0 ] && [ "${pod_cnt}" -eq 0 ]; then
      echo "  ✓ Cleanup complete."
      return 0
    fi

    if [ "$(date +%s)" -ge "${deadline}" ]; then
      echo "  ⚠ Cleanup timeout; continuing. remaining: codecoapp=${ca_exists}, services=${svc_cnt:-0}, pods=${pod_cnt}"
      return 0
    fi

    echo "  Waiting cleanup... codecoapp=${ca_exists}, services=${svc_cnt:-0}, pods=${pod_cnt}"
    sleep 2
  done
}

# Wait for CodecoApp to be fully deleted
wait_for_codecoapp_deleted() {
  local timeout_sec="${1:-300}"
  local deadline=$(( $(date +%s) + timeout_sec ))

  echo "  Waiting for CodecoApp ${CODECOAPP_NAME} to be fully deleted..."

  while true; do
    if ! kubectl get codecoapp "${CODECOAPP_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
      echo "  ✓ CodecoApp ${CODECOAPP_NAME} deleted."
      return 0
    fi

    if [ "$(date +%s)" -ge "${deadline}" ]; then
      echo "  ⚠ Timeout waiting for CodecoApp deletion"
      return 1
    fi

    sleep 1
  done
}

wait_for_pods_ready_and_labeled() {
  local deadline=$(( $(date +%s) + PODS_READY_TIMEOUT_SEC ))
  local all_found="true"

  for svc in "${SERVICES[@]}"; do
    echo "  Waiting for pod '${POD_PREFIX}-${svc}'..."

    while true; do
      local p
      p="$(pods_for_service "${svc}")"

      if [ -n "${p}" ]; then
        kubectl label pod "$p" -n "${NAMESPACE}" "serviceName=${svc}" --overwrite >/dev/null 2>&1 || true

        # For reviews versions, also add app=reviews label for the combined reviews Service
        if [[ "${svc}" == reviews-* ]]; then
          kubectl label pod "$p" -n "${NAMESPACE}" "app=reviews" --overwrite >/dev/null 2>&1 || true
        fi

        if kubectl wait --for=condition=Ready pod/"$p" -n "${NAMESPACE}" --timeout=60s >/dev/null 2>&1; then
          echo "  ✓ Pod Ready: ${p}"
          break
        fi
      fi

      if [ "$(date +%s)" -ge "${deadline}" ]; then
        echo "  ❌ Timeout waiting for pod ${POD_PREFIX}-${svc}"
        all_found="false"
        break
      fi
      sleep 1
    done
  done

  [ "${all_found}" = "true" ] && return 0 || return 1
}

wait_for_http_ok() {
  local start=$(date +%s)
  local proxy_path="/api/v1/namespaces/${NAMESPACE}/services/http:productpage:9080/proxy/productpage"
  local nodeport_url="http://${NODE_IP}:${PRODUCTPAGE_NODEPORT}/productpage"

  echo "  Checking HTTP connectivity..."

  while true; do
    if kubectl get --raw "${proxy_path}" >/dev/null 2>&1; then
      echo "  ✓ HTTP OK via API proxy"
      return 0
    fi

    if curl -fsS -m 3 "${nodeport_url}" >/dev/null 2>&1; then
      echo "  ✓ HTTP OK via NodePort"
      return 0
    fi

    if [ $(( $(date +%s) - start )) -ge "${HTTP_TIMEOUT_SEC}" ]; then
      echo "  ❌ HTTP timeout after ${HTTP_TIMEOUT_SEC}s"
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
      local p
      p="$(pods_for_service "$s")"
      [ -n "$p" ] && pod_cnt=$((pod_cnt + 1))
    done
    remaining=$((remaining + pod_cnt))

    if [ "${remaining}" -eq 0 ]; then
      return 0
    fi

    if [ "$(date +%s)" -ge "${deadline}" ]; then
      echo "  ⚠ Deletion timeout; remaining: ${remaining}"
      return 1
    fi
    sleep 1
  done
}

# ============================================================
# Main
# ============================================================
ensure_ns

# Initial operator health check
echo "Initial operator health check..."
check_operator_health || { echo "❌ Operator not healthy at start. Exiting."; exit 1; }

for (( it=1; it<=ITERATIONS; it++ )); do
  echo "============================================================" | tee -a "${RESULTS_FILE}"
  echo "Iteration ${it}/${ITERATIONS}" | tee -a "${RESULTS_FILE}"
  echo "============================================================" | tee -a "${RESULTS_FILE}"

  cleanup_all

  # ========== TIMING STARTS HERE ==========
  start_apply_ms=$(date +%s%3N)

  echo "[Stage] Apply YAML..." | tee -a "${RESULTS_FILE}"
  kubectl apply -f "${YAML_FILE}" >/dev/null

  echo "[Stage] Waiting for pods to be Ready..." | tee -a "${RESULTS_FILE}"
  all_pods_found="true"
  if ! wait_for_pods_ready_and_labeled; then
    all_pods_found="false"
  fi

  end_pods_ready_ms=$(date +%s%3N)
  pods_ready_ms=$((end_pods_ready_ms - start_apply_ms))

  echo "[Stage] Waiting for HTTP functional check..." | tee -a "${RESULTS_FILE}"
  http_ok="true"
  if ! wait_for_http_ok; then
    http_ok="false"
  fi

  end_functional_ms=$(date +%s%3N)
  functional_ms=$((end_functional_ms - start_apply_ms))

  echo "Pods Ready: ${pods_ready_ms} ms | Functional: ${functional_ms} ms | http_ok=${http_ok} | all_pods=${all_pods_found}" | tee -a "${RESULTS_FILE}"

  # ---------- Deletion timing ----------
  start_del_ms=$(date +%s%3N)

  echo "[Stage] Deleting resources..." | tee -a "${RESULTS_FILE}"
  kubectl delete codecoapp "${CODECOAPP_NAME}" -n "${NAMESPACE}" --ignore-not-found=true --wait=false >/dev/null 2>&1 || true
  kubectl delete -f "${YAML_FILE}" -n "${NAMESPACE}" --ignore-not-found=true --wait=false >/dev/null 2>&1 || true

  wait_for_deleted || true

  end_del_ms=$(date +%s%3N)
  del_ms=$((end_del_ms - start_del_ms))

  echo "Deletion completed: ${del_ms} ms" | tee -a "${RESULTS_FILE}"
  echo "${it},${pods_ready_ms},${functional_ms},${del_ms},${http_ok},${all_pods_found}" >> "${RESULTS_FILE}"
  # ========== TIMING ENDS HERE ==========

  # ========== POST-MEASUREMENT CLEANUP (does not affect timing) ==========
  if [ "${it}" -lt "${ITERATIONS}" ]; then
    echo "" | tee -a "${RESULTS_FILE}"
    echo "[Post-measurement] Ensuring CodecoApp is fully deleted..." | tee -a "${RESULTS_FILE}"
    wait_for_codecoapp_deleted 120 || true

    echo "[Post-measurement] Checking operator health before next iteration..." | tee -a "${RESULTS_FILE}"
    if ! check_operator_health; then
      echo "  ⚠ Operator unhealthy, waiting additional time..." | tee -a "${RESULTS_FILE}"
      sleep 30
      check_operator_health || echo "  ⚠ Operator still unhealthy, proceeding anyway..." | tee -a "${RESULTS_FILE}"
    fi

    echo "[Post-measurement] Sleeping ${SLEEP_BETWEEN_ITERS_SEC} seconds before next iteration..." | tee -a "${RESULTS_FILE}"
    sleep "${SLEEP_BETWEEN_ITERS_SEC}"
  fi
done

echo "==========================================="
echo "Bookinfo CAM KPI experiment (6 microservices - fair comparison) completed."
echo "Results written to: ${RESULTS_FILE}"
echo "==========================================="