
terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "2.11.0"
    }
    b2 = {
      source  = "Backblaze/b2"
      version = "0.8.4"
    }
  }
}

variable "kind_context" {
  type    = string
  default = "kind-jilgue"
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
  name       = "argo-apps"
  chart      = "argocd-apps"
  repository = "https://argoproj.github.io/argo-helm"
  version    = "1.4.1"
  namespace  = "argocd"

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

resource "b2_application_key" "this" {
  key_name     = "my-key"
  capabilities = split(",", "deleteFiles,listBuckets,listFiles,readBucketEncryption,readBucketReplications,readBuckets,readFiles,shareFiles,writeBucketEncryption,writeBucketReplications,writeFiles")
  bucket_id    = b2_bucket.this.bucket_id
}

resource "b2_bucket" "this" {
  bucket_name = "callepuzzle-nextcloud-temp"
  bucket_type = "allPrivate"
}

output "application_key" {
  value = b2_application_key.this.application_key
  sensitive = true
}

output "application_key_id" {
  value = b2_application_key.this.application_key_id
  sensitive = true
}