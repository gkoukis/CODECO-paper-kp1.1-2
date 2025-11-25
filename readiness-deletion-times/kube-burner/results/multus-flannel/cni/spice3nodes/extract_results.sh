#!/bin/bash

# Output file where the results will be saved
output_file="codeco-k8s-multus-flannel-cni_summary.txt"

# Clear the output file if it already exists
> "$output_file"

# Loop through all the log files
for log_file in kubelet-density-cni_*.log; do
  # Search for lines containing "ContainersReady 50th:" and append them to the output file
  grep "ContainersReady 50th:" "$log_file" | while read -r line; do
    echo "File: $log_file - $line" >> "$output_file"
  done
done

echo "Summary saved to $output_file"

#### ----------------------------

# Input summary file
input_file=$output_file

# Output CSV file where the results will be saved
output_csv="codeco-k8s-multus-flannel-cni_summary.csv"

# Clear the CSV file if it already exists and add the header
echo "File,JobIterations,QPS,Burst,WebserverReplicas,CurlReplicas,ServiceReplicas,50th,99th,Max,Avg" > "$output_csv"

# Loop through each line in the input summary file
while IFS= read -r line; do
  # Extract the file name
  file_name=$(echo "$line" | grep -oP 'File: \K\S+')

  # Extract job parameters from the file name
  job_iterations=$(echo "$file_name" | grep -oP 'jobIterations\K\d+')
  qps=$(echo "$file_name" | grep -oP 'qps\K\d+')
  burst=$(echo "$file_name" | grep -oP 'burst\K\d+')
  webserver_replicas=$(echo "$file_name" | grep -oP 'webserver\K\d+')
  curl_replicas=$(echo "$file_name" | grep -oP 'curl\K\d+')
  service_replicas=$(echo "$file_name" | grep -oP 'service\K\d+')

  # Extract metrics from the line
  fiftieth=$(echo "$line" | grep -oP '50th: \K\d+')
  ninety_ninth=$(echo "$line" | grep -oP '99th: \K\d+')
  max=$(echo "$line" | grep -oP 'max: \K\d+')
  avg=$(echo "$line" | grep -oP 'avg: \K\d+')

  # Write the extracted data to the CSV file, ensuring no missing values
  if [ -n "$fiftieth" ] && [ -n "$ninety_ninth" ] && [ -n "$max" ] && [ -n "$avg" ]; then
    echo "$file_name,$job_iterations,$qps,$burst,$webserver_replicas,$curl_replicas,$service_replicas,$fiftieth,$ninety_ninth,$max,$avg" >> "$output_csv"
  fi

done < "$input_file"

echo "Data saved to $output_csv"
