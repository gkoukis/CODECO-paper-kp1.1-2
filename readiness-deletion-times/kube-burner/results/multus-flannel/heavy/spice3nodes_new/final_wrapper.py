# import pandas as pd
# import matplotlib.pyplot as plt
# import numpy as np
# import os
#
# ####################
# # ONE APP
# ####################
#
# # Define the patterns to match the desired metrics and their friendly names
# patterns = {
#     "kubelet-density-heavy_jobIterations1_qps1_burst1_postgres-deploy1_app1_postgres-service1": "qps-burst1-app1",
#     "kubelet-density-heavy_jobIterations1_qps10_burst10_postgres-deploy1_app1_postgres-service1": "qps-burst10-app1",
#     "kubelet-density-heavy_jobIterations1_qps25_burst25_postgres-deploy1_app1_postgres-service1": "qps-burst25-app1",
#     "kubelet-density-heavy_jobIterations1_qps50_burst50_postgres-deploy1_app1_postgres-service1": "qps-burst50-app1",
#     "kubelet-density-heavy_jobIterations1_qps75_burst75_postgres-deploy1_app1_postgres-service1": "qps-burst75-app1",
#     "kubelet-density-heavy_jobIterations1_qps100_burst100_postgres-deploy1_app1_postgres-service1": "qps-burst100-app1"
# }
#
# # Define the color map for each CNI plugin
# color_map = {
#     "Antrea": "#17becf",   # Teal
#     "Calico": "#1f77b4",   # Medium Blue
#     "Cilium": "#2ca02c",   # Standard Green
#     "Flannel": "#d62728",  # Standard Red
#     "Kovn": "#9467bd",     # Purple
#     "Krouter": "#8c564b",  # Brown
#     "K3s Calico": "#aec7e8", # Light Blue
#     "K3s Cilium": "#98df8a", # Light Green
#     "K3s Flannel": "#ff7f7f", # Light Red
#     "Mk8s Calico": "#0b559f", # Dark Blue
#     "Mk8s Flannel": "#a71a1a", # Dark Red
#     "Mk8s Cilium": "#207525" # Dark Green
# }
#
# # Function to filter and extract average values based on patterns
# def extract_avg_values(df, patterns):
#     result = {}
#     for pattern, friendly_name in patterns.items():
#         filtered_df = df[df['File'].str.contains(pattern)]
#         avg_value = filtered_df['Avg'].mean() if not filtered_df.empty else None
#         result[friendly_name] = avg_value
#     return result
#
# # File paths for each CNI plugin
# file_paths = {
#     "Antrea": r'C:\Users\georg\Desktop\wsl2\codeco-experiments\test-list\kube-burner\examples\workloads\kubelet-density-heavy\plugins\antrea\antrea-heavy_summary.csv',
#     "Calico": r'C:\Users\georg\Desktop\wsl2\codeco-experiments\test-list\kube-burner\examples\workloads\kubelet-density-heavy\plugins\calico\calico-heavy_summary.csv',
#     "Cilium": r'C:\Users\georg\Desktop\wsl2\codeco-experiments\test-list\kube-burner\examples\workloads\kubelet-density-heavy\plugins\cilium\cilium-heavy_summary.csv',
#     "Flannel": r'C:\Users\georg\Desktop\wsl2\codeco-experiments\test-list\kube-burner\examples\workloads\kubelet-density-heavy\plugins\flannel\flannel-heavy_summary.csv',
#     "Kovn": r'C:\Users\georg\Desktop\wsl2\codeco-experiments\test-list\kube-burner\examples\workloads\kubelet-density-heavy\plugins\kovn\kovn-heavy_summary.csv',
#     "Krouter": r'C:\Users\georg\Desktop\wsl2\codeco-experiments\test-list\kube-burner\examples\workloads\kubelet-density-heavy\plugins\krouter\krouter-heavy_summary.csv',
#     "K3s Calico": r'C:\Users\georg\Desktop\wsl2\codeco-experiments\test-list\kube-burner\examples\workloads\kubelet-density-heavy\plugins\k3s-calico\k3s-calico-heavy_summary.csv',
#     "K3s Cilium": r'C:\Users\georg\Desktop\wsl2\codeco-experiments\test-list\kube-burner\examples\workloads\kubelet-density-heavy\plugins\k3s-cilium\k3s-cilium-heavy_summary.csv',
#     "K3s Flannel": r'C:\Users\georg\Desktop\wsl2\codeco-experiments\test-list\kube-burner\examples\workloads\kubelet-density-heavy\plugins\k3s-flannel\k3s-flannel-heavy_summary.csv',
#     "Mk8s Calico": r'C:\Users\georg\Desktop\wsl2\codeco-experiments\test-list\kube-burner\examples\workloads\kubelet-density-heavy\plugins\mk8s-calico\mk8s-calico-heavy_summary.csv',
#     "Mk8s Flannel": r'C:\Users\georg\Desktop\wsl2\codeco-experiments\test-list\kube-burner\examples\workloads\kubelet-density-heavy\plugins\mk8s-flannel\mk8s-flannel-heavy_summary.csv'
# }
#
# # Initialize a dictionary to store average values for each CNI
# cni_averages = {}
#
# # Process each file and extract the average values
# for cni_name, file_path in file_paths.items():
#     if os.path.exists(file_path):  # Check if the file exists
#         df = pd.read_csv(file_path)
#         cni_averages[cni_name] = extract_avg_values(df, patterns)
#     else:
#         print(f"File not found: {file_path}")
#
# # Plotting the results using bar charts
# fig, ax = plt.subplots(figsize=(14, 8))
#
# bar_width = 0.07  # Balanced width to make bars fit better
# spacing = 0.15  # Reduced spacing between groups
# index = np.arange(len(patterns)) * (len(cni_averages) * bar_width + spacing)
#
# # Plot each CNI's averages as bars with specified colors
# for i, (cni_name, averages) in enumerate(cni_averages.items()):
#     avg_values = list(averages.values())
#     ax.bar(index + i * bar_width, avg_values, bar_width, label=cni_name, color=color_map[cni_name])
#
# ax.set_xlabel('Configuration')
# ax.set_ylabel('Time (ms)')
# # ax.set_title('Average Values of Metrics Across Different Configurations')
# ax.set_xticks(index + bar_width * len(cni_averages) / 2)
# ax.set_xticklabels(patterns.values(), rotation=45, ha='right')
#
# # Move the legend to the right
# ax.legend(loc='center left', bbox_to_anchor=(1, 0.5))
#
# plt.tight_layout()
# plt.show()


