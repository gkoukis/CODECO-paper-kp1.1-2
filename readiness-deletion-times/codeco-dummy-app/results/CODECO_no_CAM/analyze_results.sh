#!/bin/bash
#
# Analyze results from codeco_dummy_app_*.txt
# Computes min, max, mean, stddev for deploy and delete times grouped by frontend replicas.
#
# Usage:
#   ./analyze_codeco_results.sh codeco_dummy_app_20251207_183227.txt
#

if [ $# -lt 1 ]; then
  echo "Usage: $0 <results_file.txt>"
  exit 1
fi

results_file="$1"

if [ ! -f "$results_file" ]; then
  echo "File not found: $results_file"
  exit 1
fi

echo "============================================="
echo "Analyzing results from: $results_file"
echo "============================================="

# Extract unique frontend replica counts from CSV lines
replicas_list=$(grep -E '^[0-9]+,[0-9]+,' "$results_file" | cut -d',' -f2 | sort -n | uniq)

for N in $replicas_list; do
  echo
  echo "---------------------------------------------------------"
  echo "Frontend Replicas = $N"
  echo "---------------------------------------------------------"

  # Extract deploy & delete times for this N
  data=$(grep -E "^[0-9]+,${N}," "$results_file")

  if [ -z "$data" ]; then
    echo "No data for N=$N"
    continue
  fi

  # Deploy time stats
  deploy_stats=$(echo "$data" | awk -F',' '
    { d[NR]=$3; sum+=$3; sumsq+=$3*$3 }
    END {
      n=NR
      mean=sum/n
      variance=(sumsq/n)-(mean*mean)
      sd=(variance>0)?sqrt(variance):0

      min=d[1]; max=d[1]
      for(i=2;i<=n;i++){
        if(d[i]<min) min=d[i]
        if(d[i]>max) max=d[i]
      }

      printf("Deploy Time (ms) → min=%d  max=%d  mean=%.2f  stddev=%.2f\n",
             min, max, mean, sd)
    }
  ')

  # Delete time stats
  delete_stats=$(echo "$data" | awk -F',' '
    { d[NR]=$4; sum+=$4; sumsq+=$4*$4 }
    END {
      n=NR
      mean=sum/n
      variance=(sumsq/n)-(mean*mean)
      sd=(variance>0)?sqrt(variance):0

      min=d[1]; max=d[1]
      for(i=2;i<=n;i++){
        if(d[i]<min) min=d[i]
        if(d[i]>max) max=d[i]
      }

      printf("Delete Time (ms) → min=%d  max=%d  mean=%.2f  stddev=%.2f\n",
             min, max, mean, sd)
    }
  ')

  echo "$deploy_stats"
  echo "$delete_stats"
done

echo
echo "============================================="
echo "Analysis completed."
echo "============================================="