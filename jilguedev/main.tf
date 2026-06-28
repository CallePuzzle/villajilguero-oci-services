variable "ssh_private_key_path" {
  description = "Path to the SSH private key used for OCI instance access and Ansible"
  default     = "~/.ssh/id_ed25519"
}

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
      version = "8.12.0"
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

  ssh_public_key = file("${var.ssh_private_key_path}.pub")

  additional_security_list_rules = [
    {
      protocol = "6"
      source   = "0.0.0.0/0"
      tcp_options = {
        min = 80
        max = 80
      }
    },
    {
      protocol = "6"
      source   = "0.0.0.0/0"
      tcp_options = {
        min = 443
        max = 443
      }
    },
    {
      protocol = "17"
      source   = "0.0.0.0/0"
      udp_options = {
        min = 443
        max = 443
      }
    },
  ]
}

resource "local_file" "ansible_inventory" {
  content = <<-EOT
all:
  children:
    docker_servers:
      hosts:
        ${module.oci-k0s.public_ip}:
          ansible_user: ubuntu
          ansible_ssh_private_key_file: ${var.ssh_private_key_path}
          docker_user: ubuntu
  EOT

  filename = "${path.module}/ansible/inventory/oci_docker.yml"
}

output "public_ip" {
  value = module.oci-k0s.public_ip
}

output "private_ip" {
  value = module.oci-k0s.private_ip
}
