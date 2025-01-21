#!/bin/bash
response="$(aws eks list-clusters --region us-east-2 --output text | grep -i tdw-cluster 2>&1)" 
if [[ $? -eq 0 ]]; then
    echo "Success: TDW-cluster exist"
    aws eks --region us-east-2 update-kubeconfig --name tdw-cluster && export KUBE_CONFIG_PATH=~/.kube/config

else
    echo "Error: TDW-cluster does not exist"
fi