################################################################################
# EKS Cluster
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.28"

  cluster_endpoint_public_access = true

  create_kms_key              = false
  create_cloudwatch_log_group = false
  cluster_encryption_config   = {}

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
    }
  }

  vpc_id                   = var.vpc_id
  subnet_ids               = var.private_subnets
  control_plane_subnet_ids = var.private_subnets

  # EKS Managed Node Group(s)
  eks_managed_node_group_defaults = {
    instance_types = ["m5.xlarge", "m5.large", "t3.medium"]
    iam_role_additional_policies = {
      AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
#      ExternalDNSPolicy = "arn:aws:iam::654654193818:policy/AllowExternalDNSUpdates"
    }
  }

  eks_managed_node_groups = {
    node-group-01 = {
      min_size     = 1
      max_size     = 10
      desired_size = 3

      instance_types = ["t3.large"]
      capacity_type  = "SPOT"
    }
    node-group-02 = {
      min_size     = 1
      max_size     = 10
      desired_size = 3

      instance_types = ["t3.large"]
      capacity_type  = "SPOT"
    }
  }

  # aws-auth configmap - disable to avoid circular dependency
  manage_aws_auth_configmap = false
  create_aws_auth_configmap = false

  # aws_auth_roles = [
  #   {
  #     rolearn  = var.rolearn
  #     username = "betech-west"
  #     groups   = ["system:masters"]
  #   },
  # ]

  tags = {
    env       = "dev"
    terraform = "true"
  }
}

###################################
