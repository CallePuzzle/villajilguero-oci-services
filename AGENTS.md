# AGENTS.md - villajilguero-oci-services

This document provides essential information for AI coding agents working on this project.

## Project Overview

This is a Kubernetes infrastructure-as-code project that deploys and manages a Nextcloud instance with supporting services on Oracle Cloud Infrastructure (OCI). The project uses a GitOps approach with ArgoCD for continuous deployment.

### Main Components

- **Nextcloud**: Self-hosted cloud storage solution with MariaDB, Redis (Dragonfly), and S3-compatible object storage
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
| Poetry | Python dependency management & virtualenv | 2.3.4+ |
| Ansible | Server configuration & provisioning | 13.6.0+ |

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
├── jilguedev/                 # Development environment
│   ├── main.tf               # Dev cluster provisioning
│   └── argocd-values.yaml.tmpl
└── test/                      # Integration testing environment
    ├── main.tf               # Kind cluster + ArgoCD setup
    ├── run.sh                # Test automation script
    └── kind-config.yaml.tpl  # Kind cluster template
```

## Key Configuration Files

### Jsonnet Dependencies
- `jsonnet/jsonnetfile.json`: Declares k8s-libsonnet 1.28 dependency
- `jsonnet/jsonnetfile.lock.json`: Locked dependency versions

### Terraform Workspaces
- `k0s/`: Production workspace "k0s" (eu-marseille-1 region)
- `jilguedev/`: Development workspace "jilguedev" (eu-madrid-1 region)
- `test/`: Local integration testing (Kind cluster)

### Secrets Management
All secrets are encrypted using SOPS with age keys:
- `*.enc.yaml` - YAML encrypted secrets
- `*.enc.json` - JSON encrypted secrets
- `.age-key.txt` - Local age private key (gitignored)

## Build and Deployment Commands

### Jsonnet/Tanka Workflow
```bash
cd jsonnet
# Install dependencies
jb install

# Generate manifests (example)
jsonnet main.libsonnet
```

### Local Testing with Kind
```bash
cd manifests/test

# Install dependencies
jb install
tk tool charts vendor

# Create cluster
./create-cluster.sh

# Deploy with Tanka
tk apply operators  # Deploy operators
tk apply local      # Deploy Nextcloud stack
```

### Integration Testing
```bash
cd test

# Run full test suite
./run.sh

# Or manually:
# 1. Create kind cluster with ingress
# 2. Deploy ArgoCD via Terraform
# 3. Access ArgoCD UI
```

### Production Deployment
```bash
# k0s environment
cd k0s
terraform init
terraform plan
terraform apply

# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  --template={{.data.password}} | base64 -d
```

### Ansible (Development Environment)

The `jilguedev/ansible` directory uses Poetry to manage a dedicated Python virtualenv with Ansible.

```bash
cd jilguedev/ansible

# Install dependencies (creates virtualenv automatically)
poetry install

# Run Ansible commands inside the virtualenv
poetry run ansible --version
poetry run ansible-playbook -i inventory/oci_podman.yml playbook.yml

# Or spawn a shell with the virtualenv activated
poetry shell
ansible-playbook -i inventory/oci_podman.yml playbook.yml
```

**Note**: Do not commit the virtualenv directory. `pyproject.toml` and `poetry.lock` should be committed to ensure reproducible builds.

## Code Organization

### Jsonnet Library Structure

The project follows a modular Jsonnet composition pattern:

1. **base.libsonnet**: Defines the base ArgoCD Application CRD structure with:
   - Helm chart support
   - Path-based manifests
   - Values injection

2. **main.libsonnet**: Composes all application components:
   - Database layer (MariaDB)
   - Cache layer (Dragonfly)
   - Application layer (Nextcloud)
   - Operators and monitoring

3. **Component libraries** (mariadb/, nextcloud/, dragonfly/):
   - Each defines Kubernetes resources
   - Parameters exposed via `params::`
   - Can be imported and customized

### Parameter Inheritance Pattern
```jsonnet
{
  params:: {
    namespace: 'default',
    // Default values here
  },
  // Resource definitions using $.params
}
```

### Import Paths
- Use relative paths for local imports: `import './base.libsonnet'`
- Use vendor paths for external libs: `import 'github.com/jsonnet-libs/k8s-libsonnet/1.28/main.libsonnet'`

## Testing Strategy

### Unit Testing
- Jsonnet validation via `jsonnet` CLI
- Tanka environments in `manifests/test/`

### Integration Testing
- Kind clusters for local validation
- Terraform-based ArgoCD deployment test
- Full application stack deployment

### Production Testing
- Separate Terraform workspace
- GitOps-based rollout via ArgoCD

## Security Considerations

### Secret Management
- **All secrets MUST be encrypted with SOPS**
- Never commit plaintext secrets
- Use age keys for encryption (not PGP)
- Public keys can be embedded in templates

### Encryption Commands
```bash
# Encrypt secrets
sops -e --age <public-key> --output-type json secrets.json > secrets.enc.json
sops -e --age <public-key> secrets.yaml > secrets.enc.yaml

# Decrypt for editing
sops -d secrets.enc.yaml
```

### Network Security
- TLS via cert-manager
- GitHub OAuth for ArgoCD authentication
- Private S3 buckets (Backblaze B2)

### RBAC
- ArgoCD configured with GitHub organization auth
- org-admin role for CallePuzzle organization members

## Development Conventions

### Jsonnet Style
- Use `::` for hidden fields (parameters)
- Use `+` for composition/mixin pattern
- Error assertions for required parameters: `error 'name is required'`
- Consistent indentation: 2 spaces

### Git Workflow
- Main branch: `main`
- Encrypted secrets track their plaintext counterparts
- Jsonnet vendor directory is committed

### Naming Conventions
- Files: `kebab-case.libsonnet`
- Resources: derived from component name
- Namespaces: explicit in params, default to 'default'

## Common Operations

### Adding a New Component
1. Create new file in `jsonnet/` or appropriate subdirectory
2. Define parameters with `params::`
3. Export Kubernetes resources
4. Import in `main.libsonnet` and compose

### Updating Dependencies
```bash
cd jsonnet
jb update
```

### Regenerating Vendor
```bash
cd jsonnet
rm -rf vendor/
jb install
```

### Adding New Secrets
1. Create plaintext `secrets.json` or `secrets.yaml`
2. Encrypt with SOPS
3. Update `.gitignore` if needed
4. Reference in Jsonnet via `import 'secrets.json'`

## Troubleshooting

### Common Issues

**Jsonnet import errors**: Check vendor directory exists, run `jb install`

**SOPS decryption fails**: Ensure `SOPS_AGE_KEY` environment variable is set

**Terraform provider errors**: Check OCI credentials are properly encrypted/decrypted

**ArgoCD sync failures**: Verify namespace exists or `CreateNamespace=true` sync option is set

## Resources

- [k8s-libsonnet docs](https://github.com/jsonnet-libs/k8s-libsonnet)
- [Tanka documentation](https://tanka.dev/)
- [Jsonnet language reference](https://jsonnet.org/)
- [SOPS documentation](https://github.com/getsops/sops)
- [k0s documentation](https://docs.k0sproject.io/)
