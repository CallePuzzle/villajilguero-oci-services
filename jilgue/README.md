# jilgue — Nextcloud AIO Production Environment

Production environment for Nextcloud All-in-One (AIO) deployed on an OCI Ubuntu instance with rootless Docker.

## Architecture

- **OCI Instance**: Ubuntu 24.04 (VM.Standard.A1.Flex) provisioned via Terraform (`terraform-module-k0s-oci` with `enable_k0s = false`).
- **Ansible roles**: `docker_host` (host base: rootless Docker, OS hardening, Backblaze B2 CLI), `caddy` (reverse proxy with its own compose project and per-app site snippets), and the apps `nextcloud_aio` and `wallabag` (disabled by default). The playbook runs them in that order.
- **Docker**: Rootless mode with socket at `/run/user/<uid>/docker.sock`.
- **Reverse Proxy**: Caddy in `network_mode: host` listening on 80/443 (TCP+UDP for HTTP/3) and proxying to `localhost:11000`. Its compose project and base Caddyfile are managed by the `caddy` role; each app role writes its site snippet into the sites directory (e.g. `nextcloud.caddy`, `wallabag.caddy`) and restarts the `caddy` container when it changes.
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
- **Wallabag** (not deployed until `wallabag_enabled: true` in group_vars): `https://wallabag.callepuzzle.com`. The image's default login is `wallabag` / `wallabag` — **change the password after the first login** (Config → My account) and create individual users; public registration ships disabled.

## Configuration

Default values are defined in `ansible/roles/docker_host/defaults/main.yml`, `ansible/roles/caddy/defaults/main.yml`, `ansible/roles/nextcloud_aio/defaults/main.yml` and `ansible/roles/wallabag/defaults/main.yml`, and can be overridden in `ansible/group_vars/docker_servers.yml`.

**`docker_host` role** (host base):

| Variable | Description | Default |
|----------|-------------|---------|
| `docker_host_user` | User that runs rootless Docker (shared with app roles) | `ubuntu` |
| `docker_host_storage_driver` | Docker storage driver (empty = default; `fuse-overlayfs` in nested environments) | `""` |
| `docker_host_enable_ufw` | Enable UFW | `true` |
| `docker_host_enable_fail2ban` | Enable fail2ban | `true` |
| `docker_host_enable_unattended_upgrades` | Enable unattended-upgrades | `true` |
| `docker_host_b2_cli_enabled` | Install the Backblaze B2 CLI (used by app cron jobs) | `true` |
| `docker_host_b2_version` | Backblaze B2 CLI version to install | `4.7.1` |

**`caddy` role** (reverse proxy):

| Variable | Description | Default |
|----------|-------------|---------|
| `caddy_compose_path` | Caddy compose project directory | `/home/ubuntu/caddy` |
| `caddy_sites_path` | Sites directory imported by the base Caddyfile (derived; exported as a fact by the role) | `{{ caddy_compose_path }}/sites` |
| `caddy_container_name` | Container app roles restart after changing a snippet | `caddy` |
| `caddy_image` | Caddy image | `caddy:alpine` |

The role exports `caddy_sites_path` and `caddy_container_name` as facts for the app roles (see the role README). The base Caddyfile imports `/etc/caddy/sites/*.caddy` and includes a `:80` placeholder so the config stays valid while no app snippet exists.

**`nextcloud_aio` role** (app):

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
| `nextcloud_aio_b2_sync_enabled` | Enable daily sync of the Borg backup to Backblaze B2 (requires `docker_host_b2_cli_enabled`) | `true` |
| `nextcloud_aio_b2_sync_time` | Daily B2 sync time | `05:00` |
| `nextcloud_aio_b2_bucket` | Destination B2 bucket for the sync | `b2://callepuzzle-nextcloud-borg-backup/` |

**`wallabag` role** (app, disabled by default):

