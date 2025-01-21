#!/bin/bash
response="$(aws eks list-clusters --region us-east-2 --output text | grep -i inadev-cluster 2>&1)" 
if [[ $? -eq 0 ]]; then
    echo "Success: inadev-cluster exist"
    aws eks --region us-east-2 update-kubeconfig --name inadev-cluster && export KUBE_CONFIG_PATH=~/.kube/config

else
    echo "Error: inadev-cluster does not exist"
fi
