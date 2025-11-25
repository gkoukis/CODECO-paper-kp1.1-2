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

### This script runs a series of K8s pod startup experiments, measures various latencies,
### compiles detailed results, and ALSO measures per-pod deletion latency and batch delete time.
### Additionally, it snapshots the node distribution per iteration without modifying manifests.

# -----------------------------
# Usage
# -----------------------------
usage() {
  echo "Usage: $0 <plugin> <num_iterations> <sleep_between_iterations> <num_pods_values>"
  echo "Example: $0 uc1 5 10 '1 10 20 30'"
  echo "If no arguments are provided, default values will be used."
}

# -----------------------------
# Defaults
# -----------------------------
default_plugin="ath"    # add here your UC as uc1, uc2 , etc
default_num_iterations=2
default_sleep_between_iterations=60
default_num_pods_values="1 10 20"

# -----------------------------
# Args
# -----------------------------
plugin=${1:-$default_plugin}
num_iterations=${2:-$default_num_iterations}
sleep_between_iterations=${3:-$default_sleep_between_iterations}
num_pods_values=${4:-$default_num_pods_values}

# -----------------------------
# Files & namespace
# -----------------------------
timestamp_file="pod_init_timestamps.txt"
namespace="pod-init-times"

# Create namespace if missing
kubectl get ns "$namespace" > /dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "Creating namespace: $namespace"
  kubectl create namespace "$namespace"
else
  echo "Namespace $namespace already exists."
fi

# -----------------------------
# Results directory (per day)
# -----------------------------
timestamp_now=$(date '+%Y%m%d_%H%M%S')
results_dir="ExpResult_${timestamp_now}"
mkdir -p "$results_dir"

# -----------------------------
# Script start log
# -----------------------------
script_start_time=$(date '+%Y-%m-%d %H:%M:%S')
echo "-------------------------------------------" >> "$timestamp_file"
echo "Script execution started at: $script_start_time" | tee -a "$timestamp_file"
echo "Plugin: $plugin, Number of Iterations: $num_iterations, Sleep Between Iterations: $sleep_between_iterations seconds, Pod Counts: $num_pods_values" | tee -a "$timestamp_file"

