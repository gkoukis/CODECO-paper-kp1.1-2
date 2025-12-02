# CODECO-paper-kp1.1-2 (led by ATH)

# General Overview

This repository contains a collection of **Kubernetes performance, scalability, and responsiveness experiments** developed for the **CODECO** project. The repository includes **three main experiment families**, each with its own README, dedicated scripts and results/.


---

# ⚠️ Important Notes

- The custom-startup-times USE **CAM**.
- The other experiments DON'T use **CAM**.

- For control-plane heavy experiments (kube-burner), test the cluster progressively.
- Keep backup of the generated files

---

# Contents

## 1️⃣ Pod Startup & Deletion Latency Experiment
Measures pod creation latency, batch readiness time, per-pod deletion latency, batch deletion time, and node scheduling distribution.

📄 Detailed documentation:  
`custom-startup-times/README.md`

---

## 2️⃣ Online Boutique – Application-Level KPI Measurement
Deploys the full *Online Boutique* microservice application and measures:
- Full application deployment time (until frontend returns HTTP 200)  
- Full namespace deletion time  
- Iteration statistics (CSV + analyzer script included)

📄 Detailed documentation:  
`online-boutique/README.md`

---

## 3️⃣ Kube-Burner – Kubelet-Density-Heavy (Perfapp + PostgreSQL + Service Workload)
Runs kube-burner using a service+database micro-workload (Postgres + perfapp). Experiments consider:

- API-server QPS/Burst values  
- Replica counts  
- jobIterations  

Also includes:
- Millisecond-precision namespace deletion measurement  
- Log parser for aggregating p50/p99/max/avg latency values into CSV

📄 Detailed documentation:  
`kube-burner/README.md`

---

# How to Run Experiments

Each experiment folder contains:

- Its **own README**
- A **main execution script**
- Specific **usage instructions**
- Warnings and prerequisites

Please refer to:

- `pod_startup_experiments/README.md`  
- `online_boutique_kpi/README.md`  
- `kubelet_density_heavy/README.md`  

These READMEs include all required instructions, examples, and recommended parameter sets.

---

# Results

The `results/` directory includes:

- Baseline pod startup/deletion results  
- Online Boutique KPI results  
- Kube-burner heavy workload logs & summaries  

These datasets were generated in:

- **CODECO cloud**
- **ATH server**

---


