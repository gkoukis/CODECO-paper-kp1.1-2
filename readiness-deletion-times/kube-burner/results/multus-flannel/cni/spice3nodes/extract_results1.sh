#!/bin/bash
set -euo pipefail

output_csv="codeco-k8s-multus-flannel-cni-summary.csv"
echo "File,JobIterations,QPS,Burst,Webserver,Curl,Service,50th,99th,Max,Avg" > "$output_csv"

shopt -s nullglob
for log_file in kubelet-density-cni_*.log; do
  # Last ContainersReady line (in case there are multiple)
  line="$(grep -F 'ContainersReady' "$log_file" | tail -n1 || true)"
  [ -z "$line" ] && continue

  # Params from filename
  job_iterations=$(echo "$log_file" | grep -oP 'jobIterations\K\d+' || echo "")
  qps=$(echo "$log_file" | grep -oP 'qps\K\d+' || echo "")
  burst=$(echo "$log_file" | grep -oP 'burst\K\d+' || echo "")
  webserver=$(echo "$log_file" | grep -oP 'webserver\K\d+' || echo "")
  curlp=$(echo "$log_file" | grep -oP 'curl\K\d+' || echo "")
  service=$(echo "$log_file" | grep -oP 'service\K\d+' || echo "")

  # Metrics (use NA if missing)
  p50=$(echo "$line" | grep -oP '50th:\s*\K\d+' || true); p50=${p50:-NA}
  p99=$(echo "$line" | grep -oP '99th:\s*\K\d+' || true); p99=${p99:-NA}
  maxv=$(echo "$line" | grep -oP 'max:\s*\K\d+' || true); maxv=${maxv:-NA}
  avg=$(echo "$line" | grep -oP 'avg:\s*\K\d+' || true); avg=${avg:-NA}

  echo "$log_file,$job_iterations,$qps,$burst,$webserver,$curlp,$service,$p50,$p99,$maxv,$avg" >> "$output_csv"
done

echo "Data saved to $output_csv"
