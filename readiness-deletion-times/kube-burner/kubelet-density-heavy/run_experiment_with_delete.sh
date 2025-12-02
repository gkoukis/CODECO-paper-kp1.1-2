#!/bin/bash

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
# CAM-ENABLED VERSION
# This script orchestrates a series of kube-burner "kubelet-density-heavy"
# experiments using:
#   - The original workloads (PostgreSQL + perfapp + Service)
#   - PLUS a CodecoApp (CAM) that models each perfapp+postgres pair.
#
# For each configured experiment, and for each outer run, it:
#   1. Deletes and recreates the namespace "kubelet-density-heavy".
#   2. Exports parameters and renders:
#         kubelet-density-heavy.template-cam-plus.yml
#      into:
#         kubelet-density-heavy.yml
#      via envsubst.
#   3. Runs `kube-burner init -c kubelet-density-heavy.yml`.
#   4. Renames the kube-burner log to a descriptive filename.
#   5. Measures deletion time (deployments, services, pods, CodecoApps)
#      in the "kubelet-density-heavy" namespace with millisecond resolution,
#      logging results to "deletion_times.log".
#
# WARNING: This script repeatedly deletes the "kubelet-density-heavy" namespace.
# Do not use that namespace for anything else.

# Define the number of times to repeat the entire set of experiments
iterations=6

# ---------------------------------------------------------------------------
# Experiments configuration
# ---------------------------------------------------------------------------
# experiments=(
#  "jobIterations=1 qps=1 burst=1 postgres_deploy_replicas=10 app_deploy_replicas=10 postgres_service_replicas=10"
#  "jobIterations=1 qps=10 burst=10 postgres_deploy_replicas=10 app_deploy_replicas=10 postgres_service_replicas=10"
# # "jobIterations=1 qps=25 burst=25 postgres_deploy_replicas=10 app_deploy_replicas=10 postgres_service_replicas=10"
#  "jobIterations=1 qps=50 burst=50 postgres_deploy_replicas=10 app_deploy_replicas=10 postgres_service_replicas=10"
# # "jobIterations=1 qps=75 burst=75 postgres_deploy_replicas=10 app_deploy_replicas=10 postgres_service_replicas=10"
#  "jobIterations=1 qps=100 burst=100 postgres_deploy_replicas=10 app_deploy_replicas=10 postgres_service_replicas=10"
#  "jobIterations=1 qps=1 burst=1 postgres_deploy_replicas=20 app_deploy_replicas=20 postgres_service_replicas=20"
#  "jobIterations=1 qps=10 burst=10 postgres_deploy_replicas=20 app_deploy_replicas=20 postgres_service_replicas=20"
#  "jobIterations=1 qps=25 burst=25 postgres_deploy_replicas=20 app_deploy_replicas=20 postgres_service_replicas=20"
# # "jobIterations=1 qps=50 burst=50 postgres_deploy_replicas=20 app_deploy_replicas=20 postgres_service_replicas=20"
#  "jobIterations=1 qps=75 burst=75 postgres_deploy_replicas=20 app_deploy_replicas=20 postgres_service_replicas=20"
# # "jobIterations=1 qps=100 burst=100 postgres_deploy_replicas=20 app_deploy_replicas=20 postgres_service_replicas=20"
#  "jobIterations=1 qps=1 burst=1 postgres_deploy_replicas=40 app_deploy_replicas=40 postgres_service_replicas=40"
#  "jobIterations=1 qps=10 burst=10 postgres_deploy_replicas=40 app_deploy_replicas=40 postgres_service_replicas=40"
# # "jobIterations=1 qps=25 burst=25 postgres_deploy_replicas=40 app_deploy_replicas=40 postgres_service_replicas=40"
#  "jobIterations=1 qps=50 burst=50 postgres_deploy_replicas=40 app_deploy_replicas=40 postgres_service_replicas=40"
# # "jobIterations=1 qps=75 burst=75 postgres_deploy_replicas=40 app_deploy_replicas=40 postgres_service_replicas=40"
#  "jobIterations=1 qps=100 burst=100 postgres_deploy_replicas=40 app_deploy_replicas=40 postgres_service_replicas=40"
# # "jobIterations=1 qps=1 burst=1 postgres_deploy_replicas=50 app_deploy_replicas=50 postgres_service_replicas=50"
# # "jobIterations=1 qps=10 burst=10 postgres_deploy_replicas=50 app_deploy_replicas=50 postgres_service_replicas=50"
# # "jobIterations=1 qps=25 burst=25 postgres_deploy_replicas=50 app_deploy_replicas=50 postgres_service_replicas=50"
# # "jobIterations=1 qps=50 burst=50 postgres_deploy_replicas=50 app_deploy_replicas=50 postgres_service_replicas=50"
# # "jobIterations=1 qps=75 burst=75 postgres_deploy_replicas=50 app_deploy_replicas=50 postgres_service_replicas=50"
# # "jobIterations=1 qps=100 burst=100 postgres_deploy_replicas=50 app_deploy_replicas=50 postgres_service_replicas=50"
# # # Add more experiment combinations as needed
# )

