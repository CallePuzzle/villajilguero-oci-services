
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
  create_namespace = true
  values           = [templatefile("${path.module}/argocd-values.yaml", {})]
}

resource "helm_release" "app_of_apps" {
  name             = "argo-apps"
  chart            = "argocd-apps"
  repository       = "https://argoproj.github.io/argo-helm"
  version          = "1.4.1"
  namespace        = "argocd"

  values = [<<EOF
applications:
  - name: manifests
    namespace: argocd
    finalizers:
    - resources-finalizer.argocd.argoproj.io
    project: default
    source:
      repoURL: https://github.com/CallePuzzle/villajilguero-oci-services.git
      targetRevision: develop
      path: manifests/test
    destination:
      server: https://kubernetes.default.svc
      namespace: argocd

  EOF
  ]
  depends_on = [helm_release.argocd]
}
