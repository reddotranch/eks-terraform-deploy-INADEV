#!/bin/bash

set -e

# Enhanced manifest application script with better error handling
# This script applies Kubernetes manifests with proper namespace verification
# 
# NOTE: ALB Controller Subnet Auto-Discovery
# The AWS Load Balancer Controller automatically discovers subnets based on tags:
# - Public subnets should have tag: kubernetes.io/role/elb = 1
# - Private subnets should have tag: kubernetes.io/role/internal-elb = 1
# This eliminates the need for hardcoded subnet IDs in ingress annotations.

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

print_header "🚀 Applying Kubernetes manifests with namespace verification..."

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check required tools
print_status "Checking required tools..."
if ! command_exists kubectl; then
    print_error "kubectl is not installed!"
    exit 1
fi

if ! command_exists aws; then
    print_error "aws CLI is not installed!"
    exit 1
fi

# Function to get cluster info with fallbacks
get_cluster_info() {
    # Try to get from terraform outputs first
    if [ -f "terraform.tfstate" ] && terraform output cluster_name >/dev/null 2>&1; then
        CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "betech-cluster")
        REGION=$(terraform output -raw main_region 2>/dev/null || echo "us-west-2")
    else
        print_warning "Terraform outputs not available, using defaults"
        CLUSTER_NAME="betech-cluster"
        REGION="us-west-2"
    fi
    
    print_status "Using cluster: $CLUSTER_NAME in region: $REGION"
}

# Get cluster information
get_cluster_info

# Check if manifest directory exists
print_header "📁 Checking manifest directory..."
MANIFEST_DIRS=("manifest" "manifests" "../weatherappPYTHON-BETECH/manifest")

MANIFEST_DIR=""
for dir in "${MANIFEST_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        MANIFEST_DIR="$dir"
        print_status "Found manifest directory: $MANIFEST_DIR"
        break
    fi
done

if [ -z "$MANIFEST_DIR" ]; then
    print_error "Manifest directory not found!"
    print_status "Checked locations: ${MANIFEST_DIRS[*]}"
    print_status "💡 Make sure you're in the correct directory or the manifest folder exists"
    exit 1
fi

# Verify cluster connectivity
print_header "🔍 Verifying cluster connectivity..."
if ! kubectl cluster-info >/dev/null 2>&1; then
    print_warning "Cannot connect to Kubernetes cluster!"
    print_status "Attempting to update kubeconfig..."
    
    if aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"; then
        print_status "Kubeconfig updated successfully"
        if ! kubectl cluster-info >/dev/null 2>&1; then
            print_error "Still cannot connect to cluster after kubeconfig update!"
            exit 1
        fi
    else
        print_error "Failed to update kubeconfig!"
        print_status "💡 Manual command: aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME"
        exit 1
    fi
fi

print_status "✅ Connected to cluster: $(kubectl config current-context)"

# Verify cluster nodes are ready
print_status "Checking cluster node status..."
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep " Ready " | wc -l)

print_status "Cluster has $NODE_COUNT nodes, $READY_NODES ready"

if [ "$READY_NODES" -eq 0 ]; then
    print_warning "No nodes are ready! The cluster may still be initializing"
    print_status "Continuing anyway, but deployments may fail..."
fi

# Verify and create required namespaces
print_header "🔍 Verifying and creating required namespaces..."
REQUIRED_NAMESPACES=("directory" "gateway" "analytics")

for ns in "${REQUIRED_NAMESPACES[@]}"; do
    if kubectl get namespace "$ns" >/dev/null 2>&1; then
        print_status "✅ Namespace '$ns' exists"
    else
        print_status "🆕 Creating namespace '$ns'..."
        if kubectl create namespace "$ns"; then
            print_status "✅ Created namespace '$ns'"
        else
            print_warning "Failed to create namespace '$ns', it might already exist"
        fi
    fi
done

