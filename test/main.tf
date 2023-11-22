
terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "2.11.0"
    }
  }
}

variable "kind_context" {
  type = string
}

provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = var.kind_context
  }
}

resource "helm_release" "argocd" {
  name             = "argo-cd"
  chart            = "argo-cd"
  repository       = "https://argoproj.github.io/argo-helm"
  version          = "5.51.4"
  namespace        = "argocd"
  timeout          = "120"
  create_namespace = true
  values           = [templatefile("${path.module}/argocd-values.yaml", {})]
}
