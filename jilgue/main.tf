variable "ssh_private_key_path" {
  description = "Path to the SSH private key used for OCI instance access and Ansible"
  default     = "~/.ssh/id_ed25519"
}

terraform {
  cloud {
    organization = "villajilguero"

    workspaces {
      name = "jilgue"
    }
  }
  required_providers {
    sops = {
      source  = "carlpett/sops"
      version = "1.1.1"
    }
    oci = {
      source = "oracle/oci"
      # ~> 9.0: requerido por el módulo v1.6.0 (>= 9.0.0). jilguedev ya corre
      # 9.x en producción.
      version = "~> 9.0"
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

module "oci-aio" {
  source = "git::https://github.com/CallePuzzle/terraform-module-k0s-oci?ref=v1.7.2"
  # source = "../../terraform-module-k0s-oci/"

  name = "aio"

  compartment_id = data.sops_file.credentials.data["tenancy_ocid"]

  enable_k0s = false

  ssh_public_key = file("${var.ssh_private_key_path}.pub")

  # Passthrough TCP: Caddy termina TLS en la instancia (host network, 443).
  # Sin este pin, el default del módulo (80, para TLS in-cluster) movería el
  # backend y el health check del listener 443 al puerto 80 y provocaría un
  # redirect loop de Caddy a través del LB.
  https_backend_port = 443

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
        ${module.oci-aio.public_ip}:
          ansible_user: ubuntu
          ansible_ssh_private_key_file: ${var.ssh_private_key_path}
          docker_user: ubuntu
  EOT

  filename = "${path.module}/ansible/inventory/oci_docker.yml"
}

output "public_ip" {
  value = module.oci-aio.public_ip
}

output "private_ip" {
  value = module.oci-aio.private_ip
}
