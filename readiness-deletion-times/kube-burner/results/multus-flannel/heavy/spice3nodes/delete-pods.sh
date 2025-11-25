#!/bin/bash

# Specific pod range
start=0
end=24
namespace="kubelet-density-heavy"

for i in $(seq $start $end); do
    pod_name="curl-1-$i-*"
    echo "Attempting to delete pod: $pod_name"

    # Force delete the pod
    kubectl delete pod $pod_name -n $namespace --grace-period=0 --force

    # Wait for a moment to allow command to send
    sleep 2

    # Check if the pod still exists and attempt to remove finalizers if necessary
    if kubectl get pod $pod_name &> /dev/null; then
        echo "Pod $pod_name still exists, attempting to remove finalizers..."
        kubectl patch pod $pod_name --type=json -p='[{"op": "remove", "path": "/metadata/finalizers"}]'
    fi

    echo "Pod $pod_name handled."
done

echo "All specified pods have been processed."