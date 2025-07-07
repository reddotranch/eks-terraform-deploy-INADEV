#!/bin/bash
response="$(aws eks list-clusters --region us-west-2 --output text | grep -i betech-cluster 2>&1)" 
if [[ $? -eq 0 ]]; then
    echo "Success: betech-cluster exist"
    aws eks --region us-west-2 update-kubeconfig --name betech-cluster && export KUBE_CONFIG_PATH=~/.kube/config

else
    echo "Error: betech-cluster does not exist"
fi
