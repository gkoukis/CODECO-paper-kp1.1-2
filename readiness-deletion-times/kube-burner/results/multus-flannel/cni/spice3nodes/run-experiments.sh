#!/bin/bash

# Define an array of jobIterations values
#jobIterations_values=(1 10 20 40 50)
jobIterations_values=(1)

# Define an array of qps values
#qps_values=(1 10 25 50 75 100)
qps_values=(10)

# Define an array of burst values
#burst_values=(1 10 25 50 75 100)
burst_values=(10)

# Define replicas for the webserver and curl deployments
webserver_replicas_values=(10)
curl_replicas_values=(10)
service_replicas_values=(1)  # Service replicas usually remain 1


### 2ND OPTION: OR LIKE THIS AND ALSO CHANGE THE FOR
## Define the experiments with all metrics
#experiments=(
 "jobIterations=10 qps=25 burst=25 webserver_replicas=10 curl_replicas=10 service_replicas=1"
  "jobIterations=20 qps=50 burst=50 webserver_replicas=20 curl_replicas=20 service_replicas=1"
  "jobIterations=50 qps=75 burst=100 webserver_replicas=30 curl_replicas=30 service_replicas=1"
  "jobIterations=10 qps=50 burst=25 webserver_replicas=15 curl_replicas=15 service_replicas=1"
  "jobIterations=20 qps=25 burst=75 webserver_replicas=20 curl_replicas=10 service_replicas=1"
#  # Add more experiment combinations as needed
#)



## Output file for ContainersReady summary
#output_file="containers_ready_summary.txt"
#
## Clear the output file if it already exists
#> "$output_file"


## 2ND OPTION: Loop over the defined experiments
#for experiment in "${experiments[@]}"; do
#  echo "Running experiment with $experiment"
#
#  # Parse the experiment string to extract the variables
#  eval $experiment


# Loop over the combinations
for jobIterations in "${jobIterations_values[@]}"; do
  for qps in "${qps_values[@]}"; do
    for burst in "${burst_values[@]}"; do
      for webserver_replicas in "${webserver_replicas_values[@]}"; do
        for curl_replicas in "${curl_replicas_values[@]}"; do
          for service_replicas in "${service_replicas_values[@]}"; do
            echo "Running experiment with jobIterations=$jobIterations, qps=$qps, burst=$burst, webserver_replicas=$webserver_replicas, curl_replicas=$curl_replicas, service_replicas=$service_replicas"

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

            # Identify the automatically created log file
            log_file=$(ls -t kube-burner-*.log | head -n 1)

            # Define a new name for the log file based on the experiment parameters
            new_log_file="kubelet-density-cni_jobIterations${jobIterations}_qps${qps}_burst${burst}_webserver${webserver_replicas}_curl${curl_replicas}_service${service_replicas}.log"

            # Rename the automatically created log file
            mv "$log_file" "$new_log_file"

            ## Extract the relevant "ContainersReady 50th:" line and append it to the summary file
            #grep "ContainersReady 50th:" "$new_log_file" | while read -r line; do
            #  echo "File: $new_log_file - $line" >> "$output_file"
            #done

            # Sleep for 30 seconds between experiments
            echo "Sleeping for 30 seconds before the next experiment..."
            sleep 30

          done
        done
      done
    done
  done
done

echo "All experiments completed. Summary saved to $output_file"