# Function to apply a manifest file with error handling
apply_manifest() {
    local file="$1"
    local filename=$(basename "$file")
    
    if [ -f "$file" ]; then
        print_status "📦 Applying $filename..."
        if kubectl apply -f "$file"; then
            print_status "✅ Successfully applied $filename"
        else
            print_warning "❌ Failed to apply $filename"
            return 1
        fi
    else
        print_warning "⚠️  File $filename not found, skipping..."
        return 1
    fi
}

# Apply specific manifest files in order
print_header "📦 Applying individual manifest files..."

# Find all YAML files in the manifest directory
MANIFEST_FILES=($(find "$MANIFEST_DIR" -name "*.yaml" -o -name "*.yml" | sort))

if [ ${#MANIFEST_FILES[@]} -eq 0 ]; then
    print_warning "No YAML manifest files found in $MANIFEST_DIR"
    exit 1
fi

print_status "Found ${#MANIFEST_FILES[@]} manifest files to apply"

APPLIED_COUNT=0
FAILED_COUNT=0

# Apply deployment first if it exists, then service, then ingress, then others
PRIORITY_ORDER=("deployment" "service" "ingress")
REMAINING_FILES=()

# Apply priority files first
for priority in "${PRIORITY_ORDER[@]}"; do
    for manifest_file in "${MANIFEST_FILES[@]}"; do
        if [[ "$(basename "$manifest_file")" == *"$priority"* ]]; then
            if apply_manifest "$manifest_file"; then
                ((APPLIED_COUNT++))
            else
                ((FAILED_COUNT++))
            fi
        else
            # Add to remaining files if not a priority file
            if [[ ! " ${REMAINING_FILES[@]} " =~ " ${manifest_file} " ]]; then
                REMAINING_FILES+=("$manifest_file")
            fi
        fi
    done
done

# Apply remaining files
for manifest_file in "${REMAINING_FILES[@]}"; do
    # Skip if already applied (check if it's a priority file)
    is_priority=false
    for priority in "${PRIORITY_ORDER[@]}"; do
        if [[ "$(basename "$manifest_file")" == *"$priority"* ]]; then
            is_priority=true
            break
        fi
    done
    
    if [ "$is_priority" = false ]; then
        if apply_manifest "$manifest_file"; then
            ((APPLIED_COUNT++))
        else
            ((FAILED_COUNT++))
        fi
    fi
done

# Apply all remaining manifests in the directory
print_header "📦 Applying all manifests in $MANIFEST_DIR/ directory..."
TOTAL_FILES=$(find "$MANIFEST_DIR" -name "*.yaml" -o -name "*.yml" | wc -l)

if [ "$TOTAL_FILES" -gt 0 ]; then
    print_status "Found $TOTAL_FILES YAML files in $MANIFEST_DIR"
    
    if kubectl apply -f "$MANIFEST_DIR/" 2>/dev/null; then
        print_status "✅ Successfully applied all manifests"
    else
        print_warning "⚠️  Some manifests may have failed, applying individually..."
        
        # Apply each file individually for better error reporting
        for file in "$MANIFEST_DIR"/*.{yaml,yml}; do
            if [ -f "$file" ]; then
                filename=$(basename "$file")
                print_status "   Applying $filename..."
                if ! kubectl apply -f "$file"; then
                    print_warning "   ❌ Failed: $filename"
                fi
            fi
        done
    fi
else
    print_warning "No YAML files found in $MANIFEST_DIR"
fi

echo "🔍 Verification..."
echo "📋 Namespaces:"
kubectl get namespaces | grep -E "(directory|gateway|analytics)"

echo "📋 Deployments:"
kubectl get deployments -A | grep -E "(directory|gateway|analytics)" || echo "No deployments found yet"

echo "📋 Services:"
kubectl get services -A | grep -E "(directory|gateway|analytics)" || echo "No services found yet"

echo "📋 Ingresses:"
kubectl get ingress -A | grep -E "(directory|gateway|analytics)" || echo "No ingresses found yet"

echo "✅ Manifest application completed!"
echo "💡 If there were any errors, check the individual manifest files and try applying them manually:"
echo "   kubectl apply -f manifest/deployment.yaml"
echo "   kubectl apply -f manifest/service.yaml" 
echo "   kubectl apply -f manifest/ingress.yaml"