############################################################################################################################
import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
import os

#####################
## MULTIPLE APPS / REPLICAS
#####################

# Define the patterns to match the desired metrics and their friendly names
# patterns = {
#     "kubelet-density-heavy_jobIterations1_qps1_burst1_postgres-deploy10_app10_postgres-service10": "qps-burst1-app10",
#     "kubelet-density-heavy_jobIterations1_qps1_burst1_postgres-deploy20_app20_postgres-service20": "qps-burst1-app20",
#     "kubelet-density-heavy_jobIterations1_qps1_burst1_postgres-deploy40_app40_postgres-service40": "qps-burst1-app40",
#     "kubelet-density-heavy_jobIterations1_qps1_burst1_postgres-deploy50_app50_postgres-service50": "qps-burst1-app50"
# }

patterns = {
    "kubelet-density-heavy_jobIterations1_qps10_burst10_postgres-deploy10_app10_postgres-service10": "qps-burst10-app10",
    "kubelet-density-heavy_jobIterations1_qps10_burst10_postgres-deploy20_app20_postgres-service20": "qps-burst10-app20",
    "kubelet-density-heavy_jobIterations1_qps10_burst10_postgres-deploy40_app40_postgres-service40": "qps-burst10-app40",
    "kubelet-density-heavy_jobIterations1_qps10_burst10_postgres-deploy50_app50_postgres-service50": "qps-burst10-app50"
}

