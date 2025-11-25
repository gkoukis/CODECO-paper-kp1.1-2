#!/bin/bash

# Define the number of times to repeat the entire set of experiments
iterations=10

# Define the experiments with all metrics
#experiments=(
# "jobIterations=1 qps=1 burst=1 postgres_deploy_replicas=10 app_deploy_replicas=10 postgres_service_replicas=10"
# "jobIterations=1 qps=10 burst=10 postgres_deploy_replicas=10 app_deploy_replicas=10 postgres_service_replicas=10"
# "jobIterations=1 qps=25 burst=25 postgres_deploy_replicas=10 app_deploy_replicas=10 postgres_service_replicas=10"
# "jobIterations=1 qps=50 burst=50 postgres_deploy_replicas=10 app_deploy_replicas=10 postgres_service_replicas=10"
# "jobIterations=1 qps=75 burst=75 postgres_deploy_replicas=10 app_deploy_replicas=10 postgres_service_replicas=10"
# "jobIterations=1 qps=100 burst=100 postgres_deploy_replicas=10 app_deploy_replicas=10 postgres_service_replicas=10"
# "jobIterations=1 qps=1 burst=1 postgres_deploy_replicas=20 app_deploy_replicas=20 postgres_service_replicas=20"
# "jobIterations=1 qps=10 burst=10 postgres_deploy_replicas=20 app_deploy_replicas=20 postgres_service_replicas=20"
# "jobIterations=1 qps=25 burst=25 postgres_deploy_replicas=20 app_deploy_replicas=20 postgres_service_replicas=20"
# "jobIterations=1 qps=50 burst=50 postgres_deploy_replicas=20 app_deploy_replicas=20 postgres_service_replicas=20"
# "jobIterations=1 qps=75 burst=75 postgres_deploy_replicas=20 app_deploy_replicas=20 postgres_service_replicas=20"
# "jobIterations=1 qps=100 burst=100 postgres_deploy_replicas=20 app_deploy_replicas=20 postgres_service_replicas=20"
# "jobIterations=1 qps=1 burst=1 postgres_deploy_replicas=40 app_deploy_replicas=40 postgres_service_replicas=40"
# "jobIterations=1 qps=10 burst=10 postgres_deploy_replicas=40 app_deploy_replicas=40 postgres_service_replicas=40"
# "jobIterations=1 qps=25 burst=25 postgres_deploy_replicas=40 app_deploy_replicas=40 postgres_service_replicas=40"
# "jobIterations=1 qps=50 burst=50 postgres_deploy_replicas=40 app_deploy_replicas=40 postgres_service_replicas=40"
# "jobIterations=1 qps=75 burst=75 postgres_deploy_replicas=40 app_deploy_replicas=40 postgres_service_replicas=40"
# "jobIterations=1 qps=100 burst=100 postgres_deploy_replicas=40 app_deploy_replicas=40 postgres_service_replicas=40"
# "jobIterations=1 qps=1 burst=1 postgres_deploy_replicas=50 app_deploy_replicas=50 postgres_service_replicas=50"
# "jobIterations=1 qps=10 burst=10 postgres_deploy_replicas=50 app_deploy_replicas=50 postgres_service_replicas=50"
# "jobIterations=1 qps=25 burst=25 postgres_deploy_replicas=50 app_deploy_replicas=50 postgres_service_replicas=50"
# "jobIterations=1 qps=50 burst=50 postgres_deploy_replicas=50 app_deploy_replicas=50 postgres_service_replicas=50"
# "jobIterations=1 qps=75 burst=75 postgres_deploy_replicas=50 app_deploy_replicas=50 postgres_service_replicas=50"
# "jobIterations=1 qps=100 burst=100 postgres_deploy_replicas=50 app_deploy_replicas=50 postgres_service_replicas=50"
# # Add more experiment combinations as needed
#)

# Define the experiments with all metrics
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


## Output file for ContainersReady summary
#output_file="containers_ready_summary.txt"

## Clear the output file if it already exists
#> "$output_file"


# Determine the starting counter value by checking existing log files
if ls kubelet-density-heavy_*.log 1> /dev/null 2>&1; then
  # Extract the highest counter from existing log files
  counter=$(ls kubelet-density-heavy_*.log | grep -o 'kubelet-density-heavy_.*_.*_.*_.*_.*_.*_[0-9]*\.log' | grep -o '[0-9]*' | sort -n | tail -1)
  counter=$((counter + 1))
else
  counter=1
fi


# Outer loop to repeat the experiments multiple times
for (( run=1; run<=iterations; run++ )); do
  echo "Starting run $run of $iterations"

  # Loop over the defined experiments
  for experiment in "${experiments[@]}"; do
    echo "Running experiment with $experiment"

    # Before creating any resources, check if namespace exists and delete if it does
    if kubectl get namespace kubelet-density-heavy &> /dev/null; then
      echo "Namespace 'kubelet-density-heavy' already exists. Deleting it (and all contained resources)..."
      kubectl delete namespace kubelet-density-heavy

      # Wait for namespace to terminate fully
      while kubectl get namespace kubelet-density-heavy &> /dev/null; do
        echo "Waiting for namespace 'kubelet-density-heavy' to be deleted..."
        sleep 5
      done
      echo "Namespace 'kubelet-density-heavy' successfully deleted."
    fi

    # kubectl create ns kubelet-density-heavy
    # kubectl apply -f /home/athena/poc/calico-secondary-nad-new.yaml
    # kubectl apply -f /home/athena/poc/flannel-nad.yaml

    # Parse the experiment string to extract the variables
    eval $experiment

    # Export variables to be used in envsubst
    export JOB_ITERATIONS=$jobIterations
    export QPS=$qps
    export BURST=$burst
    export POSTGRES_DEPLOY_REPLICAS=$postgres_deploy_replicas
    export APP_DEPLOY_REPLICAS=$app_deploy_replicas
    export POSTGRES_SERVICE_REPLICAS=$postgres_service_replicas

    # Use envsubst to replace variables in the YAML template and then run kube-burner
    envsubst < kubelet-density-heavy.template.yml > kubelet-density-heavy.yml

    # Run kube-burner (log will be created automatically)
    kube-burner init -c kubelet-density-heavy.yml
    ### Check the microk8s.txt if using microk8s distro and use this command instead
    #kube-burner init -c kubelet-density-cni.yml --kubeconfig ~/.kube/config

    # Identify the automatically created log file
    log_file=$(ls -t kube-burner-*.log | head -n 1)

    # Define a new name for the log file based on the experiment parameters
    new_log_file="kubelet-density-heavy_jobIterations${jobIterations}_qps${qps}_burst${burst}_postgres-deploy${postgres_deploy_replicas}_app${app_deploy_replicas}_postgres-service${postgres_service_replicas}_${counter}.log"

    # Rename the automatically created log file
    mv "$log_file" "$new_log_file"

  #  # Extract the relevant "ContainersReady 50th:" line and append it to the summary file
  #  grep "ContainersReady 50th:" "$new_log_file" | while read -r line; do
  #    echo "File: $new_log_file - $line" >> "$output_file"
  #  done

    # Increment the counter for the next experiment
    counter=$((counter + 1))

    # Sleep for 30 seconds between experiments
    echo "Sleeping for 30 seconds before the next experiment..."
    sleep 30
    echo "..."
    echo "..."
  done
done

echo "All experiments completed. Summary saved to $output_file"
