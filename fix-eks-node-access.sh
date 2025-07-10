#!/bin/bash

echo "🔧 EKS Node Access Fix Script"
echo "This script fixes aws-auth ConfigMap issues when nodes can't join the cluster"

# Set variables
CLUSTER_NAME="betech-cluster"
REGION="us-west-2"

echo "📋 Step 1: Checking cluster status..."
aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query 'cluster.status'

echo "📋 Step 2: Getting node groups..."
NODE_GROUPS=$(aws eks list-nodegroups --cluster-name $CLUSTER_NAME --region $REGION --query 'nodegroups[]' --output text)

if [ -z "$NODE_GROUPS" ]; then
    echo "❌ No node groups found!"
    exit 1
fi

echo "✅ Found node groups: $NODE_GROUPS"

echo "📋 Step 3: Getting node group IAM roles..."
NODE_ROLES=()
for ng in $NODE_GROUPS; do
    ROLE=$(aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $ng --region $REGION --query 'nodegroup.nodeRole' --output text)
    echo "   Node group $ng: $ROLE"
    NODE_ROLES+=("$ROLE")
done

echo "📋 Step 4: Checking current aws-auth ConfigMap..."
kubectl get configmap aws-auth -n kube-system -o yaml

echo "📋 Step 5: Building new aws-auth ConfigMap..."

# Create the mapRoles YAML content
cat > /tmp/aws-auth-fix.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
EOF

# Add node group roles
for role in "${NODE_ROLES[@]}"; do
    cat >> /tmp/aws-auth-fix.yaml << EOF
    - groups:
      - system:bootstrappers
      - system:nodes
      rolearn: $role
      username: system:node:{{EC2PrivateDNSName}}
EOF
done

# Add user role (assuming terraform-poweruser role exists)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
cat >> /tmp/aws-auth-fix.yaml << EOF
    - groups:
      - system:masters
      rolearn: arn:aws:iam::$ACCOUNT_ID:role/terraform-poweruser
      username: betech-west
EOF

echo "📋 Step 6: Applying fixed aws-auth ConfigMap..."
kubectl apply -f /tmp/aws-auth-fix.yaml

echo "📋 Step 7: Waiting for nodes to become ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s

echo "📋 Step 8: Final verification..."
kubectl get nodes
kubectl get pods -n kube-system | grep -E "(aws-load-balancer|coredns|ebs-csi)"

echo "✅ EKS node access fix completed!"
echo "🧹 Cleaning up temporary file..."
rm -f /tmp/aws-auth-fix.yaml
