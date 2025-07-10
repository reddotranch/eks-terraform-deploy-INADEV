#!/bin/bash

echo "🔧 Quick fix for Helm/Kubernetes connectivity issue..."

# Ensure we're in the right directory
cd /home/ubuntu/EKS-PROJECT-BETECH-2025/eks-terraform-deploy-BETECH

# Update kubeconfig
echo "📋 Updating kubeconfig..."
aws eks update-kubeconfig --region us-west-2 --name betech-cluster

# Verify kubectl connectivity
echo "🔍 Verifying kubectl connectivity..."
kubectl config current-context
kubectl get nodes
kubectl cluster-info

# Set environment variables for Terraform
export KUBE_CONFIG_PATH=$HOME/.kube/config
export KUBECONFIG=$HOME/.kube/config

echo "⚙️  Environment variables set:"
echo "KUBE_CONFIG_PATH=$KUBE_CONFIG_PATH"
echo "KUBECONFIG=$KUBECONFIG"

# Go to stage2 and retry
echo "🎯 Retrying stage2 deployment..."
cd stage2-kubernetes

# Verify terraform.tfvars exists
if [ ! -f terraform.tfvars ]; then
    echo "❌ terraform.tfvars not found. Creating it..."
    
    # Get values from main terraform
    cd ..
    VPC_ID=$(terraform output -raw vpc_id)
    CLUSTER_NAME=$(terraform output -raw cluster_name)
    MAIN_REGION=$(terraform output -raw main_region)
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    cd stage2-kubernetes
    cat > terraform.tfvars <<EOF
main-region = "$MAIN_REGION"
env_name = "betech"
cluster_name = "$CLUSTER_NAME"
vpc_id = "$VPC_ID"
rolearn = "arn:aws:iam::$ACCOUNT_ID:role/betech-west"
EOF
    echo "✅ terraform.tfvars created"
fi

echo "🔄 Re-initializing terraform in stage2..."
terraform init

echo "📋 Planning stage2 deployment..."
terraform plan

echo "🚀 Applying stage2 deployment..."
terraform apply -auto-approve

echo "✅ Stage2 deployment completed!"

cd ..
echo "🎯 Applying any remaining resources in main..."
terraform apply -auto-approve

echo "🎉 Deployment fix completed successfully!"