| Variable | Description | Default |
|----------|-------------|---------|
| `wallabag_enabled` | Deploy the app and its backup crons | `false` |
| `wallabag_compose_path` | Wallabag compose project directory | `/home/ubuntu/wallabag` |
| `wallabag_compose_file` | Compose file name | `docker-compose.yml` |
| `wallabag_domain` | Public domain for Wallabag | `wallabag.callepuzzle.com` |
| `wallabag_image` | Official multi-arch image (native arm64), pinned to the minor tag | `wallabag/wallabag:2.6` |
| `wallabag_port` | Loopback port Caddy proxies to (8080 and 11000 are already taken) | `8081` |
| `wallabag_ip_binding` | IP the port binds to (don't expose outside tests) | `127.0.0.1` |
| `wallabag_locale` | UI language | `en` |
| `wallabag_secret` | App secret for security tokens (empty = image's public default) | `""` |
| `wallabag_data_path` | Host bind mount holding the SQLite DB | `{{ wallabag_compose_path }}/data` |
| `wallabag_backup_dir` | Local directory for the SQLite snapshot synced to B2 | `/home/ubuntu/wallabag-backups` |
| `wallabag_backup_file` | Snapshot file name | `wallabag.sqlite` |
| `wallabag_backup_enabled` | Enable the daily SQLite snapshot | `true` |
| `wallabag_backup_time` | Daily SQLite snapshot time | `04:00` |
| `wallabag_b2_sync_enabled` | Enable daily sync of the snapshot to Backblaze B2 (requires `docker_host_b2_cli_enabled`) | `true` |
| `wallabag_b2_sync_time` | Daily B2 sync time | `04:30` |
| `wallabag_b2_bucket` | Destination B2 bucket (subfolder of the AIO bucket) | `b2://callepuzzle-nextcloud-borg-backup/wallabag/` |

> ⚠️ `NEXTCLOUD_DATADIR` can only be set **before the first startup**. Changing it later requires recreating the installation.

## Docker Compose Stack

The Ansible roles generate these compose projects (the wallabag one only when `wallabag_enabled: true`):

### nextcloud-aio (role `nextcloud_aio`)

#### nextcloud-aio-mastercontainer
- Image: `ghcr.io/nextcloud-releases/all-in-one:latest`
- Exposes `127.0.0.1:8080` for the AIO admin interface
- Mounts the rootless Docker socket (read-only)
- Environment variables control Apache binding, PHP limits, backups, and logging

### caddy (role `caddy`)

#### caddy
- Image: `caddy:alpine`
- Runs in `network_mode: host`, serving on ports 80/443
- Mounts the base Caddyfile and the sites directory (read-only) from its own compose project, plus the named volumes `caddy_config` / `caddy_data` (the same ones the pre-#38 AIO compose used, so Let's Encrypt certificates carry over untouched)

### wallabag (role `wallabag`, only when `wallabag_enabled: true`)

#### wallabag
- Image: `wallabag/wallabag:2.6` (official, multi-arch with native arm64)
- Exposes `127.0.0.1:8081` only; Caddy proxies the site to it
- SQLite DB on a host bind mount (`wallabag_data_path` → `/var/www/wallabag/data`, so the DB is at `<path>/db/wallabag.sqlite`); entry images in the named volume `wallabag_images` (re-downloadable content, not backed up)

### Base Caddyfile (`caddy` role)

Imports the per-app snippets and keeps a `:80` placeholder so the config stays valid while no snippet exists:

```
import /etc/caddy/sites/*.caddy

:80 {
  respond "Service starting up" 503
}
```

### Nextcloud site snippet (role `nextcloud_aio`, written to `sites/nextcloud.caddy`)

```
aio.callepuzzle.com {
  header Strict-Transport-Security max-age=31536000
  reverse_proxy localhost:11000
  redir /.well-known/carddav /remote.php/dav/ 301
  redir /.well-known/caldav /remote.php/dav/ 301
}
```

The role restarts the `caddy` container whenever the snippet changes (Caddy only reads its config at startup).

### Wallabag site snippet (role `wallabag`, written to `sites/wallabag.caddy`)

```
wallabag.callepuzzle.com {
  header Strict-Transport-Security max-age=31536000
  reverse_proxy localhost:8081
}
```

## Systemd Services

### docker-compose-caddy.service
User-scoped systemd service that starts the Caddy compose project after the Docker socket is available:
```bash
systemctl --user status docker-compose-caddy
journalctl --user -u docker-compose-caddy
```

### docker-compose-nextcloud.service
User-scoped systemd service that starts the compose stack after the Docker socket is available:
```bash
systemctl --user status docker-compose-nextcloud
journalctl --user -u docker-compose-nextcloud
```

### docker-compose-wallabag.service
User-scoped systemd service that starts the Wallabag compose stack after the Docker socket is available:
```bash
systemctl --user status docker-compose-wallabag
journalctl --user -u docker-compose-wallabag
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
Logs go to `/home/ubuntu/nextcloud-aio-b2-sync.log`. The `b2` CLI is installed automatically by the `docker_host` role (`docker_host_b2_cli_enabled`) but must be authorized manually and out-of-band (`b2 account authorize`) since credentials aren't yet managed via SOPS.

### Wallabag backup (cron, only when `wallabag_enabled: true`)
Two daily crons staggered between the AIO Borg backup (02:00) and its B2 sync (05:00) so the two `b2` processes never overlap:

- **04:00** — consistent SQLite snapshot via the online backup API:
  ```bash
  /usr/bin/sqlite3 /home/ubuntu/wallabag/data/db/wallabag.sqlite ".backup '/home/ubuntu/wallabag-backups/wallabag.sqlite'"
  ```
- **04:30** — sync of the snapshot directory to the existing B2 bucket (subfolder `wallabag/`):
  ```bash
  /usr/local/bin/b2 sync /home/ubuntu/wallabag-backups b2://callepuzzle-nextcloud-borg-backup/wallabag/
  ```

The snapshot file is overwritten daily; `b2 sync` keeps previous versions of changed files on the bucket, so history survives without timestamped local copies. Logs go to `/home/ubuntu/wallabag-sqlite-backup.log` and `/home/ubuntu/wallabag-b2-sync.log`. Shares the same `b2 account authorize` out-of-band requirement as the AIO sync above.

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

# Restart the Caddy compose project
systemctl --user restart docker-compose-caddy

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
│   └── roles/
│       ├── docker_host/             # Host base: rootless Docker, hardening, B2 CLI
│       │   ├── defaults/main.yml
│       │   ├── tasks/main.yml
│       │   └── README.md
│       ├── caddy/                   # Reverse proxy: own compose project, site snippets
│       │   ├── defaults/main.yml
│       │   ├── tasks/main.yml
│       │   ├── templates/
│       │   │   ├── Caddyfile.j2
│       │   │   ├── docker-compose.yml.j2
│       │   │   └── docker-compose.service.j2
│       │   └── README.md
│       ├── nextcloud_aio/
│       │   ├── defaults/main.yml    # Default role variables
│       │   ├── tasks/main.yml       # Role tasks
│       │   ├── molecule/            # Molecule scenarios (functional test, B2 restore)
│       │   ├── templates/
│       │   │   ├── docker-compose.yml.j2
│       │   │   ├── nextcloud.caddy.j2
│       │   │   ├── docker-compose.service.j2
│       │   │   ├── nextcloud-aio-backup.service.j2
│       │   │   └── nextcloud-aio-backup.timer.j2
│       │   └── README.md
│       └── wallabag/                # App: SQLite + daily B2 backup (disabled by default)
│           ├── defaults/main.yml
│           ├── tasks/main.yml       # Guarded by wallabag_enabled
│           ├── templates/
│           │   ├── docker-compose.yml.j2
│           │   ├── wallabag.caddy.j2
│           │   └── docker-compose.service.j2
│           └── README.md
```
