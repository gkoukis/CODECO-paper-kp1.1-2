#!/usr/bin/env python3
import sys
import numpy as np

"""
Usage:
    python3 compute_std.py total_pod_creation_times_ath-cam_pods150.txt
"""

def read_batch_readiness_times(filepath):
    values = []
    with open(filepath, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("Iteration"):
                continue

            # Skip summary lines
            if line.startswith("Average Batch") or line.startswith("Final Average"):
                continue

            # Expected format:
            # iteration, total_latency, avg_latency_per_pod, batch_readiness_time
            parts = line.split(",")
            if len(parts) < 4:
                continue

            try:
                batch_time = float(parts[3])
                values.append(batch_time)
            except ValueError:
                pass

    return np.asarray(values, dtype=float)

def main():
    if len(sys.argv) != 2:
        print("Usage: python3 compute_std.py <metrics_file.txt>")
        sys.exit(1)

    filepath = sys.argv[1]
    values = read_batch_readiness_times(filepath)

    if len(values) == 0:
        print("No valid data found in file.")
        sys.exit(1)

    mean = np.mean(values)
    std  = np.std(values, ddof=1)    # sample standard deviation
    vmin = np.min(values)
    vmax = np.max(values)

    print("----- Results -----")
    print(f"Values: {values.tolist()}")
    print(f"Mean: {mean:.2f} ms")
    print(f"Std Dev: {std:.2f} ms")
    print(f"Min: {vmin:.2f} ms")
    print(f"Max: {vmax:.2f} ms")

if __name__ == "__main__":
    main()
