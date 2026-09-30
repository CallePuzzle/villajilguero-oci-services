# jilgue — Nextcloud AIO Production Environment

Production environment for Nextcloud All-in-One (AIO) deployed on an OCI Ubuntu instance with rootless Docker.

## Architecture

- **OCI Instance**: Ubuntu 24.04 (VM.Standard.A1.Flex) provisioned via Terraform (`terraform-module-k0s-oci` with `enable_k0s = false`).
- **Docker**: Rootless mode with socket at `/run/user/<uid>/docker.sock`.
- **Reverse Proxy**: Caddy in `network_mode: host` listening on 80/443 (TCP+UDP for HTTP/3) and proxying to `localhost:11000`.
- **Nextcloud AIO**: Mastercontainer in `network_mode: bridge` with the admin interface restricted to `127.0.0.1:8080`.

## Initial Deployment

```bash
cd jilgue
terraform apply
cd ansible
poetry install
poetry run ansible-playbook -i inventory/oci_docker.yml playbook.yml
```

## Access

- **Nextcloud**: `https://aio.callepuzzle.com`
- **AIO Admin**: `https://<public-ip>:8080` — restricted via UFW; use an SSH tunnel if needed:
  ```bash
  ssh -L 8080:localhost:8080 ubuntu@<public-ip>
  ```

## Configuration

Default values are defined in `ansible/roles/nextcloud_aio/defaults/main.yml` and can be overridden in `ansible/group_vars/docker_servers.yml`.

| Variable | Description | Default |
|----------|-------------|---------|
| `nextcloud_aio_domain` | Public domain for Nextcloud | `aio.callepuzzle.com` |
| `nextcloud_aio_datadir` | Host path for data (empty = Docker volume) | `""` |
| `nextcloud_aio_memory_limit` | PHP memory limit | `2048M` |
| `nextcloud_aio_upload_limit` | Upload limit | `16G` |
| `nextcloud_aio_max_time` | PHP max execution time | `3600` |
| `nextcloud_aio_borg_retention_policy` | BorgBackup retention policy | `--keep-within=7d --keep-weekly=4 --keep-monthly=6` |
| `nextcloud_aio_log_level` | AIO log level | `warn` |
| `nextcloud_aio_backup_enabled` | Enable backup timer | `true` |
| `nextcloud_aio_backup_time` | Daily backup time | `02:00` |
| `nextcloud_aio_b2_sync_enabled` | Enable daily sync of the Borg backup to Backblaze B2 | `true` |
| `nextcloud_aio_b2_sync_time` | Daily B2 sync time | `05:00` |
| `nextcloud_aio_b2_version` | Backblaze B2 CLI version to install | `4.7.1` |
| `nextcloud_aio_b2_bucket` | Destination B2 bucket for the sync | `b2://callepuzzle-nextcloud-borg-backup/` |
| `nextcloud_aio_enable_ufw` | Enable UFW | `true` |
| `nextcloud_aio_enable_fail2ban` | Enable fail2ban | `true` |
| `nextcloud_aio_enable_unattended_upgrades` | Enable unattended-upgrades | `true` |

> ⚠️ `NEXTCLOUD_DATADIR` can only be set **before the first startup**. Changing it later requires recreating the installation.

## Docker Compose Stack

The Ansible role generates a `docker-compose.yml` with two services:

### nextcloud-aio-mastercontainer
- Image: `ghcr.io/nextcloud-releases/all-in-one:latest`
- Exposes `127.0.0.1:8080` for the AIO admin interface
- Mounts the rootless Docker socket (read-only)
- Environment variables control Apache binding, PHP limits, backups, and logging

### caddy
- Image: `caddy:alpine`
- Runs in `network_mode: host`
- Serves on ports 80/443 and proxies to the AIO Apache container
- Provides `.well-known/carddav` and `.well-known/caldav` redirects

### Caddyfile
```
aio.callepuzzle.com {
  header Strict-Transport-Security max-age=31536000
  reverse_proxy localhost:11000
  redir /.well-known/carddav /remote.php/dav/ 301
  redir /.well-known/caldav /remote.php/dav/ 301
}
```

## Systemd Services

### docker-compose-nextcloud.service
User-scoped systemd service that starts the compose stack after the Docker socket is available:
```bash
systemctl --user status docker-compose-nextcloud
journalctl --user -u docker-compose-nextcloud
```

### nextcloud-aio-backup.timer
Daily timer (default 02:00) that triggers a backup with automatic updates:
```bash
systemctl --user status nextcloud-aio-backup.timer
```

