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
    oci = {
      source  = "oracle/oci"
      version = "6.18.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
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

module "oci-k0s" {
  source = "../../terraform-module-k0s-oci/"

  compartment_id = data.sops_file.credentials.data["tenancy_ocid"]

  enable_k0s = false

  ssh_public_key = file("~/.ssh/id_ed25519.pub")
}

resource "local_file" "ansible_inventory" {
  content = <<-EOT
all:
  children:
    podman_servers:
      hosts:
        ${module.oci-k0s.public_ip}:
          ansible_user: ubuntu
          ansible_ssh_private_key_file: ~/.ssh/id_ed25519
          podman_user: ubuntu
          podman_uid: 1000
  EOT

  filename = "${path.module}/ansible/inventory/oci_podman.yml"
}

output "public_ip" {
  value = module.oci-k0s.public_ip
}

output "private_ip" {
  value = module.oci-k0s.private_ip
}
