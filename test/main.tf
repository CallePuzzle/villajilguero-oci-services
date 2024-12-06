
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
  timeout          = 120
  values = [templatefile("${path.module}/argocd-values.yaml", {
    SOPS_AGE_KEY = regex("AGE-SECRET-KEY-[[:alnum:]]+", file("${path.module}/.age-key.txt"))
  })]
}

resource "helm_release" "app_of_apps" {
  name       = "argo-apps"
  chart      = "argocd-apps"
  repository = "https://argoproj.github.io/argo-helm"
  version    = "1.4.1"
  namespace  = "argocd"
  timeout    = 120

  values = [<<EOF
applications:
  - name: manifests
    namespace: argocd
    finalizers:
    - resources-finalizer.argocd.argoproj.io
    project: default
    source:
      repoURL: https://github.com/CallePuzzle/villajilguero-oci-services.git
      targetRevision: 5-nextcloud-client-push
      path: manifests/test/argocd
      plugin:
        name: sops
    destination:
      server: https://kubernetes.default.svc
      namespace: argocd

  EOF
  ]
  depends_on = [helm_release.argocd]
}

resource "b2_application_key" "this" {
  key_name     = "callepuzzle-nextcloud-temp"
  capabilities = split(",", "deleteFiles,listBuckets,listFiles,readBucketEncryption,readBucketReplications,readBuckets,readFiles,shareFiles,writeBucketEncryption,writeBucketReplications,writeFiles")
  bucket_id    = b2_bucket.this.bucket_id
}

resource "b2_bucket" "this" {
  bucket_name = "callepuzzle-nextcloud-temp"
  bucket_type = "allPrivate"
}

resource "local_sensitive_file" "nextcloud_s3_secrets" {
  content = jsonencode({
    nextcloud_s3 = {
      host   = "s3.us-west-004.backblazeb2.com"
      bucket = b2_bucket.this.bucket_name
      key    = b2_application_key.this.application_key_id
      secret = b2_application_key.this.application_key
    }
  })
  filename = "${path.module}/nextcloud_s3_secrets.json"
}

output "sops" {
  value = "sops -e --age age1sw8rsjy0lwjcv9czyqretaew3696cz5laaaad3zx52clfmp85skqhwynx2 --output-type json secrets.json > secrets.enc"
}
