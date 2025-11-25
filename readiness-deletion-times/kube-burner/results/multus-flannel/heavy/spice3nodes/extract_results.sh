#!/bin/bash

# Output file where the results will be saved
output_file="flannel-heavy_summary.txt"

# Clear the output file if it already exists
> "$output_file"

# Loop through all the log files
for log_file in kubelet-density-heavy_*.log; do
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
output_csv="flannel-heavy_summary.csv"

# Clear the CSV file if it already exists and add the header
echo "File,JobIterations,QPS,Burst,PostgresDeploy,App,PostgresService,50th,99th,Max,Avg" > "$output_csv"

# Loop through each line in the input summary file
while IFS= read -r line; do
  # Extract the file name
  file_name=$(echo "$line" | grep -oP 'File: \K\S+')

  # Extract job parameters from the file name
  job_iterations=$(echo "$file_name" | grep -oP 'jobIterations\K\d+')
  qps=$(echo "$file_name" | grep -oP 'qps\K\d+')
  burst=$(echo "$file_name" | grep -oP 'burst\K\d+')
  postgres_deploy=$(echo "$file_name" | grep -oP 'postgres-deploy\K\d+')
  app=$(echo "$file_name" | grep -oP 'app\K\d+')
  postgres_service=$(echo "$file_name" | grep -oP 'postgres-service\K\d+')

  # Extract metrics from the line
  fiftieth=$(echo "$line" | grep -oP '50th: \K\d+')
  ninety_ninth=$(echo "$line" | grep -oP '99th: \K\d+')
  max=$(echo "$line" | grep -oP 'max: \K\d+')
  avg=$(echo "$line" | grep -oP 'avg: \K\d+')

  # Write the extracted data to the CSV file, ensuring no missing values
  if [ -n "$fiftieth" ] && [ -n "$ninety_ninth" ] && [ -n "$max" ] && [ -n "$avg" ]; then
    echo "$file_name,$job_iterations,$qps,$burst,$postgres_deploy,$app,$postgres_service,$fiftieth,$ninety_ninth,$max,$avg" >> "$output_csv"
  fi

done < "$input_file"

echo "Data saved to $output_csv"