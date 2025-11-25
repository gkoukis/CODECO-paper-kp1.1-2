#!/bin/bash
set -euo pipefail

output_csv="codeco-k8s-multus-flannel-heavy_summary.csv"
echo "File,JobIterations,QPS,Burst,PostgresDeploy,App,PostgresService,50th,99th,Max,Avg" > "$output_csv"

shopt -s nullglob
for log_file in kubelet-density-heavy_*.log; do
  # Get the last ContainersReady line (in case there are multiple)
  line="$(grep -F 'ContainersReady' "$log_file" | tail -n1 || true)"
  [ -z "$line" ] && continue

  # Params from filename
  job_iterations=$(echo "$log_file" | grep -oP 'jobIterations\K\d+' || echo "")
  qps=$(echo "$log_file" | grep -oP 'qps\K\d+' || echo "")
  burst=$(echo "$log_file" | grep -oP 'burst\K\d+' || echo "")
  postgres_deploy=$(echo "$log_file" | grep -oP 'postgres-deploy\K\d+' || echo "")
  app=$(echo "$log_file" | grep -oP 'app\K\d+' || echo "")
  postgres_service=$(echo "$log_file" | grep -oP 'postgres-service\K\d+' || echo "")

  # Metrics (use NA when missing)
  p50=$(echo "$line" | grep -oP '50th:\s*\K\d+' || true); p50=${p50:-NA}
  p99=$(echo "$line" | grep -oP '99th:\s*\K\d+' || true); p99=${p99:-NA}
  maxv=$(echo "$line" | grep -oP 'max:\s*\K\d+' || true); maxv=${maxv:-NA}
  avg=$(echo "$line" | grep -oP 'avg:\s*\K\d+' || true); avg=${avg:-NA}

  echo "$log_file,$job_iterations,$qps,$burst,$postgres_deploy,$app,$postgres_service,$p50,$p99,$maxv,$avg" >> "$output_csv"
done

echo "Data saved to $output_csv"
