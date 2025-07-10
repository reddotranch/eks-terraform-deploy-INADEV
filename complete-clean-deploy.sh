#!/bin/bash

set -e

echo "🧹 Performing COMPLETE infrastructure cleanup..."

# Remove ALL state files and locks
echo "Removing local state files..."
rm -f terraform.tfstate*
rm -rf .terraform/
rm -f .terraform.lock.hcl
rm -rf stage2-kubernetes/.terraform/
rm -f stage2-kubernetes/terraform.tfstate*
rm -f stage2-kubernetes/.terraform.lock.hcl
rm -f stage2-kubernetes/terraform.tfvars

# Clear remote state and locks
echo "Clearing remote state from S3..."
aws s3 rm s3://west-betech-tfstate/infra/terraformstatefile 2>/dev/null || true
aws s3 rm s3://west-betech-tfstate/infra/stage2/terraformstatefile 2>/dev/null || true

echo "Clearing DynamoDB locks..."
aws dynamodb delete-item \
    --table-name terraform-state-lock-table \
    --key '{"LockID":{"S":"west-betech-tfstate/infra/terraformstatefile-md5"}}' \
    --region us-west-2 2>/dev/null || true

aws dynamodb delete-item \
    --table-name terraform-state-lock-table \
    --key '{"LockID":{"S":"west-betech-tfstate/infra/stage2/terraformstatefile-md5"}}' \
    --region us-west-2 2>/dev/null || true

# Force unlock if any locks remain
echo "Force unlocking any remaining locks..."
terraform force-unlock -force $(aws dynamodb scan --table-name terraform-state-lock-table --region us-west-2 --query 'Items[?contains(LockID.S, `infra/terraformstatefile`)].LockID.S' --output text 2>/dev/null || echo "") 2>/dev/null || true

# Clean start
echo "🚀 Starting completely fresh terraform initialization..."
terraform init -reconfigure

echo "📋 Planning deployment..."
terraform plan

echo "🎯 Stage 1: Deploying core infrastructure (VPC + EKS)..."
terraform apply -target=module.vpc -target=module.eks -auto-approve

echo "⚙️  Stage 2: Configuring kubectl..."
aws eks update-kubeconfig --region us-west-2 --name betech-cluster

echo "🔍 Verifying cluster connectivity..."
kubectl get nodes

echo "📊 Getting values for stage 2..."
VPC_ID=$(terraform output -raw vpc_id)
CLUSTER_NAME=$(terraform output -raw cluster_name)
MAIN_REGION=$(terraform output -raw main_region)
OIDC_ARN=$(terraform output -raw oidc_provider_arn)

echo "🎯 Stage 3: Deploying Kubernetes resources and ALB Controller..."
cd stage2-kubernetes

# Create terraform.tfvars for stage 2
cat > terraform.tfvars <<EOF
main-region = "$MAIN_REGION"
env_name = "betech"
cluster_name = "$CLUSTER_NAME"
vpc_id = "$VPC_ID"
rolearn = "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/terraform-poweruser"
EOF

terraform init
terraform plan
terraform apply -auto-approve

cd ..

echo "🎯 Stage 4: Applying any remaining resources..."
terraform apply -auto-approve

echo "🎉 Complete fresh deployment successful!"
echo "📊 Infrastructure Summary:"
echo "🔗 Cluster: betech-cluster"
echo "🌍 Region: us-west-2"
echo "📋 Nodes:"
kubectl get nodes --no-headers | wc -l | xargs echo "   Node count:"
