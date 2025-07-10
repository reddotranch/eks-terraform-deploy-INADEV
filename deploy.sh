#!/bin/bash

set -e

echo "Starting EKS deployment process..."

# Step 1: Deploy VPC and EKS Cluster first
echo "Step 1: Deploying VPC and EKS cluster..."
terraform init
terraform plan -target=module.vpc -target=module.eks
terraform apply -target=module.vpc -target=module.eks -auto-approve

# Step 2: Update kubeconfig to connect to the new cluster
echo "Step 2: Updating kubeconfig..."
aws eks update-kubeconfig --region $(terraform output -raw main_region || echo "us-west-2") --name $(terraform output -raw cluster_name || echo "betech-cluster")

# Step 3: Wait for cluster to be fully ready
echo "Step 3: Waiting for cluster to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s

# Step 4: Deploy ALB Controller
echo "Step 4: Deploying AWS Load Balancer Controller..."
terraform plan -target=module.aws_alb_controller
terraform apply -target=module.aws_alb_controller -auto-approve

# Step 5: Apply any remaining resources
echo "Step 5: Applying any remaining resources..."
terraform plan
terraform apply -auto-approve

echo "Deployment completed successfully!"
