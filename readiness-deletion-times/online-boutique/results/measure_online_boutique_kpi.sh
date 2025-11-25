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

### ADD DESCRIPTION

set -euo pipefail

#############################
# CONFIGURATION
#############################
NS_DEFAULT="online-boutique"
#MANIFEST_DEFAULT="./online-boutique.yaml"
MANIFEST_DEFAULT="./online-boutique-nogen.yaml"
ITERATIONS_DEFAULT=1

CSV_FILE_DEFAULT="online-boutique_kpi_results.csv"
TXT_FILE_DEFAULT="online-boutique_kpi_results.txt"

# Use internal ClusterIP service and the same path as readinessProbe
FRONTEND_SVC_NAME="frontend"
FRONTEND_LOCAL_PORT=8080
FRONTEND_PATH="/_healthz"

#############################
# USAGE
#############################
usage() {
  echo "Usage: $0 [iterations] [namespace] [manifest]"
  echo ""
  echo "Defaults:"
  echo "  iterations: ${ITERATIONS_DEFAULT}"
  echo "  namespace:  ${NS_DEFAULT}"
  echo "  manifest:   ${MANIFEST_DEFAULT}"
  echo ""
  echo "Examples:"
  echo "  $0"
  echo "  $0 5"
  echo "  $0 3 online-boutique ./online-boutique.yaml"
}

#############################
# ARGUMENTS
#############################
ITERATIONS="${1:-$ITERATIONS_DEFAULT}"
NS="${2:-$NS_DEFAULT}"
MANIFEST="${3:-$MANIFEST_DEFAULT}"

if ! [[ "$ITERATIONS" =~ ^[0-9]+$ ]]; then
  echo "ERROR: iterations must be an integer. Got: '$ITERATIONS'"
  usage
  exit 1
fi

#############################
# DEPENDENCY CHECKS
#############################
if ! command -v kubectl >/dev/null 2>&1; then
  echo "ERROR: kubectl not found in PATH."
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl not found in PATH."
  exit 1
fi

USE_BC=0
if command -v bc >/dev/null 2>&1; then
  USE_BC=1
fi

if [[ ! -f "$MANIFEST" ]]; then
  echo "ERROR: Manifest file not found: $MANIFEST"
  exit 1
fi

#############################
# HELPER: TIME DIFF (3 decimals)
#############################
time_diff() {
  local start="$1"
  local end="$2"

  if [[ "$USE_BC" -eq 1 ]]; then
    echo "scale=3; $end - $start" | bc
  else
    local start_int=${start%%.*}
    local end_int=${end%%.*}
    printf "%.3f\n" $(( end_int - start_int ))
  fi
}

#############################
# CSV/TXT INIT (APPEND-ONLY)
#############################
CSV_FILE="$CSV_FILE_DEFAULT"
TXT_FILE="$TXT_FILE_DEFAULT"

# Create with header only if not exists
if [[ ! -f "$CSV_FILE" ]]; then
  echo "run_timestamp,iteration,namespace,deployment_time_s,deletion_time_s" > "$CSV_FILE"
fi

if [[ ! -f "$TXT_FILE" ]]; then
  {
    echo "Online Boutique KPI results"
    echo "==========================="
    echo ""
  } > "$TXT_FILE"
fi

#############################
# NAMESPACE ENSURE
#############################
if ! kubectl get ns "$NS" >/dev/null 2>&1; then
  echo "[*] Namespace '$NS' does not exist. Creating..."
  kubectl create namespace "$NS"
else
  echo "[*] Namespace '$NS' already exists."
fi

#############################
# PORT-FORWARD CLEANUP
#############################
PF_PID=""
cleanup_pf() {
  if [[ -n "${PF_PID:-}" ]] && kill -0 "$PF_PID" >/dev/null 2>&1; then
    kill "$PF_PID" || true
  fi
}
trap cleanup_pf EXIT

