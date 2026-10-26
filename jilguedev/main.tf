variable "ssh_private_key_path" {
  description = "Path to the SSH private key used for OCI instance access and k0sctl"
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
      source = "oracle/oci"
      # ~> 9.0: requerido por el módulo v1.4.1. La 8.12.0 además rechazaba
      # versioning = "Suspended" en el create del bucket de backups.
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

data "sops_file" "secrets" {
  source_file = "secrets.enc.yaml"
}

locals {
  tenancy_ocid    = data.sops_file.credentials.data["tenancy_ocid"]
  argocd_host     = "argocd.callepuzzle.com"
  github_org_name = "CallePuzzle"
}

provider "oci" {
  tenancy_ocid = data.sops_file.credentials.data["tenancy_ocid"]
  user_ocid    = data.sops_file.credentials.data["user_ocid"]
  fingerprint  = data.sops_file.credentials.data["fingerprint"]
  private_key  = data.sops_file.credentials.data["private_key"]
  region       = "eu-madrid-1"
}

module "oci-k0s" {
  source = "git::https://github.com/CallePuzzle/terraform-module-k0s-oci?ref=v1.4.3"
  # source = "../../terraform-module-k0s-oci/"

  compartment_id = local.tenancy_ocid
  environment    = "dev"

  enable_k0s           = true
  k0s_config_path      = "${path.root}/k0sctl.yaml"
  ssh_private_key_path = var.ssh_private_key_path
  ssh_public_key       = file("${var.ssh_private_key_path}.pub")

  # CNPG necesita la storage class openebs-hostpath. Sin cert-manager: el TLS lo
  # termina Cloudflare (proxy + Full sin strict) y el LB queda en passthrough
  # TCP hacia Traefik con su certificado self-signed.
  enable_openebs      = true
  enable_cert_manager = false

  # Passthrough TCP: el backend del listener 443 es Traefik (websecure), no un
  # puerto HTTP del LB.
  https_backend_port = 443

  argocd_host = local.argocd_host

  projects = [
    {
      name = "app-of-apps-dev"
      source = {
        repo_url        = "git@github.com:CallePuzzle/villajilguero-oci-services.git"
        target_revision = "main"
        path            = "jilguedev/app-of-apps"
        plugin          = "tanka-sops"
      }
      destination_namespace        = "callepuzzle-dev"
      auto_sync                    = true
      extra_destination_namespaces = ["cnpg-system"]
      # Whitelists cluster-scope para el operador CloudNativePG (CRDs, RBAC y
      # webhooks), como en Zytera pro.
      extra_cluster_resource_whitelist = [
        { group = "admissionregistration.k8s.io", kind = "MutatingWebhookConfiguration" },
        { group = "admissionregistration.k8s.io", kind = "ValidatingWebhookConfiguration" },
        { group = "apiextensions.k8s.io", kind = "CustomResourceDefinition" },
        { group = "rbac.authorization.k8s.io", kind = "ClusterRole" },
        { group = "rbac.authorization.k8s.io", kind = "ClusterRoleBinding" },
      ]
      source_repos = [
        "git@github.com:CallePuzzle/y-tu-que-compras.git",
        "https://cloudnative-pg.io/charts",
      ]
    },
  ]

  argocd_values = templatefile("${path.root}/argocd-values.yaml.tmpl", {
    argocd_host           = local.argocd_host
    github_org_name       = local.github_org_name
    github_client_id      = data.sops_file.secrets.data["github_client_id"]
    github_client_secret  = data.sops_file.secrets.data["github_client_secret"]
    sops_age_key          = data.sops_file.secrets.data["sops_age_key"]
    infra_repo_deploy_key = data.sops_file.secrets.data["infra_repo_deploy_key"]
  })
}

output "public_ip" {
  value = module.oci-k0s.public_ip
}

output "private_ip" {
  value = module.oci-k0s.private_ip
}

output "lb_public_ip" {
  description = "IP pública del LB: destino de los registros DNS en Cloudflare (proxied)"
  value       = module.oci-k0s.lb_public_ip
}

# --- Backups de ytqc-db en OCI Object Storage (API S3-compatible, barman) ---

locals {
  db_backup_bucket = "jilguedev-db-backups"
}

data "oci_objectstorage_namespace" "this" {}

// Usuario IAM dedicado: nunca la Customer Secret Key del usuario admin.
// Los usuarios viven en la raíz de la tenancy (no en compartments hijos).
resource "oci_identity_user" "db_backup" {
  compartment_id = local.tenancy_ocid
  name           = "jilguedev-db-backup"
  description    = "Acceso S3-compatible para backups de ytqc-db"
  email          = "jilguedev-db-backup@callepuzzle.com" # requerido por IAM identity domains
}

resource "oci_identity_group" "db_backup" {
  compartment_id = oci_identity_user.db_backup.compartment_id
  name           = "jilguedev-db-backup"
  description    = "Backups de ytqc-db (jilguedev)"
}

resource "oci_identity_user_group_membership" "db_backup" {
  group_id = oci_identity_group.db_backup.id
  user_id  = oci_identity_user.db_backup.id
}

// El compartment es la tenancy: `in tenancy` (sin nombre) + filtro por bucket.
resource "oci_identity_policy" "db_backup" {
  compartment_id = oci_identity_user.db_backup.compartment_id
  name           = "jilguedev-db-backup"
  description    = "Acceso al bucket de backups de ytqc-db"
  statements = [
    "Allow group 'jilguedev-db-backup' to read buckets in tenancy where target.bucket.name = '${local.db_backup_bucket}'",
    "Allow group 'jilguedev-db-backup' to manage objects in tenancy where target.bucket.name = '${local.db_backup_bucket}'",
  ]
}

// La key secreta solo se devuelve en la creación (queda en el tfstate, en
// Terraform Cloud). El Access Key ID S3 es el OCID de la credencial.
resource "oci_identity_customer_secret_key" "db_backup" {
  user_id      = oci_identity_user.db_backup.id
  display_name = "s3-compat-jilguedev-db"
}

// Crear el bucket ANTES de que el Cluster lo referencie: barman 3.16+ ya no
// crea buckets automáticamente.
// Sin versionado: la API de OCI solo admite Enabled/Disabled en CreateBucket
// ("Suspended" es un valor de update, solo aplicable a buckets que estuvieron
// Enabled), y Enabled no nos vale porque OCI no soporta reglas lifecycle sobre
// versiones no actuales: dejaría delete markers y versiones viejas acumulándose
// sin purga. Con Disabled los deletes son permanentes y la retención de barman
// es el único mecanismo de borrado.
resource "oci_objectstorage_bucket" "db_backups" {
  compartment_id = local.tenancy_ocid
  name           = local.db_backup_bucket
  namespace      = data.oci_objectstorage_namespace.this.namespace
  access_type    = "NoPublicAccess"
  storage_tier   = "Standard"
  versioning     = "Disabled"
}

# Credenciales S3 para los secrets de Tanka (jilguedev/app-of-apps/dev/secrets.enc)
output "db_backup_access_key_id" {
  value = oci_identity_customer_secret_key.db_backup.id
}

output "db_backup_secret_access_key" {
  value     = oci_identity_customer_secret_key.db_backup.key # solo legible en create
  sensitive = true
}
