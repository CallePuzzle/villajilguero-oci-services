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
      version = "8.23.0"
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
  # source = "git::https://github.com/CallePuzzle/terraform-module-k0s-oci?ref=v1.0.1"

  compartment_id  = data.sops_file.credentials.data["tenancy_ocid"]
  source_ocid     = "ocid1.image.oc1.eu-marseille-1.aaaaaaaaqihfeepadhdma7udc7n2vlfmienfwim4vl53dkftvfikrlxfi3ca"
  ssh_public_key  = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDQz0jQlA0vQ99L42+yGd9tho4Y0NwfE3+jW0pnDVmHg51Q3Nfg3aKFwg+PzsgY8/kU72dUltnw8lbI/+N/df8weWxdTpBBOpxnV8lOcFvtzvKY3C9TwqLiXspVaLa1f4LvhJjlQQrhDyiVoE4T3Fk2OL40JKLrgwC31FrIPXc8QzKm1A7QuOFwEW+DbQgWeFnDJiwun5rBhl9yTJ75T5EWgx9brQd4VW4cePAnYouQ8UtgCvXG/tDDjkVvCA8so3TaL/u0gXqBhBS4SPmMUJgAa4OHxJ025PFeE1E1zl4zhJmPvqhzTbiJpzPlioKn2egZut9/sQujxxHYo50aFM01qGERThkowzROMxyX+lSN/oLlcFvIWxKuxj6scc36k6qhQPAIOcetr9IHqk2ZgE3iRrikEao0+ACULyujFIq8G5XW52At4qqm+mbx/7j+tUe4a8ewO+HR4ByJDvpBOZENb//5QHCDUdOz+j5IIj26SWpITKX70cMDVHnZushQv8P1ifJSE1/Oi06PxxLX7BghsI0bzCH7oykFoiMEThhMSYMQkpyw+T2B1tacWacMION2eVaYwvoY+GfQWGnEDvZT8DE9TUVYDwibt2SO2aRluCBJ2/4VcLi6onx9wcZqcQGt0m1cZgqPkFdC+Tuyk7l/yj+CPzkhQuBlMD53ulG6Dw== cesar@callepuzzle.com"
  k0s_config_path = "${path.root}/k0sctl.yaml"
  k0s_version     = "1.28.9+k0s.0"

  argocd_host = "argocd.callepuzzle.com"

  projects = [
    {
      name = "manifests"
      source = {
        repo_url        = "https://github.com/CallePuzzle/villajilguero-oci-services"
        target_revision = "main"
        path            = "manifests"
        plugin          = "sops"
      }
      destination_namespace = "*"
      auto_sync             = false
    },
  ]

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