#############################
# MAIN HEADER
#############################
echo "======================================================="
echo " ONLINE BOUTIQUE KPI1 MEASUREMENT"
echo " Namespace : $NS"
echo " Manifest  : $MANIFEST"
echo " Iterations: $ITERATIONS"
echo " CSV file  : $CSV_FILE"
echo " TXT file  : $TXT_FILE"
echo "======================================================="

deploy_times=()
delete_times=()

for ((i=1; i<=ITERATIONS; i++)); do
  echo ""
  echo "================ ITERATION $i/$ITERATIONS ================"
  run_ts="$(date +%Y-%m-%dT%H:%M:%S)"

  ###########################################################
  # CLEANUP BEFORE DEPLOY
  ###########################################################
  echo "[*] Cleaning previous resources (if any) in '$NS'..."
  kubectl delete -f "$MANIFEST" -n "$NS" --ignore-not-found=true >/dev/null 2>&1 || true

  echo "[*] Waiting for all existing pods in '$NS' to terminate..."
  while true; do
    pod_count=$(kubectl get pods -n "$NS" --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')
    if [[ "$pod_count" == "0" ]]; then
      break
    fi
    sleep 2
  done
  echo "[*] Namespace '$NS' is clean."

  ###########################################################
  # DEPLOY PHASE (INCL. HTTP READINESS)
  ###########################################################
  echo "------ DEPLOY PHASE ------"
  deploy_start=$(date +%s.%N)
  deploy_start_human=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[*] Deploy start time: $deploy_start_human"

  kubectl apply -f "$MANIFEST" -n "$NS" >/dev/null

  echo "[*] Waiting for all deployments in '$NS' to be Available..."
  kubectl wait --for=condition=available deployment --all -n "$NS" --timeout=900s >/dev/null

  echo "[*] All deployments Available. Checking frontend HTTP readiness..."

  # Start port-forward for internal frontend service (ClusterIP)
  kubectl port-forward svc/"$FRONTEND_SVC_NAME" -n "$NS" "$FRONTEND_LOCAL_PORT":80 \
    >/tmp/online-boutique-kpi-pf.log 2>&1 &
  PF_PID=$!

  # Wait for port-forward to be ready (short timeout)
  echo "[*] Waiting for port-forward to be ready on ${FRONTEND_LOCAL_PORT}${FRONTEND_PATH}..."
  pf_wait_timeout=30
  pf_wait_elapsed=0
  while true; do
    # If port-forward died, abort
    if ! kill -0 "$PF_PID" >/dev/null 2>&1; then
      echo "[!] Port-forward process exited unexpectedly. Check /tmp/online-boutique-kpi-pf.log"
      exit 1
    fi

    if curl -sS --connect-timeout 1 "http://127.0.0.1:${FRONTEND_LOCAL_PORT}${FRONTEND_PATH}" >/dev/null 2>&1; then
      break
    fi

    sleep 1
    pf_wait_elapsed=$((pf_wait_elapsed + 1))
    if [ "$pf_wait_elapsed" -ge "$pf_wait_timeout" ]; then
      echo "[!] Timeout waiting for port-forward to become ready. Check /tmp/online-boutique-kpi-pf.log"
      exit 1
    fi
  done

  echo "[*] Port-forward is up. Waiting for frontend to return HTTP 200 on ${FRONTEND_PATH}..."

  # Global timeout for frontend becoming HTTP 200 ready
  frontend_timeout=300
  frontend_elapsed=0
  while true; do
    http_code=$(curl -sS -o /dev/null -w "%{http_code}" "http://127.0.0.1:${FRONTEND_LOCAL_PORT}${FRONTEND_PATH}" || echo "000")
    if [[ "$http_code" == "200" ]]; then
      break
    fi

    sleep 2
    frontend_elapsed=$((frontend_elapsed + 2))
    if [ "$frontend_elapsed" -ge "$frontend_timeout" ]; then
      echo "[!] Timeout: frontend did not become HTTP-200-ready within ${frontend_timeout}s."
      echo "    Last HTTP code seen: $http_code"
      echo "    Check pod logs for 'frontend' and other services."
      exit 1
    fi
  done

  deploy_end=$(date +%s.%N)
  deploy_end_human=$(date '+%Y-%m-%d %H:%M:%S')

  deploy_duration=$(time_diff "$deploy_start" "$deploy_end")
  deploy_times+=("$deploy_duration")

  echo "[*] Frontend is serving HTTP 200."
  echo "[*] Deploy end time:   $deploy_end_human"
  echo "[*] Deployment time:   ${deploy_duration} seconds"

  cleanup_pf
  PF_PID=""

  ###########################################################
  # DELETE PHASE
  ###########################################################
  echo "------ DELETE PHASE ------"
  delete_start=$(date +%s.%N)
  delete_start_human=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[*] Delete start time: $delete_start_human"

  kubectl delete -f "$MANIFEST" -n "$NS" >/dev/null

  echo "[*] Waiting for all pods in '$NS' to terminate..."
  while true; do
    pod_count=$(kubectl get pods -n "$NS" --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')
    if [[ "$pod_count" == "0" ]]; then
      break
    fi
    sleep 2
  done

  delete_end=$(date +%s.%N)
  delete_end_human=$(date '+%Y-%m-%d %H:%M:%S')

  delete_duration=$(time_diff "$delete_start" "$delete_end")
  delete_times+=("$delete_duration")

  echo "[*] Delete end time:   $delete_end_human"
  echo "[*] Deletion time:     ${delete_duration} seconds"

  ###########################################################
  # PER-ITERATION LOGGING (APPEND)
  ###########################################################
  echo "${run_ts},${i},${NS},${deploy_duration},${delete_duration}" >> "$CSV_FILE"

  {
    echo "Run: ${run_ts} | Iteration: $i"
    echo "  Namespace       : $NS"
    echo "  Deployment time : ${deploy_duration} s"
    echo "  Deletion time   : ${delete_duration} s"
    echo "-------------------------------------------------------"
  } >> "$TXT_FILE"

  # Sleep between iterations (does not affect KPI timing)
  if [[ $i -lt $ITERATIONS ]]; then
    echo "[*] Sleeping 20 seconds before next iteration..."
    sleep 20
  fi

done

#############################
# SIMPLE SUMMARY (THIS RUN)
#############################
echo ""
echo "================ SUMMARY (THIS RUN) ================="

calc_stats() {
  local label="$1"
  shift
  local arr=("$@")

  local count=${#arr[@]}
  if [[ "$count" -eq 0 ]]; then
    echo "$label: no data"
    return
  fi

  local min="${arr[0]}"
  local max="${arr[0]}"
  local sum="0"

  for v in "${arr[@]}"; do
    if [[ "$USE_BC" -eq 1 ]]; then
      if (( $(echo "$v < $min" | bc -l) )); then
        min="$v"
      fi
      if (( $(echo "$v > $max" | bc -l) )); then
        max="$v"
      fi
      sum=$(echo "$sum + $v" | bc)
    else
      v_int=${v%%.*}
      min_int=${min%%.*}
      max_int=${max%%.*}
      if (( v_int < min_int )); then
        min="$v"
      fi
      if (( v_int > max_int )); then
        max="$v"
      fi
      sum=$(( sum + v_int ))
    fi
  done

  local avg
  if [[ "$USE_BC" -eq 1 ]]; then
    avg=$(echo "scale=3; $sum / $count" | bc)
  else
    avg=$(( sum / count ))
  fi

  printf "%s runs: %d\n" "$label" "$count"
  printf "%s min : %.3f s\n" "$label" "$min"
  printf "%s max : %.3f s\n" "$label" "$max"
  printf "%s avg : %.3f s\n" "$label" "$avg"
}

calc_stats "Deployment" "${deploy_times[@]}"
echo ""
calc_stats "Deletion" "${delete_times[@]}"

echo "======================================================="
echo "Done. CSV: $CSV_FILE | TXT: $TXT_FILE"