The backup service runs:
```bash
docker exec --env DAILY_BACKUP=1 --env AUTOMATIC_UPDATES=1 nextcloud-aio-mastercontainer /daily-backup.sh
```

### Backblaze B2 sync (cron)
Daily cron (default 05:00, three hours after the Borg backup) that syncs `nextcloud_aio_backup_dir` to the configured B2 bucket:
```bash
/usr/local/bin/b2 sync /home/ubuntu/nextcloud-aio-backups b2://callepuzzle-nextcloud-borg-backup/
```
Logs go to `/home/ubuntu/nextcloud-aio-b2-sync.log`. The `b2` CLI is installed automatically by Ansible but must be authorized manually and out-of-band (`b2 account authorize`) since credentials aren't yet managed via SOPS.

## Backup and Restore

AIO includes integrated BorgBackup managed from the AIO admin UI (`https://localhost:8080`).

- **Automated**: Daily via the systemd user timer with `AUTOMATIC_UPDATES=1`.
- **Offsite sync**: Daily cron syncs the local Borg repository to Backblaze B2 (see above).
- **Remote**: Configure a Borg remote repository via SSH from the AIO UI. AIO generates an SSH keypair automatically. Append-only mode is recommended for ransomware protection.
- **Restore**: Only the Borg backup and the encryption password are needed. Full restore is done from the AIO UI.

### Verifying the B2 backup

To confirm the copy synced from Backblaze B2 is valid and contains the expected data:

1. **Molecule (recommended)**: runs the verification inside a disposable Podman container:

```bash
cd jilgue/ansible/roles/nextcloud_aio
# Make sure the backup is in tmp/nextcloud-aio-borg-backup/
# and the passphrase is in .borg.txt (both gitignored)
poetry run molecule test --scenario-name b2-restore
```

2. **Local playbook**: for quick checks without a container:

```bash
cd jilgue/ansible
poetry run ansible-playbook playbooks/verify-b2-backup.yml
```

Both tests:
- Run `borg check` against the local repository.
- List the available archives.
- Extract the PostgreSQL SQL dump.
- Verify that the `cesar` and `nuria` users exist in `oc_users`.

## Security

- **UFW**: Only ports 22 (SSH), 80 (HTTP), and 443 (HTTPS) are open publicly. Port 8080 (AIO admin) is denied from outside.
- **fail2ban**: Protects SSH against brute-force attacks.
- **unattended-upgrades**: Automatic OS security updates.
- **Docker rootless**: Reduces attack surface; containers run without root privileges.
- **Log driver**: Docker uses `log-driver: local` to prevent uncontrolled log growth.
- **Trusted proxies**: `NEXTCLOUD_TRUSTED_PROXIES=127.0.0.1` configured for Caddy in host network.

## Docker Daemon

The rootless daemon is configured with:
- `log-driver: local`
- `live-restore: false` (rootless does not support live-restore)

## Operational Commands

```bash
# View AIO mastercontainer logs
docker logs nextcloud-aio-mastercontainer

# View Caddy logs
docker logs caddy

# Restart the compose stack
systemctl --user restart docker-compose-nextcloud

# Trigger a backup manually
systemctl --user start nextcloud-aio-backup.service

# Check backup timer status
systemctl --user list-timers nextcloud-aio-backup.timer
```

## File Layout

```
jilgue/
├── main.tf                          # Terraform instance provisioning
├── credentials.enc.json             # Encrypted OCI credentials
├── ansible/
│   ├── ansible.cfg                  # Ansible configuration
│   ├── playbook.yml                 # Main Ansible playbook
│   ├── pyproject.toml               # Poetry dependencies
│   ├── poetry.lock
│   ├── inventory/
│   │   └── oci_docker.yml           # Generated by Terraform
│   ├── group_vars/
│   │   └── docker_servers.yml       # Host variables
│   ├── playbooks/
│   │   └── verify-b2-backup.yml     # Local B2 backup verification playbook
│   └── roles/nextcloud_aio/
│       ├── defaults/main.yml        # Default role variables
│       ├── tasks/main.yml           # Role tasks
│       ├── molecule/                # Molecule scenarios (functional test, B2 restore)
│       └── templates/
│           ├── docker-compose.yml.j2
│           ├── Caddyfile.j2
│           ├── docker-compose.service.j2
│           ├── nextcloud-aio-backup.service.j2
│           └── nextcloud-aio-backup.timer.j2
```
