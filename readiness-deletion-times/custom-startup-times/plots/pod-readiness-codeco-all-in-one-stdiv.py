# -*- coding: utf-8 -*-
"""
Creates 4 bar charts:
 - One for 10 pods
 - One for 50 pods
 - One for 100 pods
 - One for 150 pods

Y-axis: readiness time (ms)
X-axis: UCs (UC1..UC9)
For each UC: two bars (K8s, CODECO) with asymmetric error bars from min/max.

Additionally:
 - Each bar is annotated with the standard deviation (std) on top.
"""

import os
import numpy as np
import matplotlib.pyplot as plt

# -----------------------------------------------------------
# 1) INPUT DATA  (put your real values here)
# -----------------------------------------------------------

pod_counts = [10, 50, 100, 150]

# data[UC][platform]['mean'/'min'/'max'/'std'] = list of 4 values for [10,50,100,150]
# NOTE: std values are currently 0, just so the script runs.
#       Replace them with your actual std dev per (UC, platform, pod_count).
data = {
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
    "UC9": {  # done
        "K8s": {
            "mean": [3000, 9842, 18503, 27634],
            "min":  [2877, 9369, 18277, 27533],
            "max":  [3165, 10180, 19111, 27740],
            "std":  [99,    287,    308,    84],
        },
        "CODECO": {
            "mean": [3120, 11357, 21507, 33341],
            "min":  [3029, 10734, 21028, 33209],
            "max":  [3324, 11607, 21899, 33469],
            "std":  [114,    318,    379,    93],
        },
    },
}

# -----------------------------------------------------------
# 2) PLOTTING
# -----------------------------------------------------------

out_dir = "pod_readiness_all_in_one_stdiv"
os.makedirs(out_dir, exist_ok=True)

ucs = list(data.keys())
ucs.sort()  # UC1..UC9

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
            means.append(data[uc][platform]["mean"][idx])
            mins.append(data[uc][platform]["min"][idx])
            maxs.append(data[uc][platform]["max"][idx])
            stds.append(data[uc][platform]["std"][idx])  # <-- get std

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
        )
        handles.append(bars)
        labels.append(platform)

        ymax_candidate = max(ymax_candidate, np.max(maxs))

        # ---- annotate each bar with its std dev ----
        for bar, sd in zip(bars, stds):
            height = bar.get_height()
            # ax.text(
            #     bar.get_x() + bar.get_width() / 2.0,
            #     height + 0.06 * ymax_candidate,  # small offset above bar
            #     f"{sd:.0f}",                     # shows e.g. '120'
            #     ha="center",
            #     va="bottom",
            #     fontsize=7,
            #     rotation=45,                     # vertical to save horizontal space
            # )
            ax.text(
                bar.get_x() + bar.get_width() / 2.0,
                height * 0.5,  # inside bar
                f"stdiv={sd:.0f}",  # label
                ha="center",
                va="center",
                fontsize=7,
                color="white",
                rotation=90
                #fontweight="bold"
            )

    ax.set_xticks(x)
    ax.set_xticklabels(ucs, rotation=45)
    ax.set_ylabel("Readiness Time (ms)")
    ax.set_xlabel("Use Case")
    ax.set_title(f"Pod Readiness for {pod} Pods")
    ax.grid(True, axis="y", linestyle="--", linewidth=0.5, alpha=0.6)
    ax.set_ylim(0, 1.45 * ymax_candidate)  # slightly more room for labels

    # ---------- LEGEND INSIDE PLOT ----------
    ax.legend(
        handles,
        labels,
        frameon=False,
        fontsize=9,
        loc="upper right",
        bbox_to_anchor=(0.99, 1),
    )

    fig.tight_layout()
    out_path = os.path.join(out_dir, f"readiness_{pod}pods.png")
    fig.savefig(out_path, bbox_inches="tight")
    plt.show()
    plt.close(fig)

print(f"Saved plots to: {os.path.abspath(out_dir)}")
