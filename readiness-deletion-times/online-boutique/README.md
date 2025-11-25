# Online Boutique Deployment & Deletion KPI Experiment

This experiment script measures how long it takes to **deploy** and **tear down** the Online Boutique microservices application on a Kubernetes cluster.

For each iteration, the script:

1. **Cleans the namespace**  
   - Deletes any existing resources defined in the Online Boutique manifest.  
   - Waits until all pods in the target namespace are terminated.

2. **Deployment phase**  
   - Applies the provided Online Boutique manifest (by default: `online-boutique-nogen.yaml`, i.e., without the load generator).  
   - Waits until **all deployments are Available** in the target namespace.  
   - Starts a **port-forward** to the internal `frontend` service and repeatedly checks the `/_healthz` endpoint on `http://127.0.0.1:8080/_healthz`.  
   - The deployment time is measured from the `kubectl apply` start until the frontend responds with HTTP **200** on `/_healthz`.

3. **Deletion phase**  
   - Deletes all resources from the manifest.  
   - Waits until **no pods remain** in the target namespace.  
   - The deletion time is measured from the `kubectl delete` start until the namespace is completely clean.

For each iteration the script records:

- **Deployment time** (seconds)
- **Deletion time** (seconds)

Results are appended to:

- `online-boutique_kpi_results.csv` – CSV with one row per iteration.  
- `online-boutique_kpi_results.txt` – txt log with per-iteration details.

---

# Note

- **This script does NOT use the CAM. The results should be used as a baseline.** Execution with CAM **TBA**.
- **The results/ folder already contains experiment results generated on both the CODECO shared cloud environment and ATH’s server that can be used for comparison, validation, or baseline reference.**
- In case you see big **variations in the results**, increase the number of iterations.

---

# Instructions – Online Boutique KPI Script

## Prerequisites

- A running Kubernetes cluster.
- `kubectl` configured to point to the target cluster.
- `curl` installed (used to query the frontend health endpoint).
- An Online Boutique manifest file:
  - Default used by the script is the original `online-boutique.yaml` if you want the full stack including the load generator. The existing yaml was downloaded with: *curl -LO https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/main/release/kubernetes-manifests.yaml*
  - You can also use the: `./online-boutique-nogen.yaml` - no built in load generator.

## Usage


### Main script 

General usage: ./online_boutique_kpimeasure_online_boutique_kpi.sh [iterations] [namespace] [manifest]

**For this experiments I'd recommend to run:**
```bash
chmod +x ./measure_online_boutique_kpi.sh
./measure_online_boutique_kpi.sh 6
```

### Analysis Script (CSV → Stats)

Once you have collected multiple runs of Online Boutique deployment/deletion KPIs in the CSV file, you can use this script to compute **summary statistics**.

The script reads a CSV file with columns:  run_timestamp,iteration,namespace,deployment_time_s,deletion_time_s

```bash
chmod +x ./analyze_online_boutique_kpi.sh
./analyze_online_boutique_kpi.sh
```