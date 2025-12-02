# -*- coding: utf-8 -*-
"""
Creates 4 bar charts:
 - One for 10 pods
 - One for 50 pods
 - One for 100 pods
 - One for 150 pods

Y-axis: deletion time (ms)
X-axis: UCs (UC1..UC9)
For each UC: two bars (K8s, CODECO) with asymmetric error bars from min/max.
Bars use '//' hatch for visual distinction.

Additionally:
 - Each bar is annotated with the standard deviation (std) inside the bar.
"""

import os
import numpy as np
import matplotlib.pyplot as plt

# -----------------------------------------------------------
# 1) INPUT DATA  (put your real values here)
# -----------------------------------------------------------

pod_counts = [10, 50, 100, 150]

# delete_data[UC][platform]['mean'/'min'/'max'/'std'] = list of 4 values for [10,50,100,150]
# NOTE: std values are currently 0, just so the script runs.
#       Replace them with your actual std dev per (UC, platform, pod_count).
delete_data = {
    "UC1": {
        "K8s": {
            "mean": [0, 0, 0, 0],
            "min":  [0, 0, 0, 0],
            "max":  [0, 0, 0, 0],
            "std":  [0,   0,   0,    0],
        },
        "CODECO": {
            "mean": [0, 0, 0, 0],
            "min":  [0, 0, 0, 0],
            "max":  [0, 0, 0, 0],
            "std":  [0,   0,   0,    0],
        },
    },
    "UC2": {
        "K8s": {
            "mean": [0, 0, 0, 0],
            "min":  [0, 0, 0, 0],
            "max":  [0, 0, 0, 0],
            "std":  [0,   0,   0,    0],
        },
        "CODECO": {
            "mean": [0, 0, 0, 0],
            "min":  [0, 0, 0, 0],
            "max":  [0, 0, 0, 0],
            "std":  [0,   0,   0,    0],
        },
    },
    "UC3": {
        "K8s": {
            "mean": [0, 0, 0, 0],
            "min":  [0, 0, 0, 0],
            "max":  [0, 0, 0, 0],
            "std":  [0,   0,   0,    0],
        },
        "CODECO": {
            "mean": [0, 0, 0, 0],
            "min":  [0, 0, 0, 0],
            "max":  [0, 0, 0, 0],
            "std":  [0,   0,   0,    0],
        },
    },
    "UC4": {
        "K8s": {
            "mean": [0, 0, 0, 0],
            "min":  [0, 0, 0, 0],
            "max":  [0, 0, 0, 0],
            "std":  [0,   0,   0,    0],
        },
        "CODECO": {
            "mean": [0, 0, 0, 0],
            "min":  [0, 0, 0, 0],
            "max":  [0, 0, 0, 0],
            "std":  [0,   0,   0,    0],
        },
    },
    "UC5": {
        "K8s": {
            "mean": [0, 0, 0, 0],
            "min":  [0, 0, 0, 0],
            "max":  [0, 0, 0, 0],
            "std":  [0,   0,   0,    0],
        },
        "CODECO": {
            "mean": [0, 0, 0, 0],
            "min":  [0, 0, 0, 0],
            "max":  [0, 0, 0, 0],
            "std":  [0,   0,   0,    0],
        },
    },
    "UC6": {
        "K8s": {
            "mean": [0, 0, 0, 0],
            "min":  [0, 0, 0, 0],
            "max":  [0, 0, 0, 0],
            "std":  [0,   0,   0,    0],
        },
        "CODECO": {
            "mean": [0, 0, 0, 0],
            "min":  [0, 0, 0, 0],
            "max":  [0, 0, 0, 0],
            "std":  [0,   0,   0,    0],
        },
    },
    "UC7": {
        "K8s": {
            "mean": [0, 0, 0, 0],
            "min":  [0, 0, 0, 0],
            "max":  [0, 0, 0, 0],
            "std":  [0,   0,   0,    0],
        },
        "CODECO": {
            "mean": [0, 0, 0, 0],
            "min":  [0, 0, 0, 0],
            "max":  [0, 0, 0, 0],
            "std":  [0,   0,   0,    0],
        },
    },
    "UC8": {
        "K8s": {
            "mean": [0, 0, 0, 0],
            "min":  [0, 0, 0, 0],
            "max":  [0, 0, 0, 0],
            "std":  [0,   0,   0,    0],
        },
        "CODECO": {
            "mean": [0, 0, 0, 0],
            "min":  [0, 0, 0, 0],
            "max":  [0, 0, 0, 0],
            "std":  [0,   0,   0,    0],
        },
    },
    "UC9": { #done
        "K8s": {
            "mean": [2113, 4470, 7620, 11446],
            "min":  [2025, 4157, 7411, 10963],
            "max":  [2250, 4843, 7803, 12202],
            "std":  [106,   251,   168,    414],  # fill with real std later
        },
        "CODECO": {
            "mean": [2121, 4479, 8116, 12008],
            "min":  [2017, 4263, 7857, 11502],
            "max":  [2249, 4779, 8522, 12529],
            "std":  [82,   181,   284,    432],  # fill with real std later
        },
    },
}

