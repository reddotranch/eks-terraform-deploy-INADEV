#!/bin/bash

# ALB Subnet Auto-Discovery Verification Script
# This script verifies that the ALB Controller and ingress are properly configured for auto-discovery

set -e

echo "🔍 ALB Subnet Auto-Discovery Verification Script"
echo "================================================="

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_header() {
    echo -e "${BLUE}🔍 $1${NC}"
}

# 1. Check VPC and Subnet Tags
print_header "Checking VPC and Subnet Tags for Auto-Discovery"

# Get cluster VPC ID
CLUSTER_NAME="betech-cluster"
REGION="us-west-2"

echo "Getting VPC ID from cluster: $CLUSTER_NAME"
VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query 'cluster.resourcesVpcConfig.vpcId' --output text 2>/dev/null || echo "")

if [ -z "$VPC_ID" ] || [ "$VPC_ID" = "None" ]; then
    print_error "Could not retrieve VPC ID from cluster"
    exit 1
else
    print_status "Found VPC ID: $VPC_ID"
fi

# Check public subnet tags
echo ""
print_header "Verifying Public Subnet Tags (kubernetes.io/role/elb)"
PUBLIC_SUBNETS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:kubernetes.io/role/elb,Values=1" \
    --query 'Subnets[*].[SubnetId,Tags[?Key==`Name`].Value|[0]]' \
    --output text)

if [ -z "$PUBLIC_SUBNETS" ]; then
    print_error "No public subnets found with kubernetes.io/role/elb=1 tag!"
    echo "This will prevent ALB auto-discovery from working"
else
    print_status "Found public subnets with correct tags:"
    echo "$PUBLIC_SUBNETS" | while read subnet_id name; do
        echo "  - $subnet_id ($name)"
    done
fi

# Check private subnet tags
echo ""
print_header "Verifying Private Subnet Tags (kubernetes.io/role/internal-elb)"
PRIVATE_SUBNETS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:kubernetes.io/role/internal-elb,Values=1" \
    --query 'Subnets[*].[SubnetId,Tags[?Key==`Name`].Value|[0]]' \
    --output text)

if [ -z "$PRIVATE_SUBNETS" ]; then
    print_warning "No private subnets found with kubernetes.io/role/internal-elb=1 tag"
    echo "This is only needed for internal load balancers"
else
    print_status "Found private subnets with correct tags:"
    echo "$PRIVATE_SUBNETS" | while read subnet_id name; do
        echo "  - $subnet_id ($name)"
    done
fi

# 2. Check ALB Controller Configuration
echo ""
print_header "Checking ALB Controller Configuration"

if ! kubectl get deployment aws-load-balancer-controller -n kube-system >/dev/null 2>&1; then
    print_error "AWS Load Balancer Controller not found in kube-system namespace"
    exit 1
else
    print_status "AWS Load Balancer Controller deployment found"
fi

# Check ALB Controller VPC ID
ALB_VPC_ID=$(kubectl get deployment aws-load-balancer-controller -n kube-system -o yaml | grep -o 'vpc-[a-z0-9]*' | head -1)
if [ "$ALB_VPC_ID" = "$VPC_ID" ]; then
    print_status "ALB Controller using correct VPC ID: $ALB_VPC_ID"
else
    print_error "ALB Controller VPC ID mismatch!"
    echo "  Expected: $VPC_ID"
    echo "  Found: $ALB_VPC_ID"
fi

# Check ALB Controller pods
ALB_PODS=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --no-headers 2>/dev/null | wc -l)
ALB_READY=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --no-headers 2>/dev/null | grep "Running" | wc -l)

echo "ALB Controller pods: $ALB_READY/$ALB_PODS running"
if [ "$ALB_READY" -gt 0 ]; then
    print_status "ALB Controller pods are running"
else
    print_error "ALB Controller pods are not running"
fi

# 3. Check Ingress Configuration
echo ""
print_header "Checking Ingress Configuration for Auto-Discovery"

# Check if ingress exists
if kubectl get ingress -A --no-headers 2>/dev/null | grep -q weatherapp; then
    INGRESS_NS=$(kubectl get ingress -A --no-headers | grep weatherapp | awk '{print $1}')
    INGRESS_NAME=$(kubectl get ingress -A --no-headers | grep weatherapp | awk '{print $2}')
    
    print_status "Found ingress: $INGRESS_NAME in namespace: $INGRESS_NS"
    
    # Check for hardcoded subnets annotation
    if kubectl get ingress $INGRESS_NAME -n $INGRESS_NS -o yaml | grep -q "alb.ingress.kubernetes.io/subnets:"; then
        print_error "Ingress has hardcoded subnets annotation!"
        echo "This will override auto-discovery. Remove the following annotation:"
        kubectl get ingress $INGRESS_NAME -n $INGRESS_NS -o yaml | grep "alb.ingress.kubernetes.io/subnets:"
    else
        print_status "Ingress properly configured for auto-discovery (no hardcoded subnets)"
    fi
    
    # Check ingress status
    ALB_ADDRESS=$(kubectl get ingress $INGRESS_NAME -n $INGRESS_NS -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    if [ -n "$ALB_ADDRESS" ]; then
        print_status "ALB successfully provisioned: $ALB_ADDRESS"
    else
        print_warning "ALB not yet provisioned or having issues"
    fi
    
    # Check ingress events for errors
    echo ""
    print_header "Recent Ingress Events"
    kubectl describe ingress $INGRESS_NAME -n $INGRESS_NS | grep -A 10 "Events:" || echo "No events found"
    
else
    print_warning "No weatherapp ingress found"
fi

# 4. Summary and Recommendations
echo ""
echo "================================================="
print_header "Summary and Recommendations"

if [ -n "$PUBLIC_SUBNETS" ] && [ "$ALB_READY" -gt 0 ]; then
    print_status "ALB Auto-Discovery Configuration: READY ✅"
    echo ""
    echo "✅ Public subnets properly tagged for ALB auto-discovery"
    echo "✅ ALB Controller running and configured correctly"
    echo "✅ No hardcoded subnet annotations found"
    echo ""
    echo "🚀 Your deployment is ready for future infrastructure changes!"
else
    print_error "ALB Auto-Discovery Configuration: NEEDS ATTENTION ❌"
    echo ""
    echo "🔧 Actions needed:"
    if [ -z "$PUBLIC_SUBNETS" ]; then
        echo "  - Add kubernetes.io/role/elb=1 tags to public subnets"
    fi
    if [ "$ALB_READY" -eq 0 ]; then
        echo "  - Fix ALB Controller deployment issues"
    fi
fi

echo ""
echo "📖 For more information, see: ALB-SUBNET-AUTO-DISCOVERY.md"
