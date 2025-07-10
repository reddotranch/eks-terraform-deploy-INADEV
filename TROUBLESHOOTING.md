# EKS Terraform Deployment Troubleshooting

## Issue: Circular Dependency Error

The circular dependency error occurs when Terraform modules reference each other in a way that creates a dependency loop.

## Root Cause
- The EKS module was trying to manage the aws-auth configmap using the Kubernetes provider
- The Kubernetes provider needed the EKS cluster to be created first
- This created a circular dependency: EKS module → Kubernetes provider → EKS module

## Solutions Applied

### 1. Fixed Provider Configuration
- Updated `providers.tf` to use `exec` authentication instead of data sources
- Used `try()` functions to handle cases when cluster doesn't exist yet
- Removed circular dependency by avoiding data source references

### 2. Separated aws-auth ConfigMap Management
- Disabled `manage_aws_auth_configmap` in the EKS module
- Moved aws-auth configmap to separate `kubernetes.tf` file
- Added explicit dependencies to ensure proper ordering

### 3. Fixed Helm Release Syntax
- Corrected the `set` blocks in the ALB controller to use proper Terraform syntax

### 4. Enhanced Deployment Script
- Created `deploy.sh` script for staged deployment
- Deploys infrastructure in the correct order with proper waiting

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

# Step 3: Deploy Kubernetes resources
terraform apply -target=kubernetes_namespace.gateway -target=kubernetes_namespace.directory -target=kubernetes_namespace.analytics -target=kubernetes_config_map_v1_data.aws_auth -auto-approve

# Step 4: Deploy ALB Controller
terraform apply -target=module.aws_alb_controller -auto-approve

# Step 5: Apply remaining resources
terraform apply -auto-approve
```

## Key Changes Made

1. **providers.tf**: Switched to exec-based authentication
2. **modules/eks-cluster/main.tf**: Disabled aws-auth configmap management
3. **kubernetes.tf**: Added separate aws-auth configmap resource
4. **modules/aws-alb-controller/main.tf**: Fixed helm release syntax
5. **deploy.sh**: Enhanced deployment script with proper staging

## Prevention
- Always separate Kubernetes resource management from cluster creation
- Use exec authentication for providers when possible
- Implement staged deployments for complex infrastructure
