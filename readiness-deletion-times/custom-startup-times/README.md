# Description

This script automates a series of experiments to benchmark pod startup and deletion behavior for a batch of pods. It uses a lightweight `pause` container image: `k8s.gcr.io/pause:3.1`.

For each selected **plugin/use case label** (e.g., `uc1`, `uc2`, `ath`) and each configured **pod count**, the script:

- Creates `N` lightweight `pause` pods in the `pod-init-times` namespace.
- Measures:
  - **Per-pod creation latency** (from API request to Ready condition).
  - **Batch readiness time** (time until all pods in the batch become Ready).
- Deletes the same pods in a **parallel-style** manner and measures:
  - **Per-pod deletion latency** (from delete request to complete removal).
  - **Batch delete time** (time until all pods are fully deleted).
- Captures a **node distribution snapshot** per iteration, i.e., how many pods were scheduled on each node.

All raw and aggregated results are stored in a timestamped directory:

```text
ExpResult_<YYYYMMDD>_<HHMMSS>/
  ├─ individual_pod_creation_times_<plugin>_pods<N>.txt
  ├─ total_pod_creation_times_<plugin>_pods<N>.txt
  ├─ individual_pod_delete_times_<plugin>_pods<N>.txt
  ├─ total_pod_delete_times_<plugin>_pods<N>.txt
  ├─ node_dist_<plugin>_pods<N>.txt
  ├─ compiled_pod_creation_times_detailed_summary.txt
  ├─ compiled_pod_delete_times_detailed_summary.txt
  └─ compiled_node_distribution_<plugin>.txt
```


# Note

- **This script does NOT use the CAM. The results should be used as a baseline.** Execution with CAM **TBA**.
- **The results/ folder already contains experiment results generated on both the CODECO shared cloud environment and ATH’s server that can be used for comparison, validation, or baseline reference.**
- Please make sure to check the number of pods (less than 100 per node).
- In case of issues with the pods (e.g., cancelling the script) you can delete them with the `delete_pods_final.sh` script.
- In case you see big **variations in the results**, increase the number of iterations.


---

# Instructions to use it

## Prerequisites

- A running Kubernetes cluster.
- `kubectl`.
- Permission to create namespaces and pods.

## Output

- All pods are created in the namespace: `pod-init-times`.
  - If it does not exist, the script will create it.
- A results directory is created per execution:
  - `ExpResult_<YYYYMMDD>_<HHMMSS>/`
- A global timestamp/log file is appended:
  - `pod_init_timestamps.txt`

## Usage

General usage: ./pod_startup_experiments.sh <plugin> <num_iterations> <sleep_between_iterations> "<num_pods_values>"

1. Change the `default_plugin` value in the script (e.g., `ath`, `uc1`, `uc2`) to reflect your use case or declare it while running the script.
2. Add the `num_iterations` = number of iterations for each batch pod value (for statistical accuracy).
3. Add the `sleep_between_iterations` = time to sleep between iterations
4. Add the `num_pods_values` = batch of pods that will be deployed to measure startup and deletion times



**For this experiments I'd recommend to run:**
```bash
chmod +x ./pod_startup_times_script.sh
./pod_startup_times_script.sh uc1 6 60 '1 10 50 100 150'
```

