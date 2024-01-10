terraform {
  cloud {
    organization = "villajilguero"

    workspaces {
      name = "k0s"
    }
  }
  required_providers {
    sops = {
      source  = "carlpett/sops"
      version = "1.0.0"
    }
    b2 = {
      source  = "Backblaze/b2"
      version = "0.8.4"
    }
  }
}

provider "oci" {}

provider "sops" {}

data "sops_file" "argo" {
  source_file = "secrets.enc.yaml"
}

module "oci-k0s" {
  source = "../../terraform-module-k0s-oci/"

  compartment_id  = "ocid1.tenancy.oc1..aaaaaaaa5ii3uidynoqhjub5ub66fm3ryn2my6txw6xrguihckyr2uyarlkq"
  k0s_config_path = "${path.root}/k0sctl.yaml"

  argocd_host = "argocd-villajilguero.callepuzzle.com"

  manifests_source = {
    repo_url        = "https://github.com/CallePuzzle/villajilguero-oci-services"
    target_revision = "nextcloud"
    path            = "manifests"
  }

  argocd_values = templatefile("${path.root}/argocd-values.yaml.tmpl", {
    argocd_host          = "argocd-villajilguero.callepuzzle.com"
    github_client_id     = data.sops_file.argo.data["github.clientID"]
    github_client_secret = data.sops_file.argo.data["github.clientSecret"]
    sops_age_key         = data.sops_file.argo.data["sops_age_key"]
  })
}

resource "b2_application_key" "this" {
  key_name     = "callepuzzle-nextcloud"
  capabilities = split(",", "deleteFiles,listBuckets,listFiles,readBucketEncryption,readBucketReplications,readBuckets,readFiles,shareFiles,writeBucketEncryption,writeBucketReplications,writeFiles")
  bucket_id    = b2_bucket.this.bucket_id
}

resource "b2_bucket" "this" {
  bucket_name = "callepuzzle-nextcloud"
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
  value = "sops -e --age age1fffgfwlmw8k9ln7ssdvtfz428etrnch4es5kv37d06h0t7lurghq3la73z --output-type json secrets.json > secrets.enc"
}

output "public_ip" {
  value = module.oci-k0s.public_ip
}
