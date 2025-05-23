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
      version = "1.1.1"
    }
    b2 = {
      source  = "Backblaze/b2"
      version = "0.9.0"
    }
    oci = {
      source  = "oracle/oci"
      version = "6.18.0"
    }
  }
}

provider "oci" {
  tenancy_ocid = data.sops_file.credentials.data["tenancy_ocid"]
  user_ocid    = data.sops_file.credentials.data["user_ocid"]
  fingerprint  = data.sops_file.credentials.data["fingerprint"]
  private_key  = data.sops_file.credentials.data["private_key"]
  region       = "eu-marseille-1"
}

provider "b2" {
  application_key    = data.sops_file.credentials.data["b2_application_key"]
  application_key_id = data.sops_file.credentials.data["b2_application_key_id"]
}

data "sops_file" "argo" {
  source_file = "secrets.enc.yaml"
}

data "sops_file" "credentials" {
  source_file = "credentials.enc.json"
  input_type  = "json"
}

module "oci-k0s" {
  source = "../../terraform-module-k0s-oci/"

  compartment_id  = data.sops_file.credentials.data["tenancy_ocid"]
  source_ocid     = "ocid1.image.oc1.eu-marseille-1.aaaaaaaaqihfeepadhdma7udc7n2vlfmienfwim4vl53dkftvfikrlxfi3ca"
  k0s_config_path = "${path.root}/k0sctl.yaml"
  k0s_version     = "v1.28.9+k0s.0"

  argocd_host = "argocd.callepuzzle.com"

  manifests_source = {
    repo_url        = "https://github.com/CallePuzzle/villajilguero-oci-services"
    target_revision = "main"
    path            = "manifests"
    plugin          = "sops"
  }

  instance_source_ocid = "ocid1.image.oc1.eu-marseille-1.aaaaaaaaqihfeepadhdma7udc7n2vlfmienfwim4vl53dkftvfikrlxfi3ca"

  argocd_values = templatefile("${path.root}/argocd-values.yaml.tmpl", {
    argocd_host          = "argocd.callepuzzle.com"
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
