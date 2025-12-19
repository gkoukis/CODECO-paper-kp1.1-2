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

# ---------------------------------------------
# Bookinfo non-CAM KPI Experiment
# - Measures time until: deployments Available + productpage functional (HTTP via API proxy)
# - Measures deletion time of created resources
# - Labels everything created in the namespace (best with a dedicated namespace)
# - Cleans up on Ctrl+C
#
# Usage:
#   ./measure_bookinfo_noncam_cheackavail.sh <yaml_file> <iterations> [namespace] [sleep_between_iterations]
#
# Example:
#   ./measure_bookinfo_noncam_cheackavail.sh bookinfo.yaml 6 bookinfo 60
# ---------------------------------------------

usage() {
  echo "Usage: $0 <yaml_file> <iterations> [namespace] [sleep_between_iterations]"
  echo "  yaml_file                : Bookinfo YAML (non-CAM) (e.g., bookinfo.yaml)"
  echo "  iterations               : number of iterations (e.g., 3)"
  echo "  namespace                : target namespace (default: bookinfo)"
  echo "  sleep_between_iterations : seconds (default: 10)"
}

if [ $# -lt 2 ]; then
  usage
  exit 1
fi

YAML_FILE="$1"
ITERATIONS="$2"
NAMESPACE="${3:-bookinfo}"
SLEEP_BETWEEN="${4:-10}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "❌ kubectl not found in PATH."
  exit 1
fi

if [ ! -f "${YAML_FILE}" ]; then
  echo "❌ YAML file not found: ${YAML_FILE}"
  exit 1
fi

LABEL_KEY="experiment"
LABEL_VAL="bookinfo-noncam-kpi"
LABEL_SEL="${LABEL_KEY}=${LABEL_VAL}"

timestamp_now=$(date '+%Y%m%d_%H%M%S')
results_file="bookinfo_noncam_kpi_${timestamp_now}.txt"

echo "-------------------------------------------" | tee -a "${results_file}"
echo "Bookinfo non-CAM KPI Experiment (v4 - Available + functional via API proxy)" | tee -a "${results_file}"
echo "YAML file            : ${YAML_FILE}" | tee -a "${results_file}"
echo "Namespace            : ${NAMESPACE}" | tee -a "${results_file}"
echo "Iterations           : ${ITERATIONS}" | tee -a "${results_file}"
echo "Sleep between iters  : ${SLEEP_BETWEEN}s" | tee -a "${results_file}"
echo "Label                : ${LABEL_SEL}" | tee -a "${results_file}"
echo "-------------------------------------------" | tee -a "${results_file}"
echo "iteration,ready_functional_time_ms,delete_time_ms,http_ok" >> "${results_file}"

# -----------------------------
# Helper: create namespace if missing
# -----------------------------
ensure_namespace() {
  if ! kubectl get ns "${NAMESPACE}" >/dev/null 2>&1; then
    echo "Namespace ${NAMESPACE} does not exist. Creating..."
    kubectl create ns "${NAMESPACE}" >/dev/null
  fi
}

# -----------------------------
# Helper: label everything in namespace (assumes namespace is dedicated)
# -----------------------------
label_namespace_objects() {
  # Label common types created by bookinfo.yaml
  kubectl label deploy -n "${NAMESPACE}" --all --overwrite "${LABEL_SEL}" >/dev/null 2>&1 || true
  kubectl label svc  -n "${NAMESPACE}" --all --overwrite "${LABEL_SEL}" >/dev/null 2>&1 || true
  kubectl label sa   -n "${NAMESPACE}" --all --overwrite "${LABEL_SEL}" >/dev/null 2>&1 || true
}

# -----------------------------
# Helper: cleanup labeled objects (best-effort)
# -----------------------------
cleanup_labeled() {
  kubectl delete deploy,svc,sa -n "${NAMESPACE}" -l "${LABEL_SEL}" --ignore-not-found=true >/dev/null 2>&1 || true
}

# -----------------------------
# Helper: wait until no labeled objects remain (and no pods remain)
# -----------------------------
wait_cleanup_done() {
  local timeout_sec=300
  local deadline=$(( $(date +%s) + timeout_sec ))

  while [ "$(date +%s)" -lt "${deadline}" ]; do
    local objs pods
    objs=$(kubectl get deploy,svc,sa -n "${NAMESPACE}" -l "${LABEL_SEL}" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    pods=$(kubectl get pods -n "${NAMESPACE}" --no-headers 2>/dev/null | wc -l | tr -d ' ')

    objs="${objs:-0}"
    pods="${pods:-0}"

    if [ "${objs}" -eq 0 ] && [ "${pods}" -eq 0 ]; then
      return 0
    fi

    echo "  Waiting cleanup... labeled objects=${objs}, pods=${pods}"
    sleep 0.5
  done

  echo "⚠ Cleanup timeout reached; some objects may remain."
  return 1
}

# -----------------------------
# Helper: wait for all deployments in namespace to become Available
# -----------------------------
wait_deployments_available() {
  local timeout_sec=600
  local deadline=$(( $(date +%s) + timeout_sec ))

  while [ "$(date +%s)" -lt "${deadline}" ]; do
    mapfile -t deps < <(kubectl get deploy -n "${NAMESPACE}" -o name 2>/dev/null || true)

    if [ "${#deps[@]}" -eq 0 ]; then
      echo "  No deployments found yet..."
      sleep 1
      continue
    fi

    local not_ready=0
    for d in "${deps[@]}"; do
      # If rollout status fails, treat as not ready yet
      if ! kubectl rollout status -n "${NAMESPACE}" "${d}" --timeout=2s >/dev/null 2>&1; then
        not_ready=$((not_ready + 1))
      fi
    done

    if [ "${not_ready}" -eq 0 ]; then
      return 0
    fi

    echo "  Deployments not yet Available: ${not_ready}/${#deps[@]}"
    sleep 2
  done

  echo "❌ Timeout waiting for deployments to become Available."
  kubectl get deploy -n "${NAMESPACE}" -o wide || true
  return 1
}

# -----------------------------
# Helper: functional check via Kubernetes API proxy
# (No NodePort, no extra curl pod.)
# -----------------------------
wait_productpage_functional() {
  local timeout_sec=300
  local deadline=$(( $(date +%s) + timeout_sec ))

  local proxy_path="/api/v1/namespaces/${NAMESPACE}/services/http:productpage:9080/proxy/productpage"

  while [ "$(date +%s)" -lt "${deadline}" ]; do
    if kubectl get --raw "${proxy_path}" >/dev/null 2>&1; then
      echo "  Functional check OK: productpage responds via API proxy."
      return 0
    fi
    echo "  Waiting for productpage to become functional..."
    sleep 2
  done

  echo "❌ Timeout waiting for productpage functional response."
  return 1
}

# -----------------------------
# Trap: ensure cleanup on interrupt
# -----------------------------
on_exit() {
  echo
  echo "Caught exit/interrupt. Cleaning up labeled resources (best-effort)..."
  cleanup_labeled
  wait_cleanup_done || true
}
trap on_exit INT TERM

# -----------------------------
# Main
# -----------------------------
ensure_namespace

for (( it=1; it<=ITERATIONS; it++ )); do
  echo "============================================================" | tee -a "${results_file}"
  echo "Iteration ${it}/${ITERATIONS}" | tee -a "${results_file}"
  echo "============================================================" | tee -a "${results_file}"

  echo "[Stage] Cleanup labeled leftovers..." | tee -a "${results_file}"
  cleanup_labeled
  wait_cleanup_done || true

  start_ready_ms=$(date +%s%3N)

  echo "[Stage] Apply YAML..." | tee -a "${results_file}"
  kubectl apply -n "${NAMESPACE}" -f "${YAML_FILE}" >/dev/null

  # Label after apply so future cleanup is deterministic
  label_namespace_objects

  echo "[Stage] Waiting for deployments to be Available..." | tee -a "${results_file}"
  wait_deployments_available

  echo "[Stage] Waiting for functional productpage (API proxy)..." | tee -a "${results_file}"
  http_ok="false"
  if wait_productpage_functional; then
    http_ok="true"
  fi

  end_ready_ms=$(date +%s%3N)
  ready_functional_ms=$((end_ready_ms - start_ready_ms))

  echo "Ready+Functional completed: iteration=${it}, time=${ready_functional_ms} ms, http_ok=${http_ok}" | tee -a "${results_file}"

  # -------------------------
  # Deletion timing
  # -------------------------
  start_del_ms=$(date +%s%3N)

  echo "[Stage] Deleting labeled resources..." | tee -a "${results_file}"
  cleanup_labeled
  wait_cleanup_done || true

  end_del_ms=$(date +%s%3N)
  delete_ms=$((end_del_ms - start_del_ms))

  echo "Deletion completed: iteration=${it}, time=${delete_ms} ms" | tee -a "${results_file}"

  echo "${it},${ready_functional_ms},${delete_ms},${http_ok}" >> "${results_file}"

  echo "Sleeping ${SLEEP_BETWEEN} seconds before next iteration..." | tee -a "${results_file}"
  sleep "${SLEEP_BETWEEN}"
done

echo "==========================================="
echo "Bookinfo non-CAM KPI experiment completed."
echo "Results written to: ${results_file}"
echo "==========================================="