# ==============================================================
# Function: run_pod_startup_experiment
# - Measures per-pod creation latency, batch readiness time
# - Measures per-pod delete latency, batch delete time (parallel-style)
# - Snapshots node distribution per iteration (no labels needed)
# ==============================================================
run_pod_startup_experiment() {
  num_pods=$1
  plugin=$2

  individual_filename="${results_dir}/individual_pod_creation_times_${plugin}_pods${num_pods}.txt"
  total_filename="${results_dir}/total_pod_creation_times_${plugin}_pods${num_pods}.txt"

  del_individual_filename="${results_dir}/individual_pod_delete_times_${plugin}_pods${num_pods}.txt"
  del_total_filename="${results_dir}/total_pod_delete_times_${plugin}_pods${num_pods}.txt"

  node_dist_file="${results_dir}/node_dist_${plugin}_pods${num_pods}.txt"

  echo "Pod Creation Time Measurement for num_pods=$num_pods"
  echo "Iteration, Total Latency (milliseconds), Average Latency per pod (milliseconds), Batch Readiness Time (milliseconds)" > "$total_filename"
  echo "Pod Name, Creation Timestamp, Ready Timestamp, Latency (milliseconds)" > "$individual_filename"

  # Headers for deletion files
  echo "Pod Name, Delete Start Timestamp, Deleted Confirmed Timestamp, Delete Latency (milliseconds)" > "$del_individual_filename"
  echo "Iteration, Total Delete Latency (milliseconds), Average Delete Latency per pod (milliseconds), Batch Delete Time (milliseconds)" > "$del_total_filename"

  total_batch_readiness=0
  total_latency_accumulator=0

  # Accumulators for deletion stats across iterations
  total_delete_latency_acc=0
  total_batch_delete_acc=0

  for (( r=1; r<=num_iterations; r++ )); do
    # ---- Launch pods & measure readiness ----
    iteration_start_time=$(date '+%Y-%m-%d %H:%M:%S')
    echo "Iteration $r started at: $iteration_start_time" | tee -a "$timestamp_file"

    start_times=()
    end_times=()
    total_latency=0

    batch_start_time=$(date +%s%3N)

    # Create pods concurrently
    for (( i=1; i<=$num_pods; i++ )); do
      pod_name="pause-pod-$r-$i"
      cat <<EOF | kubectl apply -f - -n "$namespace" &
apiVersion: v1
kind: Pod
metadata:
  name: $pod_name
spec:
  containers:
  - name: pause
    image: k8s.gcr.io/pause:3.1
#  nodeSelector:
#    kubernetes.io/hostname: athw3         ### Enable it with the name of one worker node you want the pods to deploy or keep it as it is if you want pods to be deployed in all nodes via scheduler
EOF
      start_times[$i]=$(date +%s%3N)
    done
    wait

    latest_ready_time=0
    for (( i=1; i<=$num_pods; i++ )); do
      pod_name="pause-pod-$r-$i"
      kubectl wait --for=condition=ready pod "$pod_name" -n "$namespace" --timeout=300s > /dev/null 2>&1
      end_times[$i]=$(date +%s%3N)
      if [[ ${end_times[$i]} -gt $latest_ready_time ]]; then
        latest_ready_time=${end_times[$i]}
      fi
    done

    batch_readiness_time=$((latest_ready_time - batch_start_time))
    total_batch_readiness=$((total_batch_readiness + batch_readiness_time))

    for (( i=1; i<=$num_pods; i++ )); do
      pod_name="pause-pod-$r-$i"
      latency=$(( end_times[$i] - start_times[$i] ))
      echo "$pod_name, ${start_times[$i]}, ${end_times[$i]}, $latency" >> "$individual_filename"
      total_latency=$(( total_latency + latency ))
    done

    average_latency=$(( total_latency / num_pods ))
    echo "$r, $total_latency, $average_latency, $batch_readiness_time" >> "$total_filename"
    total_latency_accumulator=$(( total_latency_accumulator + total_latency ))

    # ---- Snapshot node distribution for this iteration ----
    {
      echo "------ iteration=$r pods=$num_pods (node distribution) ------"
      kubectl get pods -n "$namespace" -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName --no-headers \
        | grep -E "^pause-pod-$r-" | awk '{print $2}' | sort | uniq -c \
        | awk -v it=$r -v np=$num_pods '{printf "iter=%d pods=%d  %4d %s\n", it, np, $1, $2}'
    } >> "$node_dist_file"

    # ---- Parallel-style delete: fire all deletes, then wait for all ----
    delete_batch_start=$(date +%s%3N)
    iteration_delete_total=0
    del_start_times=()

    # 1) Send all delete requests (non-blocking) and record start times
    for (( i=1; i<=$num_pods; i++ )); do
      pod_name="pause-pod-$r-$i"
      del_start_times[$i]=$(date +%s%3N)
      kubectl delete pod "$pod_name" -n "$namespace" --wait=false > /dev/null 2>&1 &
    done
    wait  # ensure all delete requests have been submitted to the API server

    # 2) Wait for each pod to be fully deleted and measure latency
    for (( i=1; i<=$num_pods; i++ )); do
      pod_name="pause-pod-$r-$i"
      kubectl wait --for=delete pod/"$pod_name" -n "$namespace" --timeout=300s > /dev/null 2>&1
      del_end=$(date +%s%3N)
      del_latency=$(( del_end - del_start_times[$i] ))
      iteration_delete_total=$(( iteration_delete_total + del_latency ))
      echo "$pod_name, ${del_start_times[$i]}, ${del_end}, $del_latency" >> "$del_individual_filename"
    done

    delete_batch_end=$(date +%s%3N)
    batch_delete_time=$(( delete_batch_end - delete_batch_start ))
    avg_delete_latency=$(( iteration_delete_total / num_pods ))
    echo "$r, $iteration_delete_total, $avg_delete_latency, $batch_delete_time" >> "$del_total_filename"

    # Accumulate across iterations
    total_delete_latency_acc=$(( total_delete_latency_acc + iteration_delete_total ))
    total_batch_delete_acc=$(( total_batch_delete_acc + batch_delete_time ))

    # ---- logging & sleep ----
    iteration_end_time=$(date '+%Y-%m-%d %H:%M:%S')
    echo "Iteration $r completed at: $iteration_end_time." | tee -a "$timestamp_file"
    echo "Create: total=$total_latency ms, avg/pod=$average_latency ms, batch_ready=$batch_readiness_time ms." | tee -a "$timestamp_file"
    echo "Delete: total=$iteration_delete_total ms, avg/pod=$avg_delete_latency ms, batch_delete=$batch_delete_time ms." | tee -a "$timestamp_file"

    echo "Sleeping for $sleep_between_iterations seconds..."
    sleep "$sleep_between_iterations"
  done

  # ---- Creation rollups ----
  average_batch_readiness=$(( total_batch_readiness / num_iterations ))
  echo "Average Batch Readiness Time for all iterations: $average_batch_readiness milliseconds." >> "$total_filename"

  final_average_latency=$(( total_latency_accumulator / (num_iterations * num_pods) ))
  echo "Final Average Latency per pod for all iterations: $final_average_latency milliseconds." >> "$total_filename"

  # ---- Deletion rollups ----
  avg_batch_delete_over_iters=$(( total_batch_delete_acc / num_iterations ))
  final_avg_delete_latency=$(( total_delete_latency_acc / (num_iterations * num_pods) ))
  echo "Average Batch Delete Time for all iterations: $avg_batch_delete_over_iters milliseconds." >> "$del_total_filename"
  echo "Final Average Delete Latency per pod for all iterations: $final_avg_delete_latency milliseconds." >> "$del_total_filename"

  echo "Measurement complete for num_pods=$num_pods."
  echo "Create metrics: $individual_filename, $total_filename"
  echo "Delete metrics: $del_individual_filename, $del_total_filename"
  echo "Node distribution per iteration: $node_dist_file"
}

