#!/bin/bash

set -e

echo "🔄 Starting fresh EKS deployment..."

# Backup current state (optional)
if [ -f "terraform.tfstate" ]; then
    echo "📁 Backing up current state file..."
    cp terraform.tfstate terraform.tfstate.backup.$(date +%Y%m%d_%H%M%S)
fi

# Remove ALL state and cache for both main and stage2
echo "🧹 Performing complete cleanup..."
rm -f terraform.tfstate*
rm -rf .terraform/
rm -f .terraform.lock.hcl
rm -rf stage2-kubernetes/.terraform/
rm -f stage2-kubernetes/terraform.tfstate*
rm -f stage2-kubernetes/.terraform.lock.hcl
rm -f stage2-kubernetes/terraform.tfvars

# Initialize completely fresh
echo "🚀 Initializing completely fresh Terraform..."
terraform init

# Deploy in stages
echo "📋 Planning deployment..."
terraform plan

echo "🎯 Starting staged deployment..."

# Stage 1: Core infrastructure (VPC + EKS)
echo "🏗️  Stage 1: Deploying VPC and EKS cluster..."
terraform apply -target=module.vpc -target=module.eks -auto-approve

# Stage 2: Configure kubectl
echo "⚙️  Stage 2: Configuring kubectl..."
CLUSTER_NAME=$(terraform output -raw cluster_name)
REGION=$(terraform output -raw main_region)
VPC_ID=$(terraform output -raw vpc_id)
OIDC_ARN=$(terraform output -raw oidc_provider_arn)

aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME

echo "🔍 Verifying cluster connectivity..."
kubectl get nodes

# Stage 3: Deploy Kubernetes resources and ALB Controller
echo "🎯 Stage 3: Deploying Kubernetes resources and ALB Controller..."
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

# Stage 4: Everything else
echo "🔧 Stage 4: Applying any remaining resources..."
terraform apply -auto-approve

echo "✅ Fresh deployment completed successfully!"
echo "🔗 Cluster: $CLUSTER_NAME"
echo "🌍 Region: $REGION"
echo "📊 Infrastructure Summary:"
kubectl get nodes --no-headers | wc -l | xargs echo "   Node count:"
