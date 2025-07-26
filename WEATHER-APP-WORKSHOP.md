# Weather App Workshop: EKS Operations & Best Practices

## 🎯 Workshop Overview
This hands-on workshop covers essential Kubernetes and AWS EKS operations using our weather app deployed on the `betech-cluster`. You'll practice real-world scenarios including scaling, autoscaling, rolling updates, and hotfixes.

## 📋 Prerequisites
- Access to `betech-cluster` EKS cluster
- `kubectl` configured and connected
- `aws` CLI configured
- Git repository access
- Basic understanding of Kubernetes concepts

## 🚀 Workshop Exercises

### Exercise 1: Manual Pod Scaling
**Objective**: Learn to manually scale deployment replicas

#### 1.1 Current State Check
```bash
# Check current deployment status
kubectl get deployment weatherapp -n directory
kubectl get pods -n directory -l app=weatherapp

# View deployment details
kubectl describe deployment weatherapp -n directory
```

#### 1.2 Scale Up Pods
```bash
# Scale deployment to 5 replicas
kubectl scale deployment weatherapp --replicas=5 -n directory

# Watch the scaling process
kubectl get pods -n directory -l app=weatherapp -w

# Verify scaling completed
kubectl get deployment weatherapp -n directory
```

#### 1.3 Scale Down Pods
```bash
# Scale down to 2 replicas
kubectl scale deployment weatherapp --replicas=2 -n directory

# Watch pods terminating
kubectl get pods -n directory -l app=weatherapp -w

# Check final state
kubectl get deployment weatherapp -n directory
```

#### 1.4 Using YAML for Scaling
```bash
# Edit deployment directly
kubectl edit deployment weatherapp -n directory
# Change spec.replicas to 6, save and exit

# Alternative: patch method
kubectl patch deployment weatherapp -n directory -p '{"spec":{"replicas":4}}'
```

---

### Exercise 2: Manual Node Group Scaling
**Objective**: Scale EKS node groups to handle different workloads

#### 2.1 Check Current Node Status
```bash
# List all nodes
kubectl get nodes -o wide

# Check node group information
aws eks describe-nodegroup \
  --cluster-name betech-cluster \
  --nodegroup-name $(aws eks list-nodegroups --cluster-name betech-cluster --query 'nodegroups[0]' --output text) \
  --region us-west-2
```

#### 2.2 Scale Node Group Up
```bash
# Get node group name
NODE_GROUP=$(aws eks list-nodegroups --cluster-name betech-cluster --query 'nodegroups[0]' --output text --region us-west-2)

# Scale node group to 4 nodes
aws eks update-nodegroup-config \
  --cluster-name betech-cluster \
  --nodegroup-name $NODE_GROUP \
  --scaling-config minSize=2,maxSize=6,desiredSize=4 \
  --region us-west-2

# Monitor scaling progress
watch "kubectl get nodes"
```

#### 2.3 Scale Node Group Down
```bash
# Scale back to 2 nodes
aws eks update-nodegroup-config \
  --cluster-name betech-cluster \
  --nodegroup-name $NODE_GROUP \
  --scaling-config minSize=1,maxSize=6,desiredSize=2 \
  --region us-west-2

# Wait for scaling to complete
kubectl get nodes -w
```

---

### Exercise 3: Horizontal Pod Autoscaler (HPA)
**Objective**: Configure automatic pod scaling based on resource usage

#### 3.1 Install Metrics Server (if not present)
```bash
# Check if metrics server exists
kubectl get deployment metrics-server -n kube-system

# If not present, install it
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

#### 3.2 Configure Resource Requests
```bash
# Create HPA-ready deployment configuration
cat > weatherapp-hpa-config.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: weatherapp
  namespace: directory
spec:
  replicas: 3
  selector:
    matchLabels:
      app: weatherapp
  template:
    metadata:
      labels:
        app: weatherapp
    spec:
      containers:
      - name: weatherapp-container
        image: 374965156099.dkr.ecr.us-west-2.amazonaws.com/weatherapp:1.5.2
        ports:
        - containerPort: 8081
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
EOF