# --------------------------------------------------------------
# Compile detailed creation results
# --------------------------------------------------------------
compile_detailed_results() {
  output_file="${results_dir}/compiled_pod_creation_times_detailed_summary.txt"

  echo "Plugin, Num Pods, Iteration, Total Latency (ms), Average Latency per Pod (ms), Batch Readiness Time (ms), Average Batch Readiness Time (ms), Final Average Latency per Pod for all iterations (ms)" > "$output_file"

  for total_file in "${results_dir}"/total_pod_creation_times_*.txt; do
    [ -f "$total_file" ] || continue
    plugin=$(echo "$total_file" | sed -n 's/.*_\(.*\)_pods.*/\1/p')
    num_pods=$(echo "$total_file" | sed -n 's/.*_pods\([0-9]\+\).*/\1/p')

    avg_batch_readiness=$(grep "Average Batch Readiness Time for all iterations" "$total_file" | awk -F': ' '{print $2}' | awk '{print $1}')
    final_avg_latency=$(grep "Final Average Latency per pod for all iterations" "$total_file" | awk -F': ' '{print $2}' | awk '{print $1}')

    while read -r line; do
      if [[ "$line" == "Iteration, Total Latency (milliseconds),"* ]] || [[ "$line" == "Average Batch Readiness Time for all iterations:"* ]] || [[ "$line" == "Final Average Latency per pod for all iterations:"* ]]; then
        continue
      fi
      echo "$plugin, $num_pods, $line, $avg_batch_readiness, $final_avg_latency" >> "$output_file"
    done < "$total_file"
  done

  echo "All creation data compiled into $output_file"
}

# --------------------------------------------------------------
# Compile deletion results
# --------------------------------------------------------------
compile_delete_results() {
  output_file="${results_dir}/compiled_pod_delete_times_detailed_summary.txt"

  echo "Plugin, Num Pods, Iteration, Total Delete Latency (ms), Average Delete Latency per Pod (ms), Batch Delete Time (ms), Average Batch Delete Time (ms), Final Average Delete Latency per Pod for all iterations (ms)" > "$output_file"

  for total_file in "${results_dir}"/total_pod_delete_times_*.txt; do
    [ -f "$total_file" ] || continue
    plugin=$(echo "$total_file" | sed -n 's/.*_\(.*\)_pods.*/\1/p')
    num_pods=$(echo "$total_file" | sed -n 's/.*_pods\([0-9]\+\).*/\1/p')

    avg_batch_delete=$(grep "Average Batch Delete Time for all iterations" "$total_file" | awk -F': ' '{print $2}' | awk '{print $1}')
    final_avg_del_latency=$(grep "Final Average Delete Latency per pod for all iterations" "$total_file" | awk -F': ' '{print $2}' | awk '{print $1}')

    while read -r line; do
      if [[ "$line" == "Iteration, Total Delete Latency (milliseconds),"* ]] || [[ "$line" == "Average Batch Delete Time for all iterations:"* ]] || [[ "$line" == "Final Average Delete Latency per pod for all iterations:"* ]]; then
        continue
      fi
      echo "$plugin, $num_pods, $line, $avg_batch_delete, $final_avg_del_latency" >> "$output_file"
    done < "$total_file"
  done

  echo "All deletion data compiled into $output_file"
}

# --------------------------------------------------------------
# Compile node distributions
# --------------------------------------------------------------
compile_node_distributions() {
  out="${results_dir}/compiled_node_distribution_${plugin}.txt"
  echo "Compiling node distributions..." | tee -a "$timestamp_file"
  : > "$out"
  for f in "${results_dir}"/node_dist_${plugin}_pods*.txt; do
    [ -f "$f" ] || continue
    echo "------ $(basename "$f") ------" >> "$out"
    cat "$f" >> "$out"
  done
  echo "Node distributions written to $out"
}

# -----------------------------
# Run experiments
# -----------------------------
echo "Running experiments with the following parameters:" | tee -a "$timestamp_file"
echo "Plugin: $plugin" | tee -a "$timestamp_file"
echo "Number of Iterations: $num_iterations" | tee -a "$timestamp_file"
echo "Sleep Between Iterations: $sleep_between_iterations seconds" | tee -a "$timestamp_file"
echo "Pod Counts: $num_pods_values" | tee -a "$timestamp_file"
echo "-------------------------------------------" | tee -a "$timestamp_file"

for num_pods in $num_pods_values; do
  run_pod_startup_experiment "$num_pods" "$plugin"
done

# -----------------------------
# Compile results
# -----------------------------
echo "Compiling results from all experiments..." | tee -a "$timestamp_file"
compile_detailed_results
compile_delete_results
compile_node_distributions

# -----------------------------
# Script end log
# -----------------------------
script_end_time=$(date '+%Y-%m-%d %H:%M:%S')
echo "All experiments completed at: $script_end_time" | tee -a "$timestamp_file"
echo "Results compiled into:"
echo " - ${results_dir}/compiled_pod_creation_times_detailed_summary.txt"
echo " - ${results_dir}/compiled_pod_delete_times_detailed_summary.txt"
echo " - ${results_dir}/compiled_node_distribution_${plugin}.txt"
