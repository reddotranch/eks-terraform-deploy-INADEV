# EKS Terraform Deployment Troubleshooting

## Issue: Connection Refused Error

The error you're experiencing occurs because Terraform is trying to connect to the Kubernetes cluster before it's fully provisioned and accessible.

## Root Cause
- The AWS Load Balancer Controller module is trying to deploy Kubernetes resources before the EKS cluster is ready
- The Kubernetes provider is configured to use module outputs that aren't available during the initial run

## Solutions Applied

### 1. Fixed Provider Configuration
- Updated `providers.tf` to use data sources instead of module outputs
- Added proper dependencies with `depends_on`
- Simplified provider configuration to use token-based authentication

### 2. Added Dependencies
- Added `depends_on = [module.eks]` to the ALB controller module in `main.tf`
- Added explicit dependencies in the ALB controller module

### 3. Created Deployment Script
- Created `deploy.sh` script for staged deployment
- Deploys infrastructure in the correct order

## Deployment Options

### Option 1: Use the Deployment Script (Recommended)
```bash
cd /home/ubuntu/EKS-PROJECT-BETECH-2025/eks-terraform-deploy-BETECH
./deploy.sh
```

### Option 2: Manual Staged Deployment
```bash
# Step 1: Deploy VPC and EKS
terraform init
terraform apply -target=module.vpc -target=module.eks -auto-approve

# Step 2: Update kubeconfig
aws eks update-kubeconfig --region us-west-2 --name betech-cluster

# Step 3: Deploy ALB Controller
terraform apply -target=module.aws_alb_controller -auto-approve

# Step 4: Apply remaining resources
terraform apply -auto-approve
```

### Option 3: If Still Facing Issues
If you continue to have connection issues, you may need to:

1. Ensure AWS CLI is properly configured:
```bash
aws sts get-caller-identity
aws eks describe-cluster --name betech-cluster --region us-west-2
```

2. Check if kubectl can connect:
```bash
kubectl get nodes
kubectl get namespaces
```

3. Verify the cluster endpoint is accessible:
```bash
terraform output cluster_endpoint
```

## Prevention
- Always use staged deployments for EKS with Kubernetes resources
- Use data sources instead of module outputs in provider configuration
- Add proper dependencies between modules
