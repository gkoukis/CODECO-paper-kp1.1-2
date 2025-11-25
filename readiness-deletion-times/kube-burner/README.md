# Kube-Burner: Kubelet-Density-Heavy Experiment (Service + Database Micro-Workload)

This experiment is based on our forked configuration of **kube-burner** (https://github.com/gkoukis/kube-burner/tree/main) and runs the `kubelet-density-heavy` workload (https://github.com/gkoukis/kube-burner/tree/main/examples/workloads/kubelet-density-heavy).

This scenario deploys a **coupled micro-workload**:

- **PostgreSQL backend** (database)
- **perfapp frontend** (client application) that:
  - connects to Postgres through a Kubernetes **Service**
  - queries against the database as part of the test

The experiment repeatedly **deploys and tears down** this service–database stack in order to:

- Stress the **Kubernetes control plane** (API server, controller-manager, scheduler)
- Generate realistic API traffic (Deployments, Pods, Services, status checks)
- Collect **pod-level latency metrics** to evaluate pod creation, readiness and deletion latency,


## QPS and Burst configuration

The API traffic pattern is controlled via kube-burner’s **client-side rate limiting**, which is built on top of the Kubernetes `client-go` rate limiter. There are two key parameters:

- **QPS (Queries Per Second)**  
  The sustained rate of API calls per second that kube-burner will send.  
  It applies to:
  - `POST` requests (Deployments, Pods, Services)
  - `GET` requests used for status checks, etc.

- **Burst (maximum burst capacity)**  
  The maximum number of API calls that can be sent at once in a short spike.

---

# Note

- **This script does NOT use the CAM. The results should be used as a baseline.** Execution with CAM **TBA**.
- **The results/ folder already contains experiment results generated on both the CODECO shared cloud environment and ATH’s server that can be used for comparison, validation, or baseline reference.**
- In the multiple replica scenario please make sure to check the number of pods created (less than 100 per node). **For each replica, 2 pods are created and one service:**
    - Postgres Deployment → creates postgres_deploy_replicas pods
    - Perfapp Deployment → creates app_deploy_replicas pods
    - Service replica (NOT pods) → creates postgres_service_replicas 

---
# Usage

1) curl -LO https://github.com/kube-burner/kube-burner/releases/download/v1.17.7/kube-burner-V1.17.7-linux-x86_64.tar.gz # Install kube-burner
2) tar -xzf kube-burner-V1.17.7-linux-x86_64.tar.gz  # Extract and move
3) sudo mv kube-burner /usr/local/bin/
4) chmod +x /usr/local/bin/kube-burner
5) kube-burner # test this command if kube-burner is installed 
5) git clone https://github.com/gkoukis/kube-burner.git
6) kubectl label node <worker_node> node-role.kubernetes.io/worker=""  # all the worker nodes so the pods can be allocated there
7) cd kube-burner/examples/workloads/kubelet-density-heavy
8) Edit the [run_experiment_with_delete.sh](https://github.com/gkoukis/kube-burner/blob/main/examples/workloads/kubelet-density-heavy/run_experiment_with_delete.sh) script, which script automates a **matrix of kube-burner runs** over different QPS/Burst and replica configurations e.g., jobIterations=1 qps=50 burst=50 postgres_deploy_replicas=1 app_deploy_replicas=1 postgres_service_replicas=1, and repeats the whole set multiple times. Select:
    - the iterations e.g., 6
    - experiment configuration for the selected qps and burst
    - the execution for one replica or for multiple

***Note that the 1st section in comments including "#experiments=(# "jobIterations=1 qps=1 burst=1 postgres_deploy_replicas=10 app_deploy_replicas=10 postgres_service_replicas=10" ...) etc. refers to the multiple replica scenarios**

9) Run the script
```bash
chmod +x extract_results.sh
chmod +x run_experiment_with_delete.sh
./run_experiment_with_delete.sh
```
10) After running the `kubelet-density-heavy` experiments run the [extract_results.sh](https://github.com/gkoukis/kube-burner/blob/main/examples/workloads/kubelet-density-heavy/extract_results.sh) to parse the logs from the generated files.


***For this experiments I'd recommend to 1st run: the single replica experiment i.e. the uncommented part of the script.**