# patterns = {
#     "kubelet-density-heavy_jobIterations1_qps25_burst25_postgres-deploy10_app10_postgres-service10": "qps-burst25-app10",
#     "kubelet-density-heavy_jobIterations1_qps25_burst25_postgres-deploy20_app20_postgres-service20": "qps-burst25-app20",
#     "kubelet-density-heavy_jobIterations1_qps25_burst25_postgres-deploy40_app40_postgres-service40": "qps-burst25-app40",
#     "kubelet-density-heavy_jobIterations1_qps25_burst25_postgres-deploy50_app50_postgres-service50": "qps-burst25-app50"
# }

# patterns = {
#     "kubelet-density-heavy_jobIterations1_qps50_burst50_postgres-deploy10_app10_postgres-service10": "qps-burst50-app10",
#     "kubelet-density-heavy_jobIterations1_qps50_burst50_postgres-deploy20_app20_postgres-service20": "qps-burst50-app20",
#     "kubelet-density-heavy_jobIterations1_qps50_burst50_postgres-deploy40_app40_postgres-service40": "qps-burst50-app40",
#     "kubelet-density-heavy_jobIterations1_qps50_burst50_postgres-deploy50_app50_postgres-service50": "qps-burst50-app50"
# }

# patterns = {
#     "kubelet-density-heavy_jobIterations1_qps75_burst75_postgres-deploy10_app10_postgres-service10": "qps-burst75-app10",
#     "kubelet-density-heavy_jobIterations1_qps75_burst75_postgres-deploy20_app20_postgres-service20": "qps-burst75-app20",
#     "kubelet-density-heavy_jobIterations1_qps75_burst75_postgres-deploy40_app40_postgres-service40": "qps-burst75-app40",
#     "kubelet-density-heavy_jobIterations1_qps75_burst75_postgres-deploy50_app50_postgres-service50": "qps-burst75-app50"
# }

# patterns = {
#     "kubelet-density-heavy_jobIterations1_qps100_burst100_postgres-deploy10_app10_postgres-service10": "qps-burst100-app10",
#     "kubelet-density-heavy_jobIterations1_qps100_burst100_postgres-deploy20_app20_postgres-service20": "qps-burst100-app20",
#     "kubelet-density-heavy_jobIterations1_qps100_burst100_postgres-deploy40_app40_postgres-service40": "qps-burst100-app40",
#     "kubelet-density-heavy_jobIterations1_qps100_burst100_postgres-deploy50_app50_postgres-service50": "qps-burst100-app50"
# }

# Define the color map for each CNI plugin
color_map = {
    "Antrea": "#17becf",   # Teal
    "Calico": "#1f77b4",   # Medium Blue
    "Cilium": "#2ca02c",   # Standard Green
    "Flannel": "#d62728",  # Standard Red
    "Kovn": "#9467bd",     # Purple
    "Krouter": "#8c564b",  # Brown
    "K3s Calico": "#aec7e8", # Light Blue
    "K3s Cilium": "#98df8a", # Light Green
    "K3s Flannel": "#ff7f7f", # Light Red
    "Mk8s Calico": "#0b559f", # Dark Blue
    "Mk8s Flannel": "#a71a1a", # Dark Red
    "Mk8s Cilium": "#207525" # Dark Green
}

# Function to filter and extract average values based on patterns
def extract_avg_values(df, patterns):
    result = {}
    for pattern, friendly_name in patterns.items():
        filtered_df = df[df['File'].str.contains(pattern)]
        avg_value = filtered_df['Avg'].mean() if not filtered_df.empty else None
        result[friendly_name] = avg_value
    return result