# Apply the updated configuration
kubectl apply -f weatherapp-hpa-config.yaml
```

#### 3.3 Create HPA
```bash
# Create HPA for weatherapp
kubectl autoscale deployment weatherapp -n directory \
  --cpu-percent=50 \
  --min=2 \
  --max=10

# View HPA status
kubectl get hpa -n directory
kubectl describe hpa weatherapp -n directory
```

#### 3.4 Generate Load to Trigger Autoscaling
```bash
# Get the ALB endpoint
ALB_ENDPOINT=$(kubectl get ingress weatherapp-ingress -n directory -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Generate load using a load generator pod
kubectl run load-generator --image=busybox --restart=Never -n directory -- /bin/sh -c "while true; do wget -q -O- http://$ALB_ENDPOINT/; sleep 0.1; done"

# Watch HPA scaling in action
watch "kubectl get hpa -n directory"

# Monitor pod scaling
kubectl get pods -n directory -l app=weatherapp -w
```

#### 3.5 Stop Load and Observe Scale Down
```bash
# Delete load generator
kubectl delete pod load-generator -n directory

# Watch scale down (may take 5-10 minutes)
watch "kubectl get hpa -n directory && echo '---' && kubectl get pods -n directory -l app=weatherapp"
```

---

### Exercise 4: Cluster Autoscaler
**Objective**: Configure automatic node scaling based on pod requirements

#### 4.1 Deploy Cluster Autoscaler
```bash
# Create cluster autoscaler deployment
cat > cluster-autoscaler.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cluster-autoscaler
  namespace: kube-system
  labels:
    app: cluster-autoscaler
spec:
  selector:
    matchLabels:
      app: cluster-autoscaler
  template:
    metadata:
      labels:
        app: cluster-autoscaler
    spec:
      serviceAccountName: cluster-autoscaler
      containers:
      - image: k8s.gcr.io/autoscaling/cluster-autoscaler:v1.21.0
        name: cluster-autoscaler
        resources:
          limits:
            cpu: 100m
            memory: 300Mi
          requests:
            cpu: 100m
            memory: 300Mi
        command:
        - ./cluster-autoscaler
        - --v=4
        - --stderrthreshold=info
        - --cloud-provider=aws
        - --skip-nodes-with-local-storage=false
        - --expander=least-waste
        - --node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/betech-cluster
        env:
        - name: AWS_REGION
          value: us-west-2
---
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
    k8s-app: cluster-autoscaler
  name: cluster-autoscaler
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cluster-autoscaler
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
    k8s-app: cluster-autoscaler
rules:
- apiGroups: [""]
  resources: ["events","endpoints"]
  verbs: ["create", "patch"]
- apiGroups: [""]
  resources: ["pods/eviction"]
  verbs: ["create"]
- apiGroups: [""]
  resources: ["pods/status"]
  verbs: ["update"]
- apiGroups: [""]
  resources: ["endpoints"]
  resourceNames: ["cluster-autoscaler"]
  verbs: ["get","update"]
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["watch","list","get","update"]
- apiGroups: [""]
  resources: ["pods","services","replicationcontrollers","persistentvolumeclaims","persistentvolumes"]
  verbs: ["watch","list","get"]
- apiGroups: ["extensions"]
  resources: ["replicasets","daemonsets"]
  verbs: ["watch","list","get"]
- apiGroups: ["policy"]
  resources: ["poddisruptionbudgets"]
  verbs: ["watch","list"]
- apiGroups: ["apps"]
  resources: ["statefulsets","replicasets","daemonsets"]
  verbs: ["watch","list","get"]
- apiGroups: ["storage.k8s.io"]
  resources: ["storageclasses","csinodes"]
  verbs: ["watch","list","get"]
- apiGroups: ["batch", "extensions"]
  resources: ["jobs"]
  verbs: ["get","list","patch","watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cluster-autoscaler
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
    k8s-app: cluster-autoscaler
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-autoscaler
subjects:
- kind: ServiceAccount
  name: cluster-autoscaler
  namespace: kube-system
EOF

# Apply cluster autoscaler
kubectl apply -f cluster-autoscaler.yaml
```

#### 4.2 Trigger Cluster Autoscaling
```bash
# Create resource-intensive pods to trigger node scaling
kubectl create deployment resource-hog --image=nginx -n directory
kubectl scale deployment resource-hog --replicas=20 -n directory

# Set resource requests to force new nodes
kubectl patch deployment resource-hog -n directory -p '{"spec":{"template":{"spec":{"containers":[{"name":"nginx","resources":{"requests":{"cpu":"1000m","memory":"1Gi"}}}]}}}}'

# Watch cluster autoscaler logs
kubectl logs -f deployment/cluster-autoscaler -n kube-system

# Monitor node scaling
watch "kubectl get nodes"
```

#### 4.3 Scale Down Test
```bash
# Delete resource-intensive deployment
kubectl delete deployment resource-hog -n directory

# Watch nodes scale down (takes 10-15 minutes)
watch "kubectl get nodes"
```

---

### Exercise 5: Load Balancer Autoscaling
**Objective**: Understand ALB behavior under different loads

#### 5.1 Monitor Current ALB Status
```bash
# Get ALB ARN
ALB_ARN=$(aws elbv2 describe-load-balancers \
  --names weatherapp-server-ip \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text --region us-west-2)

# Check target group health
TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups \
  --load-balancer-arn $ALB_ARN \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text --region us-west-2)

aws elbv2 describe-target-health \
  --target-group-arn $TARGET_GROUP_ARN \
  --region us-west-2
```

#### 5.2 Load Testing with Multiple Clients
```bash
# Create multiple load generators
for i in {1..5}; do
  kubectl run load-generator-$i --image=busybox --restart=Never -n directory -- /bin/sh -c "while true; do wget -q -O- http://$ALB_ENDPOINT/; sleep 0.5; done" &
done

# Monitor ALB metrics in AWS Console or CLI
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name RequestCount \
  --dimensions Name=LoadBalancer,Value=$(echo $ALB_ARN | cut -d'/' -f2-) \
  --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum \
  --region us-west-2
```

#### 5.3 Cleanup Load Generators
```bash
# Remove all load generators
kubectl delete pod -l run=load-generator -n directory
for i in {1..5}; do kubectl delete pod load-generator-$i -n directory 2>/dev/null || true; done
```

---

### Exercise 6: Rolling Updates and Rollbacks
**Objective**: Practice application updates and version management

#### 6.1 Prepare New Application Version
```bash
# First, let's create a simple script to modify the weather app
cat > update-weather-app.py << 'EOF'
#!/usr/bin/env python3
import re
import sys

def update_header(file_path, new_header):
    with open(file_path, 'r') as f:
        content = f.read()
    
    # Update the title/header in the HTML template
    content = re.sub(r'<title>.*?</title>', f'<title>{new_header}</title>', content, flags=re.IGNORECASE)
    content = re.sub(r'<h1.*?>.*?</h1>', f'<h1>{new_header}</h1>', content, flags=re.IGNORECASE | re.DOTALL)
    
    with open(file_path, 'w') as f:
        f.write(content)

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python3 update-weather-app.py <file_path> <new_header>")
        sys.exit(1)
    
    update_header(sys.argv[1], sys.argv[2])
    print(f"Updated header to: {sys.argv[2]}")
EOF

chmod +x update-weather-app.py
```

#### 6.2 Check Current Application Version
```bash
# Check current deployment image
kubectl get deployment weatherapp -n directory -o jsonpath='{.spec.template.spec.containers[0].image}'

# Check rollout history
kubectl rollout history deployment/weatherapp -n directory

# Test current application
ALB_ENDPOINT=$(kubectl get ingress weatherapp-ingress -n directory -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -s http://$ALB_ENDPOINT/ | grep -i "<title>\|<h1>"
```

#### 6.3 Simulate Application Update
```bash
# Let's simulate updating to a new version by changing the image tag
# First, tag current deployment
kubectl annotate deployment weatherapp -n directory deployment.kubernetes.io/revision-history="v1.5.2-original"

# Update to a "new version" (we'll use a different tag or simulate with rolling restart)
# Option 1: Change image tag (if you have different versions)
kubectl set image deployment/weatherapp weatherapp-container=374965156099.dkr.ecr.us-west-2.amazonaws.com/weatherapp:1.5.3 -n directory

# Option 2: If no new image, trigger rolling restart with annotation
kubectl patch deployment weatherapp -n directory -p '{"spec":{"template":{"metadata":{"annotations":{"app.version":"v1.5.3","deployment.date":"'$(date)'"}}}}}'
```

#### 6.4 Monitor Rolling Update
```bash
# Watch rolling update progress
kubectl rollout status deployment/weatherapp -n directory

# Monitor pods during update
kubectl get pods -n directory -l app=weatherapp -w

# Check rollout history
kubectl rollout history deployment/weatherapp -n directory
```

#### 6.5 Perform Rollback
```bash
# Rollback to previous version
kubectl rollout undo deployment/weatherapp -n directory

# Monitor rollback
kubectl rollout status deployment/weatherapp -n directory

# Verify rollback
kubectl get deployment weatherapp -n directory -o jsonpath='{.spec.template.spec.containers[0].image}'

# Check rollout history
kubectl rollout history deployment/weatherapp -n directory
```

#### 6.6 Rollback to Specific Revision
```bash
# View detailed rollout history
kubectl rollout history deployment/weatherapp -n directory --revision=1
kubectl rollout history deployment/weatherapp -n directory --revision=2

# Rollback to specific revision
kubectl rollout undo deployment/weatherapp -n directory --to-revision=1

# Verify specific rollback
kubectl rollout status deployment/weatherapp -n directory
```

---

### Exercise 7: Git Repository Hotfixes
**Objective**: Practice emergency fixes and rapid deployment

#### 7.1 Setup Local Repository
```bash
# Clone the repository (adjust URL as needed)
cd /tmp
git clone https://github.com/your-org/weatherapp-repo.git
cd weatherapp-repo

# Create a hotfix branch
git checkout -b hotfix/critical-header-fix
```

#### 7.2 Implement Emergency Fix
```bash
# Find the main application file (adjust path as needed)
# This is a simulation - adapt to your actual file structure
cat > simulated-hotfix.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>BETECH Weather App - HOTFIX v1.5.4</title>
</head>
<body>
    <h1>🚨 BETECH Weather Service - Emergency Update</h1>
    <p>Critical security patch applied - v1.5.4</p>
    <p>Service operational status: ✅ HEALTHY</p>
</body>
</html>
EOF

# Simulate updating the application code
echo "# HOTFIX v1.5.4 - Critical security patch" >> README.md
```

#### 7.3 Rapid Deployment Process
```bash
# Commit hotfix
git add .
git commit -m "HOTFIX: Critical security patch v1.5.4

- Fixed security vulnerability in header processing
- Updated service status display
- Emergency deployment approved"

# Push hotfix branch
git push origin hotfix/critical-header-fix

# Simulate building new container (in real scenario, this would trigger CI/CD)
echo "🏗️  Building emergency container image..."
echo "📦 Pushing to ECR: weatherapp:1.5.4-hotfix"
echo "✅ Image ready for deployment"
```

#### 7.4 Emergency Deployment
```bash
# Deploy hotfix immediately
kubectl set image deployment/weatherapp \
  weatherapp-container=374965156099.dkr.ecr.us-west-2.amazonaws.com/weatherapp:1.5.4-hotfix \
  -n directory

# Force immediate rollout
kubectl rollout restart deployment/weatherapp -n directory

# Monitor emergency deployment
kubectl rollout status deployment/weatherapp -n directory --timeout=300s

# Verify hotfix deployment
kubectl get pods -n directory -l app=weatherapp
kubectl describe deployment weatherapp -n directory | grep Image:
```

#### 7.5 Hotfix Verification and Cleanup
```bash
# Test application after hotfix
curl -s http://$ALB_ENDPOINT/ | head -20

# Create merge request/pull request (simulate)
echo "🔀 Creating emergency merge request..."
echo "📋 Hotfix verification checklist:"
echo "   ✅ Security vulnerability patched"
echo "   ✅ Application responding correctly"
echo "   ✅ No service disruption"
echo "   ✅ Monitoring shows healthy status"

# Merge hotfix to main (simulation)
git checkout main
git merge hotfix/critical-header-fix
git push origin main

# Tag the hotfix release
git tag -a v1.5.4-hotfix -m "Emergency hotfix release v1.5.4"
git push origin v1.5.4-hotfix

# Cleanup hotfix branch
git branch -d hotfix/critical-header-fix
git push origin --delete hotfix/critical-header-fix
```

---

## 🔧 Cleanup and Reset Commands

### Reset to Original State
```bash
# Reset deployment to original image
kubectl set image deployment/weatherapp \
  weatherapp-container=374965156099.dkr.ecr.us-west-2.amazonaws.com/weatherapp:1.5.2 \
  -n directory

# Scale back to original replicas
kubectl scale deployment weatherapp --replicas=3 -n directory

# Remove HPA
kubectl delete hpa weatherapp -n directory 2>/dev/null || true

# Remove cluster autoscaler
kubectl delete -f cluster-autoscaler.yaml 2>/dev/null || true

# Clean up any remaining load generators
kubectl delete pod -l run=load-generator -n directory 2>/dev/null || true

# Reset node group size
NODE_GROUP=$(aws eks list-nodegroups --cluster-name betech-cluster --query 'nodegroups[0]' --output text --region us-west-2)
aws eks update-nodegroup-config \
  --cluster-name betech-cluster \
  --nodegroup-name $NODE_GROUP \
  --scaling-config minSize=1,maxSize=4,desiredSize=2 \
  --region us-west-2
```

### Verification Commands
```bash
# Final state check
echo "🔍 Final Verification:"
echo "====================="
kubectl get deployment weatherapp -n directory
kubectl get pods -n directory -l app=weatherapp
kubectl get nodes
kubectl get hpa -n directory 2>/dev/null || echo "HPA: Not configured"
kubectl get svc -n directory
kubectl get ingress -n directory
```

---

## 📊 Workshop Completion Checklist

- [ ] ✅ Manual pod scaling (up/down)
- [ ] ✅ Manual node group scaling
- [ ] ✅ Horizontal Pod Autoscaler configuration
- [ ] ✅ Cluster Autoscaler deployment
- [ ] ✅ Load balancer monitoring
- [ ] ✅ Rolling updates execution
- [ ] ✅ Application rollback procedures
- [ ] ✅ Emergency hotfix deployment
- [ ] ✅ Git workflow for hotfixes
- [ ] ✅ Environment cleanup

## 🎓 Key Takeaways

1. **Scaling Strategies**: Manual vs automatic scaling considerations
2. **Resource Management**: Importance of resource requests/limits
3. **Rolling Updates**: Zero-downtime deployment techniques
4. **Rollback Procedures**: Quick recovery from failed deployments
5. **Emergency Response**: Rapid hotfix deployment workflows
6. **Monitoring**: Observing system behavior during operations
7. **Best Practices**: Production-ready configurations

## 📚 Additional Resources

- [Kubernetes Scaling Documentation](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#scaling-a-deployment)
- [HPA Configuration Guide](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Rolling Updates Strategy](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#rolling-update-deployment)

---

**🎉 Congratulations!** You've completed the comprehensive weather app workshop covering essential EKS and Kubernetes operations!