# -----------------------------------------------------------
# 2) PLOTTING
# -----------------------------------------------------------

out_dir = "pod_deletion_all_in_one_stdiv"
os.makedirs(out_dir, exist_ok=True)

ucs = sorted(delete_data.keys())  # UC1..UC9

bar_width = 0.35
capsize = 3
colors = {"K8s": "tab:red", "CODECO": "tab:blue"}

for idx, pod in enumerate(pod_counts):
    fig, ax = plt.subplots(figsize=(6, 4), dpi=150)

    x = np.arange(len(ucs))  # positions for UCs

    ymax_candidate = 0.0
    handles = []
    labels = []

    for j, platform in enumerate(["K8s", "CODECO"]):
        means = []
        mins = []
        maxs = []
        stds = []

        for uc in ucs:
            means.append(delete_data[uc][platform]["mean"][idx])
            mins.append(delete_data[uc][platform]["min"][idx])
            maxs.append(delete_data[uc][platform]["max"][idx])
            stds.append(delete_data[uc][platform]["std"][idx])

        means = np.asarray(means, dtype=float)
        mins = np.asarray(mins, dtype=float)
        maxs = np.asarray(maxs, dtype=float)
        stds = np.asarray(stds, dtype=float)

        lower = np.clip(means - mins, 0, None)
        upper = np.clip(maxs - means, 0, None)
        yerr = np.vstack([lower, upper])

        positions = x + (j - 0.5) * bar_width

        bars = ax.bar(
            positions,
            means,
            width=bar_width,
            yerr=yerr,
            capsize=capsize,
            color=colors[platform],
            alpha=0.9,
            edgecolor="black",
            linewidth=0.3,
            label=platform,
            hatch="//",  # hatch style
        )
        handles.append(bars)
        labels.append(platform)

        ymax_candidate = max(ymax_candidate, np.max(maxs))

        # ---- annotate each bar with its std dev (inside bar) ----
        for bar, sd in zip(bars, stds):
            height = bar.get_height()
            ax.text(
                bar.get_x() + bar.get_width() / 2.0,
                height * 0.5,               # inside bar
                f"stdiv={sd:.0f}",          # label text
                ha="center",
                va="center",
                fontsize=7,
                color="white",
                rotation=90,
                # fontweight="bold",
            )

    ax.set_xticks(x)
    ax.set_xticklabels(ucs, rotation=45)
    ax.set_ylabel("Deletion Time (ms)")
    ax.set_xlabel("Use Case")
    ax.set_title(f"Pod Deletion Time for {pod} Pods")
    ax.grid(True, axis="y", linestyle="--", linewidth=0.5, alpha=0.6)
    ax.set_ylim(0, 1.45 * ymax_candidate)  # extra room if needed

    # Legend inside plot (top-right)
    ax.legend(
        handles,
        labels,
        frameon=False,
        fontsize=9,
        loc="upper right",
        bbox_to_anchor=(0.99, 1),
    )

    fig.tight_layout()
    out_path = os.path.join(out_dir, f"deletion_{pod}pods.png")
    fig.savefig(out_path, bbox_inches="tight")
    plt.show()
    plt.close(fig)

print(f"Saved deletion plots to: {os.path.abspath(out_dir)}")
