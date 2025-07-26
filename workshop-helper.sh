#!/bin/bash

# Weather App Workshop Helper Script
# This script provides utilities for the workshop exercises

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}🎯 $1${NC}"
    echo -e "${BLUE}================================${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${PURPLE}ℹ️  $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Workshop Prerequisites"
    
    # Check kubectl
    if command -v kubectl >/dev/null 2>&1; then
        print_success "kubectl is installed"
        kubectl version --client --short
    else
        print_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check AWS CLI
    if command -v aws >/dev/null 2>&1; then
        print_success "AWS CLI is installed"
        aws --version
    else
        print_error "AWS CLI is not installed or not in PATH"
        exit 1
    fi
    
    # Check cluster connectivity
    if kubectl cluster-info >/dev/null 2>&1; then
        print_success "Connected to Kubernetes cluster"
        echo "Current context: $(kubectl config current-context)"
    else
        print_error "Cannot connect to Kubernetes cluster"
        print_info "Run: aws eks update-kubeconfig --region us-west-2 --name betech-cluster"
        exit 1
    fi
    
    # Check if weather app is deployed
    if kubectl get deployment weatherapp -n directory >/dev/null 2>&1; then
        print_success "Weather app deployment found"
        kubectl get deployment weatherapp -n directory
    else
        print_error "Weather app deployment not found in 'directory' namespace"
        print_info "Make sure the weather app is deployed first"
        exit 1
    fi
    
    echo ""
    print_success "All prerequisites met! Ready for workshop exercises."
    echo ""
}

# Workshop status dashboard
show_status() {
    print_header "Current Workshop Status"
    
    echo -e "${YELLOW}📊 Deployment Status:${NC}"
    kubectl get deployment weatherapp -n directory
    echo ""
    
    echo -e "${YELLOW}🏃 Pod Status:${NC}"
    kubectl get pods -n directory -l app=weatherapp
    echo ""
    
    echo -e "${YELLOW}🖥️  Node Status:${NC}"
    kubectl get nodes
    echo ""
    
    echo -e "${YELLOW}🌐 Service & Ingress:${NC}"
    kubectl get svc,ingress -n directory
    echo ""
    
    # Check HPA if exists
    if kubectl get hpa weatherapp -n directory >/dev/null 2>&1; then
        echo -e "${YELLOW}📈 HPA Status:${NC}"
        kubectl get hpa weatherapp -n directory
        echo ""
    fi
    
    # Get ALB endpoint
    ALB_ENDPOINT=$(kubectl get ingress weatherapp-ingress -n directory -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "Not available")
    echo -e "${YELLOW}🔗 Application URL:${NC} http://$ALB_ENDPOINT"
    echo ""
}

# Quick exercise functions
exercise_1_scaling() {
    print_header "Exercise 1: Manual Pod Scaling"
    
    echo "Current replicas:"
    kubectl get deployment weatherapp -n directory -o jsonpath='{.spec.replicas}'
    echo ""
    
    read -p "Enter desired number of replicas (1-10): " replicas
    
    if [[ "$replicas" =~ ^[1-9]$|^10$ ]]; then
        echo "Scaling to $replicas replicas..."
        kubectl scale deployment weatherapp --replicas=$replicas -n directory
        
        echo "Watching scaling progress (Ctrl+C to stop):"
        kubectl get pods -n directory -l app=weatherapp -w
    else
        print_error "Invalid input. Please enter a number between 1 and 10."
    fi
}

exercise_2_node_scaling() {
    print_header "Exercise 2: Node Group Scaling"
    
    NODE_GROUP=$(aws eks list-nodegroups --cluster-name betech-cluster --query 'nodegroups[0]' --output text --region us-west-2)
    
    echo "Current node group: $NODE_GROUP"
    echo "Current nodes:"
    kubectl get nodes --no-headers | wc -l
    echo ""
    
    read -p "Enter desired number of nodes (1-6): " nodes
    
    if [[ "$nodes" =~ ^[1-6]$ ]]; then
        echo "Scaling node group to $nodes nodes..."
        aws eks update-nodegroup-config \
            --cluster-name betech-cluster \
            --nodegroup-name $NODE_GROUP \
            --scaling-config minSize=1,maxSize=6,desiredSize=$nodes \
            --region us-west-2
        
        echo "Node scaling initiated. Monitor with: watch 'kubectl get nodes'"
    else
        print_error "Invalid input. Please enter a number between 1 and 6."
    fi
}

exercise_3_hpa() {
    print_header "Exercise 3: Horizontal Pod Autoscaler"
    
    # Check if HPA exists
    if kubectl get hpa weatherapp -n directory >/dev/null 2>&1; then
        echo "HPA already exists:"
        kubectl get hpa weatherapp -n directory
        echo ""
        read -p "Do you want to delete and recreate HPA? (y/N): " recreate
        if [[ "$recreate" =~ ^[Yy]$ ]]; then
            kubectl delete hpa weatherapp -n directory
        else
            return
        fi
    fi
    
    echo "Creating HPA for weatherapp..."
    kubectl autoscale deployment weatherapp -n directory \
        --cpu-percent=50 \
        --min=2 \
        --max=10
    
    print_success "HPA created!"
    kubectl get hpa weatherapp -n directory
    
    echo ""
    print_info "To test HPA, use the load generator commands from the workshop"
}

