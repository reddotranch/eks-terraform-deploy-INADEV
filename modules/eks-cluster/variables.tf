################################################################################
# General Variables from root module
################################################################################
variable "cluster_name" {
  type    = string
  default = "betech-cluster"
}

################################################################################
# Variables from other Modules
################################################################################

variable "vpc_id" {
  description = "VPC ID which EKS cluster is deployed in"
  type        = string
  # default     = "vpc-03f2dbbcdfadabdb3"
  # default     = "vpc-00e435af9b6bdb38a"
}

variable "private_subnets" {
  description = "VPC Private Subnets which EKS cluster is deployed in"
  type        = list(any)
  # default = [ "subnet-040de6219e9432362", "subnet-01f19b9eda439a9b3", "subnet-0854fbf3730708b04"  ]
  # default = [ "subnet-02dbcffbed6d9f6f4", "subnet-014ff7d974ff51748", "subnet-04ad5e4462246909c"  ]
}

################################################################################
# Variables defined using Environment Variables
################################################################################

variable "rolearn" {
  description = "Add admin role to the aws-auth configmap"
  type        = string
  default     = "arn:aws:iam::374965156099:role/terraform-poweruser"
}

