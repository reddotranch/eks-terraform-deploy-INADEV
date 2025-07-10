#!/bin/bash

set -e

echo "🚀 Starting EKS deployment process..."

# Step 1: Initialize Terraform
echo "📋 Step 1: Initializing Terraform..."
terraform init

# Step 2: Deploy VPC and EKS Cluster (stage 1)
echo "🎯 Step 2: Deploying VPC and EKS cluster (Stage 1)..."
terraform plan -target=module.vpc -target=module.eks
terraform apply -target=module.vpc -target=module.eks -auto-approve

# Step 3: Update kubeconfig to connect to the new cluster
echo "⚙️  Step 3: Updating kubeconfig..."
CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "betech-cluster")
REGION=$(terraform output -raw main_region 2>/dev/null || echo "us-west-2")
VPC_ID=$(terraform output -raw vpc_id)
OIDC_ARN=$(terraform output -raw oidc_provider_arn)

aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME

# Step 4: Wait for cluster to be fully ready
echo "⏳ Step 4: Waiting for cluster nodes to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=600s || echo "Nodes may still be starting up, continuing..."

# Step 5: Deploy Kubernetes resources (stage 2)
echo "🎯 Step 5: Deploying Kubernetes resources and ALB Controller (Stage 2)..."
cd stage2-kubernetes

# Create terraform.tfvars for stage 2
cat > terraform.tfvars <<EOF
main-region = "$REGION"
env_name = "betech"
cluster_name = "$CLUSTER_NAME"
vpc_id = "$VPC_ID"
rolearn = "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/terraform-poweruser"
EOF

terraform init
terraform plan
terraform apply -auto-approve

cd ..

# Step 6: Apply any remaining resources in main configuration
echo "🔧 Step 6: Applying any remaining resources..."
terraform apply -auto-approve

echo "✅ Deployment completed successfully!"
echo "🔗 Cluster Name: $CLUSTER_NAME"
echo "🌍 Region: $REGION"
echo "📝 To connect: aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME"
