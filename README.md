# CODECO-paper-kp1.1-2 (led by ATH)

# General Overview

This repository contains a collection of **Kubernetes performance, scalability, and responsiveness experiments** developed for the **CODECO** project. The repository includes **experiment families**, each with its own dedicated scripts and results/. 

I suggest to focus on the following 3 experiments:

## custom_startup_times
- for default K8s/no-CAM --> [Link] https://github.com/gkoukis/CODECO-paper-kp1.1-2/blob/main/readiness-deletion-times/custom-startup-times/pod_startup_times_with_pod_delete_script.sh --> ./pod_startup_times_with_pod_delete_script.sh ucX 6 60 '1 10 50 100 150'
- for CAM --> I believe I have updated the code according to your input/observations. Now the new script for CAM deletes the codecoapp after each iteration. [Link]: https://github.com/gkoukis/CODECO-paper-kp1.1-2/blob/main/readiness-deletion-times/custom-startup-times/pod_startup_times_with_pod_delete_script_CAM.sh --> ./pod_startup_times_with_pod_delete_script_CAM.sh ucX 6 60 '1 10 50 100 150'

## CODECO dummy (frontend-backend) app with varying frontend replicas (1–50).
- for default K8s/no-CAM --> [Link] https://github.com/gkoukis/CODECO-paper-kp1.1-2/blob/main/readiness-deletion-times/codeco-dummy-app/measure_codecoapp_nocam_checkavail.sh —> ./measure_codecoapp_nocam_checkavail.sh 6 "1 10 25 50" skupper-demo
- for CAM --> [Link] https://github.com/gkoukis/CODECO-paper-kp1.1-2/blob/main/readiness-deletion-times/codeco-dummy-app/measure_codecoapp_cam_checkavail.sh —> ./measure_codecoapp_cam_checkavail.sh 6 "1 10 25 50" he-codeco-acm

## Bookinfo
- for default K8s/no-CAM --> [Link] https://github.com/gkoukis/CODECO-paper-kp1.1-2/tree/main/readiness-deletion-times/bookinfo/results/CODECO_no_CAM —> You need to have measure_bookinfo_nocam_checkavail.sh and bookinfo.yaml and run --> ./measure_bookinfo_noncam_checkavail.sh bookinfo.yaml 6 bookinfo 60
- for CAM --> [Link] https://github.com/gkoukis/CODECO-paper-kp1.1-2/tree/main/readiness-deletion-times/bookinfo/results/CODECO_CAM —> You need to have measure_bookinfo_cam.sh and codecoapp-bookinfo-cam.yaml and run --> ./measure_bookinfo_cam.sh codecoapp-bookinfo-cam.yaml 6 he-codeco-acm





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


