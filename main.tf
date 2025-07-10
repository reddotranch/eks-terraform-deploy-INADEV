# ################################################################################
# # VPC Module
# ################################################################################

module "vpc" {
  source      = "./modules/vpc"
  main-region = var.main-region
}

# ################################################################################
# # EKS Cluster Module
# ################################################################################

module "eks" {
  source = "./modules/eks-cluster"

  rolearn = var.rolearn

  vpc_id          = module.vpc.vpc_id
  private_subnets = module.vpc.private_subnets
}

# ################################################################################
# # AWS ALB Controller - MOVED TO STAGE 2
# ################################################################################

# The ALB controller is now deployed in stage2-alb-controller.tf to avoid
# circular dependency issues with Kubernetes/Helm providers

# module "aws_alb_controller" {
#   source = "./modules/aws-alb-controller"
#
#   main-region  = var.main-region
#   env_name     = var.env_name
#   cluster_name = var.cluster_name
#
#   vpc_id            = module.vpc.vpc_id
#   oidc_provider_arn = module.eks.oidc_provider_arn
#   
#   depends_on = [module.eks]
# }