experiments=(
"jobIterations=1 qps=1 burst=1 postgres_deploy_replicas=1 app_deploy_replicas=1 postgres_service_replicas=1"
"jobIterations=1 qps=10 burst=10 postgres_deploy_replicas=1 app_deploy_replicas=1 postgres_service_replicas=1"
"jobIterations=1 qps=25 burst=25 postgres_deploy_replicas=1 app_deploy_replicas=1 postgres_service_replicas=1"
"jobIterations=1 qps=50 burst=50 postgres_deploy_replicas=1 app_deploy_replicas=1 postgres_service_replicas=1"
"jobIterations=1 qps=75 burst=75 postgres_deploy_replicas=1 app_deploy_replicas=1 postgres_service_replicas=1"
"jobIterations=1 qps=100 burst=100 postgres_deploy_replicas=1 app_deploy_replicas=1 postgres_service_replicas=1"
# "jobIterations=10 qps=1 burst=1 postgres_deploy_replicas=1 app_deploy_replicas=1 postgres_service_replicas=1"
#  "jobIterations=10 qps=10 burst=10 postgres_deploy_replicas=1 app_deploy_replicas=1 postgres_service_replicas=1"
#  "jobIterations=10 qps=25 burst=25 postgres_deploy_replicas=1 app_deploy_replicas=1 postgres_service_replicas=1"
#  "jobIterations=10 qps=50 burst=50 postgres_deploy_replicas=1 app_deploy_replicas=1 postgres_service_replicas=1"
#  "jobIterations=10 qps=75 burst=75 postgres_deploy_replicas=1 app_deploy_replicas=1 postgres_service_replicas=1"
#  "jobIterations=10 qps=100 burst=100 postgres_deploy_replicas=1 app_deploy_replicas=1 postgres_service_replicas=1"
  # Add more experiment combinations as needed
)

# ---------------------------------------------------------------------------
# Function: HIGH-ACCURACY deletion measurement (ms resolution, 3 decimals)
# ---------------------------------------------------------------------------
measure_delete_time() {
  local ns="kubelet-density-heavy"
  local experiment_desc="$1"
  local run_id="$2"

  echo "------"
  echo "Starting deletion of resources in namespace '${ns}' for run=${run_id}"
  echo "Experiment: ${experiment_desc}"

  # Start timestamp in milliseconds
  local start_ts_ms
  start_ts_ms=$(date +%s%3N)

  # Delete deployments and services created by kube-burner
  kubectl delete deployment,svc -n "${ns}" --all --ignore-not-found=true

  # Poll until all pods, deployments, and services are gone
  while true; do
    local remaining
    remaining=$(kubectl get pods,deploy,svc -n "${ns}" --no-headers 2>/dev/null | wc -l)

    if [ "${remaining}" -eq 0 ]; then
      break
    fi

    echo "Waiting for resources to be deleted... remaining objects: ${remaining}"
    sleep 0.2  # 200ms polling
  done

  # End timestamp in milliseconds
  local end_ts_ms
  end_ts_ms=$(date +%s%3N)

  # Duration in milliseconds
  local duration_ms=$((end_ts_ms - start_ts_ms))

  # Convert ms → seconds with 3 decimals (X.XXX)
  local sec=$((duration_ms / 1000))
  local ms_rem=$((duration_ms % 1000))
  local duration
  duration=$(printf "%d.%03d" "${sec}" "${ms_rem}")

  # Log accurate duration
  echo "DeleteDurationSeconds run=${run_id} ${experiment_desc} duration=${duration}s"
  echo "DeleteDurationSeconds run=${run_id} ${experiment_desc} duration=${duration}s" >> deletion_times.log

  echo "Finished deletion timing for run=${run_id} (${duration}s)"
  echo "------"
}

# ---------------------------------------------------------------------------
# Determine the starting log counter
# ---------------------------------------------------------------------------
if ls kubelet-density-heavy_*.log 1> /dev/null 2>&1; then
  counter=$(ls kubelet-density-heavy_*.log | grep -o '[0-9]*\.log' | grep -o '[0-9]*' | sort -n | tail -1)
  counter=$((counter + 1))
else
  counter=1
fi

# ---------------------------------------------------------------------------
# Main experiment loop
# ---------------------------------------------------------------------------
for (( run=1; run<=iterations; run++ )); do
  echo "============================================================"
  echo "Starting run ${run} of ${iterations}"
  echo "============================================================"

  for experiment in "${experiments[@]}"; do
    echo "------------------------------------------------------------"
    echo "Running experiment: ${experiment}"
    echo "------------------------------------------------------------"

    # Namespace cleanup before each experiment
    if kubectl get namespace kubelet-density-heavy &> /dev/null; then
      echo "Namespace exists. Deleting..."
      kubectl delete namespace kubelet-density-heavy

      while kubectl get namespace kubelet-density-heavy &> /dev/null; do
        echo "Waiting for namespace cleanup..."
        sleep 1
      done
    fi

    kubectl create namespace kubelet-density-heavy

    # Parse experiment variables
    eval "${experiment}"

    export JOB_ITERATIONS="${jobIterations}"
    export QPS="${qps}"
    export BURST="${burst}"
    export POSTGRES_DEPLOY_REPLICAS="${postgres_deploy_replicas}"
    export APP_DEPLOY_REPLICAS="${app_deploy_replicas}"
    export POSTGRES_SERVICE_REPLICAS="${postgres_service_replicas}"

    # Generate kube-burner manifest
    envsubst < kubelet-density-heavy.template.yml > kubelet-density-heavy.yml

    # Run kube-burner
    kube-burner init -c kubelet-density-heavy.yml

    # Rename kube-burner log
    log_file=$(ls -t kube-burner-*.log | head -n 1)
    new_log_file="kubelet-density-heavy_jobIterations${jobIterations}_qps${qps}_burst${burst}_postgres-deploy${postgres_deploy_replicas}_app${app_deploy_replicas}_postgres-service${postgres_service_replicas}_${counter}.log"
    mv "${log_file}" "${new_log_file}"

    # Measure precise deletion timing
    measure_delete_time "${experiment}" "${run}"

    counter=$((counter + 1))

    echo "Sleeping 45 seconds before next experiment..."
    sleep 45
  done
done

echo "All experiments completed."