exercise_6_rolling_update() {
    print_header "Exercise 6: Rolling Update Simulation"
    
    echo "Current image:"
    kubectl get deployment weatherapp -n directory -o jsonpath='{.spec.template.spec.containers[0].image}'
    echo ""
    
    echo "Simulating rolling update by adding deployment annotation..."
    kubectl patch deployment weatherapp -n directory -p '{"spec":{"template":{"metadata":{"annotations":{"workshop.update":"'$(date +%s)'","version":"workshop-v2"}}}}}'
    
    echo ""
    echo "Monitoring rolling update:"
    kubectl rollout status deployment/weatherapp -n directory
    
    echo ""
    print_success "Rolling update completed!"
    kubectl get pods -n directory -l app=weatherapp
}

exercise_rollback() {
    print_header "Rollback Exercise"
    
    echo "Rollout history:"
    kubectl rollout history deployment/weatherapp -n directory
    echo ""
    
    echo "Performing rollback to previous version..."
    kubectl rollout undo deployment/weatherapp -n directory
    
    echo ""
    echo "Monitoring rollback:"
    kubectl rollout status deployment/weatherapp -n directory
    
    print_success "Rollback completed!"
}

generate_load() {
    print_header "Load Generator"
    
    ALB_ENDPOINT=$(kubectl get ingress weatherapp-ingress -n directory -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    
    if [ -z "$ALB_ENDPOINT" ]; then
        print_error "ALB endpoint not found"
        return 1
    fi
    
    echo "ALB Endpoint: $ALB_ENDPOINT"
    echo ""
    
    read -p "Enter number of load generator pods (1-5): " pods
    
    if [[ "$pods" =~ ^[1-5]$ ]]; then
        echo "Creating $pods load generator pods..."
        for i in $(seq 1 $pods); do
            kubectl run load-generator-$i --image=busybox --restart=Never -n directory \
                -- /bin/sh -c "while true; do wget -q -O- http://$ALB_ENDPOINT/; sleep 0.5; done" &
        done
        
        print_success "Load generators created!"
        echo "Monitor with: watch 'kubectl get hpa -n directory'"
        echo "Stop with: workshop-helper.sh cleanup-load"
    else
        print_error "Invalid input. Please enter a number between 1 and 5."
    fi
}

cleanup_load() {
    print_header "Cleaning Up Load Generators"
    
    echo "Removing load generator pods..."
    kubectl delete pod -l run=load-generator -n directory 2>/dev/null || true
    for i in {1..5}; do 
        kubectl delete pod load-generator-$i -n directory 2>/dev/null || true
    done
    
    print_success "Load generators cleaned up!"
}

reset_workshop() {
    print_header "Resetting Workshop Environment"
    
    echo "This will reset:"
    echo "- Deployment replicas to 3"
    echo "- Remove HPA"
    echo "- Clean up load generators"
    echo "- Reset node group to 2 nodes"
    echo ""
    
    read -p "Are you sure you want to reset? (y/N): " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo "Resetting deployment..."
        kubectl scale deployment weatherapp --replicas=3 -n directory
        
        echo "Removing HPA..."
        kubectl delete hpa weatherapp -n directory 2>/dev/null || true
        
        echo "Cleaning up load generators..."
        cleanup_load
        
        echo "Resetting node group..."
        NODE_GROUP=$(aws eks list-nodegroups --cluster-name betech-cluster --query 'nodegroups[0]' --output text --region us-west-2)
        aws eks update-nodegroup-config \
            --cluster-name betech-cluster \
            --nodegroup-name $NODE_GROUP \
            --scaling-config minSize=1,maxSize=4,desiredSize=2 \
            --region us-west-2
        
        print_success "Workshop environment reset!"
    else
        echo "Reset cancelled."
    fi
}

show_help() {
    echo -e "${BLUE}Weather App Workshop Helper${NC}"
    echo "Usage: $0 [command]"
    echo ""
    echo "Available commands:"
    echo "  check           - Check prerequisites"
    echo "  status          - Show current status"
    echo "  ex1             - Exercise 1: Manual Pod Scaling"
    echo "  ex2             - Exercise 2: Node Group Scaling"
    echo "  ex3             - Exercise 3: Setup HPA"
    echo "  ex6             - Exercise 6: Rolling Update"
    echo "  rollback        - Perform rollback"
    echo "  load            - Generate load"
    echo "  cleanup-load    - Remove load generators"
    echo "  reset           - Reset workshop environment"
    echo "  help            - Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 check        # Verify setup"
    echo "  $0 status       # View current state"
    echo "  $0 ex1          # Start scaling exercise"
}

# Main script logic
case "${1:-help}" in
    "check")
        check_prerequisites
        ;;
    "status")
        show_status
        ;;
    "ex1")
        exercise_1_scaling
        ;;
    "ex2")
        exercise_2_node_scaling
        ;;
    "ex3")
        exercise_3_hpa
        ;;
    "ex6")
        exercise_6_rolling_update
        ;;
    "rollback")
        exercise_rollback
        ;;
    "load")
        generate_load
        ;;
    "cleanup-load")
        cleanup_load
        ;;
    "reset")
        reset_workshop
        ;;
    "help"|*)
        show_help
        ;;
esac
