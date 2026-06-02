# villajilguero-oci-services

Kubernetes infrastructure-as-code project that deploys and manages a Nextcloud instance with supporting services on Oracle Cloud Infrastructure (OCI). Uses a GitOps approach with ArgoCD for continuous deployment.

## Main Components

- **Nextcloud**: Self-hosted cloud storage with MariaDB, Redis (Dragonfly), and S3-compatible object storage
- **MariaDB Operator**: Manages database instances, users, grants, and backups
- **Dragonfly Operator**: Redis-compatible in-memory data store
- **Grafana Monitoring**: Kubernetes monitoring stack with Prometheus, Loki, and Tempo
- **ArgoCD**: GitOps continuous delivery tool
- **cert-manager**: TLS certificate management
- **metrics-server**: Kubernetes metrics aggregation

## Technology Stack

| Tool | Purpose | Version |
|------|---------|---------|
| Terraform | Infrastructure provisioning | ~1.5+ |
| Jsonnet/Tanka | Kubernetes manifest generation | 0.20.0+ |
| k0s | Lightweight Kubernetes distribution | v1.31.2+k0s.0 |
| ArgoCD | GitOps/CD | 5.51.4+ |
| SOPS | Secret encryption | 3.8.1+ |
| Helm | Package management | 3.x |
| Oracle Cloud | Cloud provider | OCI |
| Backblaze B2 | S3-compatible object storage | - |

## Project Structure

```
.
├── jsonnet/                    # Jsonnet libraries for Kubernetes manifests
│   ├── main.libsonnet         # Main composition entry point
│   ├── base.libsonnet         # Base ArgoCD Application template
│   ├── vendor/                # Jsonnet dependencies (k8s-libsonnet 1.28)
│   ├── mariadb/               # MariaDB operator manifests
│   ├── nextcloud/             # Nextcloud application manifests
│   └── dragonfly/             # Dragonfly (Redis) manifests
├── manifests/                 # Generated/output manifests
│   ├── main.jsonnet          # Production manifest composition
│   ├── item.yaml             # ArgoCD Application wrapper
│   ├── dragonfly-operator/   # Static Dragonfly operator manifests
│   └── test/                 # Local testing manifests
├── k0s/                       # Production Terraform configuration
│   ├── main.tf               # OCI k0s cluster provisioning
│   ├── secrets.enc.yaml      # Encrypted secrets (SOPS)
│   └── credentials.enc.json  # Encrypted OCI credentials
├── jilguedev/                 # Development environment (Nextcloud AIO)
│   ├── main.tf               # Dev instance provisioning
│   └── ansible/              # Ansible automation for AIO deployment
└── test/                      # Integration testing environment
    ├── main.tf               # Kind cluster + ArgoCD setup
    ├── run.sh                # Test automation script
    └── kind-config.yaml.tpl  # Kind cluster template
```

## Environments

### Production (`k0s/`)
- OCI region: `eu-marseille-1`
- Workspace: `k0s`
- Full Kubernetes cluster with k0s
- GitOps deployment via ArgoCD

### Development (`jilguedev/`)
- OCI region: `eu-madrid-1`
- Workspace: `jilguedev`
- Standalone Ubuntu instance with Nextcloud All-in-One (AIO)
- Docker rootless + Caddy reverse proxy
- See [`jilguedev/README.md`](jilguedev/README.md) for details

### Integration Testing (`test/`)
- Local Kind cluster
- Terraform-based ArgoCD deployment test

## Quick Start

### Jsonnet/Tanka Workflow
```bash
cd jsonnet
jb install
# Generate manifests
jsonnet main.libsonnet
```

### Production Deployment
```bash
cd k0s
terraform init
terraform plan
terraform apply
```

### Development Deployment
```bash
cd jilguedev
terraform apply
cd ansible
poetry install
poetry run ansible-playbook -i inventory/oci_docker.yml playbook.yml
```

## Security

- All secrets are encrypted with SOPS using age keys
- TLS via cert-manager
- GitHub OAuth for ArgoCD authentication
- Private S3 buckets (Backblaze B2)
- Never commit plaintext secrets

## Documentation

- [Development environment (Nextcloud AIO)](jilguedev/README.md)
- [Agent guidelines](AGENTS.md)
