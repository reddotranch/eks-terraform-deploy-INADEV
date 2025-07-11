# This file should be applied AFTER the EKS cluster is created and kubectl is configured
# Use: terraform apply -target=helm_release.aws_load_balancer_controller

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.10"
    }
  }
}

provider "aws" {
  region = var.main-region
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      data.aws_eks_cluster.cluster.name
    ]
  }
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
    
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks",
        "get-token",
        "--cluster-name",
        data.aws_eks_cluster.cluster.name
      ]
    }
  }
}

# ################################################################################
# Data Sources
# ################################################################################

data "aws_eks_cluster" "cluster" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = var.cluster_name
}

# Get EKS node group information
data "aws_eks_node_groups" "cluster" {
  cluster_name = var.cluster_name
}

# Get node group details to extract IAM roles
data "aws_eks_node_group" "nodes" {
  for_each         = toset(data.aws_eks_node_groups.cluster.names)
  cluster_name     = var.cluster_name
  node_group_name  = each.value
}

# Get OIDC issuer URL without https://
data "aws_iam_openid_connect_provider" "eks" {
  url = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

# Create a list of node group roles for aws-auth
locals {
  node_group_roles = [
    for ng in data.aws_eks_node_group.nodes : {
      rolearn  = ng.node_role_arn
      username = "system:node:{{EC2PrivateDNSName}}"
      groups   = ["system:bootstrappers", "system:nodes"]
    }
  ]
  
  # Combine user roles and node group roles
  auth_roles = concat(
    local.node_group_roles,
    [
      {
        rolearn  = var.rolearn
        username = "betech-west"
        groups   = ["system:masters"]
      }
    ]
  )
}

module "aws_load_balancer_controller_irsa_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name                              = "${var.env_name}-alb-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = data.aws_iam_openid_connect_provider.eks.arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }


}

################################################################################
# Kubernetes Service Account
################################################################################

resource "kubernetes_service_account" "aws_load_balancer_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    labels = {
      "app.kubernetes.io/name"      = "aws-load-balancer-controller"
      "app.kubernetes.io/component" = "controller"
    }
    annotations = {
      "eks.amazonaws.com/role-arn"               = module.aws_load_balancer_controller_irsa_role.iam_role_arn
      "eks.amazonaws.com/sts-regional-endpoints" = "true"
    }
  }
}

################################################################################
# Helm Chart for AWS Load Balancer Controller
################################################################################

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.6.2"

  depends_on = [
    kubernetes_service_account.aws_load_balancer_controller
  ]

  values = [
    yamlencode({
      clusterName = data.aws_eks_cluster.cluster.name
      serviceAccount = {
        create = false
        name   = "aws-load-balancer-controller"
      }
      region = var.main-region
      vpcId  = var.vpc_id
      image = {
        repository = "602401143452.dkr.ecr.${var.main-region}.amazonaws.com/amazon/aws-load-balancer-controller"
      }
    })
  ]
}

# ################################################################################
# Variables for Stage 2
# ################################################################################

variable "main-region" {
  description = "AWS region"
  type        = string
}

variable "env_name" {
  description = "Environment name"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "rolearn" {
  description = "IAM role ARN for EKS access"
  type        = string
}

# ################################################################################
# Kubernetes Namespaces
# ################################################################################

resource "kubernetes_namespace" "gateway" {
  metadata {
    annotations = {
      name = "gateway"
    }

    labels = {
      app = "webapp"
    }

    name = "gateway"
  }
}

resource "kubernetes_namespace" "directory" {
  metadata {
    annotations = {
      name = "directory"
    }

    labels = {
      app = "webapp"
    }

    name = "directory"
  }
}

resource "kubernetes_namespace" "analytics" {
  metadata {
    annotations = {
      name = "analytics"
    }

    labels = {
      app = "webapp"
    }

    name = "analytics"
  }
}

# ################################################################################
# AWS Auth ConfigMap
# ################################################################################

resource "kubernetes_config_map_v1_data" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = yamlencode(local.auth_roles)
  }

  force = true
  
  # Ensure this runs after node groups are available
  depends_on = [data.aws_eks_node_group.nodes]
}
