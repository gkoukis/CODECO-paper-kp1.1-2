#!/bin/bash

# Define the number of times to repeat the entire set of experiments
iterations=10

## Define the experiments with all metrics
#experiments=(
#  "jobIterations=1 qps=1 burst=1 webserver_replicas=10 curl_replicas=10 service_replicas=1"
#  "jobIterations=1 qps=1 burst=1 webserver_replicas=20 curl_replicas=20 service_replicas=1"
#  "jobIterations=1 qps=1 burst=1 webserver_replicas=40 curl_replicas=40 service_replicas=1"
#  "jobIterations=1 qps=1 burst=1 webserver_replicas=50 curl_replicas=50 service_replicas=1"
#  "jobIterations=1 qps=10 burst=10 webserver_replicas=10 curl_replicas=10 service_replicas=1"
#  "jobIterations=1 qps=10 burst=10 webserver_replicas=20 curl_replicas=20 service_replicas=1"
#  "jobIterations=1 qps=10 burst=10 webserver_replicas=40 curl_replicas=40 service_replicas=1"
#  "jobIterations=1 qps=10 burst=10 webserver_replicas=50 curl_replicas=50 service_replicas=1"
#  "jobIterations=1 qps=25 burst=25 webserver_replicas=10 curl_replicas=10 service_replicas=1"
#  "jobIterations=1 qps=50 burst=50 webserver_replicas=10 curl_replicas=10 service_replicas=1"
#  "jobIterations=1 qps=75 burst=75 webserver_replicas=10 curl_replicas=10 service_replicas=1"
#  "jobIterations=1 qps=100 burst=100 webserver_replicas=10 curl_replicas=10 service_replicas=1"
#  "jobIterations=1 qps=25 burst=25 webserver_replicas=20 curl_replicas=20 service_replicas=1"
#  "jobIterations=1 qps=50 burst=50 webserver_replicas=20 curl_replicas=20 service_replicas=1"
#  "jobIterations=1 qps=75 burst=75 webserver_replicas=20 curl_replicas=20 service_replicas=1"
#  "jobIterations=1 qps=100 burst=100 webserver_replicas=20 curl_replicas=20 service_replicas=1"
#  "jobIterations=1 qps=25 burst=25 webserver_replicas=40 curl_replicas=40 service_replicas=1"
#  "jobIterations=1 qps=50 burst=50 webserver_replicas=40 curl_replicas=40 service_replicas=1"
#  "jobIterations=1 qps=75 burst=75 webserver_replicas=40 curl_replicas=40 service_replicas=1"
#  "jobIterations=1 qps=100 burst=100 webserver_replicas=40 curl_replicas=40 service_replicas=1"
#  "jobIterations=1 qps=25 burst=25 webserver_replicas=50 curl_replicas=50 service_replicas=1"
#  "jobIterations=1 qps=50 burst=50 webserver_replicas=50 curl_replicas=50 service_replicas=1"
#  "jobIterations=1 qps=75 burst=75 webserver_replicas=50 curl_replicas=50 service_replicas=1"
#  "jobIterations=1 qps=100 burst=100 webserver_replicas=50 curl_replicas=50 service_replicas=1"
#  # Add more experiment combinations as needed
#)

# Define the experiments with all metrics
experiments=(
  "jobIterations=1 qps=1 burst=1 webserver_replicas=1 curl_replicas=1 service_replicas=1"
  "jobIterations=1 qps=10 burst=10 webserver_replicas=1 curl_replicas=1 service_replicas=1"
  "jobIterations=1 qps=25 burst=25 webserver_replicas=1 curl_replicas=1 service_replicas=1"
  "jobIterations=1 qps=50 burst=50 webserver_replicas=1 curl_replicas=1 service_replicas=1"
  "jobIterations=1 qps=75 burst=75 webserver_replicas=1 curl_replicas=1 service_replicas=1"
  "jobIterations=1 qps=100 burst=100 webserver_replicas=1 curl_replicas=1 service_replicas=1"
#  "jobIterations=10 qps=1 burst=1 webserver_replicas=1 curl_replicas=1 service_replicas=1"
#  "jobIterations=10 qps=10 burst=10 webserver_replicas=1 curl_replicas=1 service_replicas=1"
#  "jobIterations=10 qps=25 burst=25 webserver_replicas=1 curl_replicas=1 service_replicas=1"
#  "jobIterations=10 qps=50 burst=50 webserver_replicas=1 curl_replicas=1 service_replicas=1"
#  "jobIterations=10 qps=75 burst=75 webserver_replicas=1 curl_replicas=1 service_replicas=1"
#  "jobIterations=10 qps=100 burst=100 webserver_replicas=1 curl_replicas=1 service_replicas=1"
#  # Add more experiment combinations as needed
)

## Output file for ContainersReady summary
#output_file="containers_ready_summary.txt"

## Clear the output file if it already exists
#> "$output_file"


# Determine the starting counter value by checking existing log files
if ls kubelet-density-cni_*.log 1> /dev/null 2>&1; then
  # Extract the highest counter from existing log files
  counter=$(ls kubelet-density-cni_*.log | grep -o 'kubelet-density-cni_.*_.*_.*_.*_.*_.*_[0-9]*\.log' | grep -o '[0-9]*' | sort -n | tail -1)
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
    if kubectl get namespace kubelet-density-cni &> /dev/null; then
      echo "Namespace 'kubelet-density-cni' already exists. Deleting it (and all contained resources)..."
      kubectl delete namespace kubelet-density-cni

      # Wait for namespace to terminate fully
      while kubectl get namespace kubelet-density-cni &> /dev/null; do
        echo "Waiting for namespace 'kubelet-density-cni' to be deleted..."
        sleep 5
      done
      echo "Namespace 'kubelet-density-cni' successfully deleted."
    fi

    # kubectl create ns kubelet-density-cni
    # kubectl apply -f /home/athena/poc/calico-secondary-nad-new.yaml
    # kubectl apply -f /home/athena/poc/flannel-nad.yaml

    # Parse the experiment string to extract the variables
    eval $experiment

    # Export variables to be used in envsubst
    export JOB_ITERATIONS=$jobIterations
    export QPS=$qps
    export BURST=$burst
    export WEBSERVER_REPLICAS=$webserver_replicas
    export CURL_REPLICAS=$curl_replicas
    export SERVICE_REPLICAS=$service_replicas

    # Use envsubst to replace variables in the YAML template and then run kube-burner
    envsubst < kubelet-density-cni.template.yml > kubelet-density-cni.yml

    # Run kube-burner (log will be created automatically)
    kube-burner init -c kubelet-density-cni.yml
    ### Check the microk8s.txt if using microk8s distro and use this command instead
    #kube-burner init -c kubelet-density-cni.yml --kubeconfig ~/.kube/config

    # Identify the automatically created log file
    log_file=$(ls -t kube-burner-*.log | head -n 1)

    # Define a new name for the log file based on the experiment parameters
    new_log_file="kubelet-density-cni_jobIterations${jobIterations}_qps${qps}_burst${burst}_webserver${webserver_replicas}_curl${curl_replicas}_service${service_replicas}_${counter}.log"

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
