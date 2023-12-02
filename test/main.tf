
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
  values           = [templatefile("${path.module}/argocd-values.yaml", {
    SOPS_AGE_KEY = regex("AGE-SECRET-KEY-[[:alnum:]]+", file("${path.module}/../.key.txt"))
  })]
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
      plugin: {}
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

resource "local_sensitive_file" "this" {
  filename = "${path.module}/secrets.yaml"
  content = templatefile("${path.module}/secrets.tftpl", {
    MARIADB_PASSWORD = base64encode("mariadb")
    MARIADB_ROOT_PASSWORD = base64encode("root")
    NEXTCLOUD_USER = base64encode("admin")
    NEXTCLOUD_PASSWORD = base64encode("admin")
    NEXTCLOUD_TOKEN = base64encode("bKc52A4yr8ukRLNa")
    NEXTCLOUD_BUCKET_NAME = base64encode(b2_bucket.this.bucket_name)
    NEXTCLOUD_BUCKET_HOST = base64encode("s3.us-west-004.backblazeb2.com")
    NEXTCLOUD_BUCKET_ACCESS_KEY = base64encode(b2_application_key.this.application_key_id)
    NEXTCLOUD_BUCKET_SECRET_KEY = base64encode(b2_application_key.this.application_key)
    NEXTCLOUD_DB_USERNAME = base64encode("nextcloud")
    NEXTCLOUD_DB_PASSWORD = base64encode("nextcloud")
    NEXTCLOUD_DB_USERNAME_TEXT = "nextcloud"
  })
}

resource "null_resource" "sops_encrypt" {
  depends_on = [local_sensitive_file.this]

  triggers = {
    updated = local_sensitive_file.this.id
  }

  provisioner "local-exec" {
    command = "sops -e --age age1cz6z4uq36tfuvevqpx8rzcfvqgncmczwgmlmwdqxluh8gncw8pjq03scha --input-type yaml --output-type yaml ${local_sensitive_file.this.filename} > secrets.enc"
  }
}