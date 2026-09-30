# villajilguero-oci-services

Infrastructure-as-code project that deploys and manages Nextcloud All-in-One (AIO) instances on Oracle Cloud Infrastructure (OCI), provisioned with Terraform and configured with Ansible.

## Main Components

- **Nextcloud AIO**: All-in-One Nextcloud deployment (mastercontainer + Apache)
- **Caddy**: Reverse proxy in host network mode with automatic HTTPS (ports 80/443, HTTP/3)
- **Docker rootless**: Containers run without root privileges
- **BorgBackup**: Integrated AIO backups with automated daily runs
- **Backblaze B2**: Offsite sync of the Borg backup repository
- **OS hardening**: UFW, fail2ban, unattended-upgrades

## Technology Stack

| Tool | Purpose | Version |
|------|---------|---------|
| Terraform | OCI instance provisioning (`terraform-module-k0s-oci` with `enable_k0s = false`) | ~1.5+ |
| Ansible | Server configuration & AIO deployment | 13.6.0+ |
| Poetry | Python dependency management & virtualenv | 2.3.4+ |
| Molecule | Role testing (functional + B2 restore scenarios) | - |
| SOPS | Secret encryption (age keys) | 3.8.1+ |
| Oracle Cloud | Cloud provider (Ubuntu 24.04, VM.Standard.A1.Flex) | - |
| Backblaze B2 | S3-compatible object storage for backups | - |

## Project Structure

```
.
├── jilgue/                      # Production environment (Nextcloud AIO)
│   ├── main.tf                  # OCI instance provisioning
│   ├── credentials.enc.json     # Encrypted OCI credentials (SOPS)
│   ├── AGENTS.md                # Operational guidelines
│   └── ansible/                 # Ansible automation
│       ├── playbook.yml         # Main playbook
│       ├── playbooks/           # Auxiliary playbooks (B2 backup verification)
│       └── roles/nextcloud_aio/ # AIO role (compose, Caddy, backup timers)
│           └── molecule/        # Molecule scenarios (aio-functional, b2-restore)
├── jilguedev/                   # Development environment (Nextcloud AIO)
│   ├── main.tf                  # OCI instance provisioning
│   ├── credentials.enc.json     # Encrypted OCI credentials (SOPS)
│   ├── secrets.enc.yaml         # Encrypted secrets (SOPS)
│   ├── AGENTS.md                # Operational guidelines
│   └── ansible/                 # Ansible automation (same structure as jilgue)
└── docs/plans/                  # Design and planning documents
```

## Environments

### Production (`jilgue/`)
- OCI region: `eu-madrid-1`
- Nextcloud: `https://aio.callepuzzle.com`
- Ubuntu 24.04 instance with Docker rootless + Caddy reverse proxy
- Daily Borg backup (systemd user timer) + daily Backblaze B2 sync (cron)
- See [`jilgue/README.md`](jilgue/README.md) for details

### Development (`jilguedev/`)
- OCI region: `eu-madrid-1`
- Standalone Ubuntu instance with Nextcloud All-in-One (AIO)
- Docker rootless + Caddy reverse proxy
- See [`jilguedev/README.md`](jilguedev/README.md) for details

## Quick Start

### Deployment (per environment)
```bash
cd jilgue   # or jilguedev
terraform apply
cd ansible
poetry install
poetry run ansible-playbook -i inventory/oci_docker.yml playbook.yml
```

### Testing (Molecule)
```bash
cd jilgue/ansible/roles/nextcloud_aio
poetry install

# Functional AIO test
poetry run molecule test --scenario-name aio-functional

# B2 backup restore verification (backup in tmp/nextcloud-aio-borg-backup/,
# passphrase in .borg.txt — both gitignored)
poetry run molecule test --scenario-name b2-restore
```

### Backup verification (local playbook)
```bash
cd jilgue/ansible
poetry run ansible-playbook playbooks/verify-b2-backup.yml
```

## Security

- All secrets are encrypted with SOPS using age keys; never commit plaintext secrets
- UFW: only ports 22 (SSH), 80 (HTTP), and 443 (HTTPS) open publicly; AIO admin (8080) only via SSH tunnel
- fail2ban protects SSH against brute-force attacks
- unattended-upgrades for automatic OS security updates
- Docker rootless reduces the attack surface

## Documentation

- [Production environment (Nextcloud AIO)](jilgue/README.md)
- [Development environment (Nextcloud AIO)](jilguedev/README.md)
- [Agent guidelines](AGENTS.md)

## License

See [LICENSE](LICENSE).
