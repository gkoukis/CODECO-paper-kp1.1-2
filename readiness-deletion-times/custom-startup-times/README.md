## Pod Startup Times (this uses the default k8s scheduler)

# Usage 
./pod_startup_times_script.sh <plugin> <num_iterations> <sleep_between_iterations> <num_pods_values>
e.g., 
./pod_startup_times_script.sh uc1 11 60 '1 10 20 40 60 80'

# Description
This is a script that deploys a user-defined batch of pods (with a "pause" image) and measures the time taken for pods to be in a Ready state

# Note 
-Please make sure to change the name of the node in which you want to deploy the batch of pods in the 'nodeSelector' (line 86) or remove it if you want to deploy the pods in all nodes
-Please make sure the number of pods (less than 100) in case you want to deploy them all in one worker node
-In case of issues with the pods you can delete them with the delete_pods_final.sh script

## Pod Startup Times (use SWM)

TBA