# File paths for each CNI plugin
file_paths = {
    "Antrea": r'C:\Users\georg\Desktop\wsl2\codeco-experiments\test-list\kube-burner\examples\workloads\kubelet-density-heavy\plugins\antrea\replicas\antrea-heavy-replicas_summary.csv',
    "Calico": r'C:\Users\georg\Desktop\wsl2\codeco-experiments\test-list\kube-burner\examples\workloads\kubelet-density-heavy\plugins\calico\replicas\calico-heavy-replicas_summary.csv',
    "Cilium": r'C:\Users\georg\Desktop\wsl2\codeco-experiments\test-list\kube-burner\examples\workloads\kubelet-density-heavy\plugins\cilium\replicas\cilium-heavy-replicas_summary.csv',
    "Flannel": r'C:\Users\georg\Desktop\wsl2\codeco-experiments\test-list\kube-burner\examples\workloads\kubelet-density-heavy\plugins\flannel\replicas\flannel-heavy-replicas_summary.csv',
    "Kovn": r'C:\Users\georg\Desktop\wsl2\codeco-experiments\test-list\kube-burner\examples\workloads\kubelet-density-heavy\plugins\kovn\replicas\kovn-heavy-replicas_summary.csv',
    "Krouter": r'C:\Users\georg\Desktop\wsl2\codeco-experiments\test-list\kube-burner\examples\workloads\kubelet-density-heavy\plugins\krouter\replicas\krouter-heavy-replicas_summary.csv',
    "K3s Calico": r'C:\Users\georg\Desktop\wsl2\codeco-experiments\test-list\kube-burner\examples\workloads\kubelet-density-heavy\plugins\k3s-calico\replicas\k3s-calico-heavy-replicas_summary.csv',
    "K3s Cilium": r'C:\Users\georg\Desktop\wsl2\codeco-experiments\test-list\kube-burner\examples\workloads\kubelet-density-heavy\plugins\k3s-cilium\replicas\k3s-cilium-heavy-replicas_summary.csv',
    "K3s Flannel": r'C:\Users\georg\Desktop\wsl2\codeco-experiments\test-list\kube-burner\examples\workloads\kubelet-density-heavy\plugins\k3s-flannel\replicas\k3s-flannel-heavy-replicas_summary.csv',
    "Mk8s Calico": r'C:\Users\georg\Desktop\wsl2\codeco-experiments\test-list\kube-burner\examples\workloads\kubelet-density-heavy\plugins\mk8s-calico\replicas\mk8s-calico-heavy-replicas_summary.csv',
    "Mk8s Flannel": r'C:\Users\georg\Desktop\wsl2\codeco-experiments\test-list\kube-burner\examples\workloads\kubelet-density-heavy\plugins\mk8s-flannel\replicas\mk8s-flannel-heavy-replicas_summary.csv'
}

# Initialize a dictionary to store average values for each CNI
cni_averages = {}

# Process each file and extract the average values
for cni_name, file_path in file_paths.items():
    if os.path.exists(file_path):  # Check if the file exists
        df = pd.read_csv(file_path)
        cni_averages[cni_name] = extract_avg_values(df, patterns)
    else:
        print(f"File not found: {file_path}")

# Plotting the results using bar charts
# fig, ax = plt.subplots(figsize=(14, 8))
fig, ax = plt.subplots(figsize=(8, 6))

bar_width = 0.03  # Balanced width to make bars fit better
spacing = 0.08  # Reduced spacing between groups
index = np.arange(len(patterns)) * (len(cni_averages) * bar_width + spacing)

# Plot each CNI's averages as bars with specified colors
for i, (cni_name, averages) in enumerate(cni_averages.items()):
    avg_values = list(averages.values())
    ax.bar(index + i * bar_width, avg_values, bar_width, label=cni_name, color=color_map[cni_name])

ax.set_xlabel('Configuration')
ax.set_ylabel('Time (ms)')
# ax.set_title('Average Values of Metrics Across Different Configurations')
ax.set_xticks(index + bar_width * len(cni_averages) / 2)
ax.set_xticklabels(patterns.values(), rotation=45, ha='right')

# Move the legend to the right
ax.legend(loc='center left', bbox_to_anchor=(1, 0.5))

plt.tight_layout()
plt.show()


