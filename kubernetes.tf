# ################################################################################
# # Kubernetes Namespaces
# ################################################################################

# These namespaces are created after the EKS cluster is ready
# This ensures the Kubernetes provider can connect to the cluster

resource "kubernetes_namespace" "gateway" {
  depends_on = [module.eks]
  
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
  depends_on = [module.eks]
  
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
  depends_on = [module.eks]
  
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
