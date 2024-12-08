terraform {
  cloud {
    organization = "villajilguero"

    workspaces {
      name = "jilguedev"
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

data "sops_file" "credentials" {
  source_file = "credentials.enc.json"
  input_type  = "json"
}

provider "oci" {
  tenancy_ocid = data.sops_file.credentials.data["tenancy_ocid"]
  user_ocid    = data.sops_file.credentials.data["user_ocid"]
  fingerprint  = data.sops_file.credentials.data["fingerprint"]
  private_key  = data.sops_file.credentials.data["private_key"]
  region       = "eu-madrid-1"
}

data "sops_file" "argo" {
  source_file = "secrets.enc.yaml"
}

locals {
  argocd_host = "argocd-jilgue.callepuzzle.com"
}

module "oci-k0s" {
  source = "git::https://github.com/CallePuzzle/terraform-module-k0s-oci?ref=v1.0.1"
  #source = "../../terraform-module-k0s-oci/"

  compartment_id = data.sops_file.credentials.data["tenancy_ocid"]
  #source_ocid     = "ocid1.image.oc1.eu-marseille-1.aaaaaaaaqihfeepadhdma7udc7n2vlfmienfwim4vl53dkftvfikrlxfi3ca"
  k0s_config_path = "${path.root}/k0sctl.yaml"
  k0s_version     = "v1.31.2+k0s.0"

  argocd_host = local.argocd_host

  projects = [{
    name = "svelte-template"
    source = {
      repo_url        = "https://github.com/CallePuzzle/villajilguero-oci-services"
      target_revision = "main"
      path            = "svelte-template"
      plugin          = "tanka-sops"
    }
    destination_namespace = "svelte-template"
  }]

  argocd_values = templatefile("${path.root}/argocd-values.yaml.tmpl", {
    argocd_host          = local.argocd_host
    github_client_id     = data.sops_file.argo.data["github.clientID"]
    github_client_secret = data.sops_file.argo.data["github.clientSecret"]
    sops_age_key         = data.sops_file.argo.data["sops_age_key"]
  })
}

output "public_ip" {
  value = module.oci-k0s.public_ip
}
