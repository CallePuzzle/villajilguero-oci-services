# AGENTS.md - jilguedev

Entorno de desarrollo para Nextcloud All-in-One (AIO) desplegado en una instancia OCI Ubuntu con Docker rootless.

## Arquitectura

- **OCI Instance**: Ubuntu 24.04 (shape VM.Standard.A1.Flex) provisionada via Terraform (`terraform-module-k0s-oci` con `enable_k0s = false`).
- **Docker**: Rootless mode con socket en `/run/user/<uid>/docker.sock`.
- **Reverse Proxy**: Caddy en `network_mode: host` escuchando en 80/443(TCP+UDP para HTTP/3) y proxyficando a `localhost:11000`.
- **Nextcloud AIO**: Mastercontainer en `network_mode: bridge` con la interfaz admin restringida a `127.0.0.1:8080`.

## Operaciones comunes

### Despliegue inicial
```bash
cd jilguedev
terraform apply
cd ansible
poetry install
poetry run ansible-playbook -i inventory/oci_docker.yml playbook.yml
```

### Acceso
- **Nextcloud**: `https://aio.callepuzzle.com`
- **AIO Admin**: `https://<ip-publica>:8080` (restringido via UFW; usar túnel SSH si es necesario)

### Backup y restauración
AIO incluye BorgBackup integrado. Se gestiona desde la UI de AIO (`https://localhost:8080`).

**Backup automatizado**: Un systemd user timer ejecuta diariamente a las 02:00:
```bash
systemctl --user status nextcloud-aio-backup.timer
```

El script ejecuta:
```bash
docker exec --env DAILY_BACKUP=1 --env AUTOMATIC_UPDATES=1 nextcloud-aio-mastercontainer /daily-backup.sh
```

**Backup remoto**: Desde la UI de AIO se puede configurar un repositorio Borg remoto via SSH. AIO genera automáticamente un par de claves SSH. Se recomienda usar modo append-only para protección contra ransomware.

**Restauración**: Solo se necesita el backup de Borg + la contraseña de encriptación. Se restaura completo desde la UI de AIO.

### Actualizaciones
- **Automáticas**: El timer de backup incluye `AUTOMATIC_UPDATES=1`, por lo que AIO se actualiza automáticamente durante el backup diario.
- **Manuales**: Desde la UI de AIO (`https://localhost:8080`) o ejecutando el script de backup manualmente.

### Seguridad
- **UFW**: Solo 22 (SSH), 80 (HTTP) y 443 (HTTPS) están abiertos públicamente. El puerto 8080 (AIO admin) está denegado desde fuera.
- **fail2ban**: Protege SSH contra fuerza bruta.
- **unattended-upgrades**: Actualizaciones de seguridad automáticas del SO.
- **Docker rootless**: Reduce la superficie de ataque; los contenedores corren sin privilegios de root.
- **Log driver**: Docker usa `log-driver: local` para evitar crecimiento descontrolado de logs.
- **Container hardening**: `cap_drop: [ALL]` y `no-new-privileges:true` en el mastercontainer.
- **Trusted proxies**: `NEXTCLOUD_TRUSTED_PROXIES=127.0.0.1` configurado para Caddy en host network.

### Variables importantes
Definidas en `ansible/roles/nextcloud_aio/defaults/main.yml` y sobrescribibles en `group_vars/docker_servers.yml`:

| Variable | Descripción | Default |
|----------|-------------|---------|
| `nextcloud_aio_domain` | Dominio público de Nextcloud | `aio.callepuzzle.com` |
| `nextcloud_aio_datadir` | Path host para datos (vacío = volumen Docker) | `""` |
| `nextcloud_aio_memory_limit` | Límite de memoria PHP | `2048M` |
| `nextcloud_aio_upload_limit` | Límite de subida | `16G` |
| `nextcloud_aio_max_time` | Tiempo máx. de ejecución PHP | `3600` |
| `nextcloud_aio_borg_retention_policy` | Retención de backups Borg | `--keep-within=7d --keep-weekly=4 --keep-monthly=6` |
| `nextcloud_aio_log_level` | Nivel de log de AIO | `warn` |
| `nextcloud_aio_backup_enabled` | Habilitar backup timer | `true` |
| `nextcloud_aio_backup_time` | Hora del backup diario | `02:00` |
| `nextcloud_aio_enable_ufw` | Habilitar UFW | `true` |
| `nextcloud_aio_enable_fail2ban` | Habilitar fail2ban | `true` |
| `nextcloud_aio_enable_unattended_upgrades` | Habilitar unattended-upgrades | `true` |

### Docker daemon
El daemon rootless se configura con:
- `log-driver: local`
- `live-restore: false` (rootless no soporta live-restore)

### Advertencias
- `NEXTCLOUD_DATADIR` **solo puede configurarse antes del primer arranque** de Nextcloud. Cambiarlo después requiere recrear la instalación.
- El puerto 8080 (AIO admin) está denegado en UFW y no tiene regla de ingress en la Security List de OCI, por lo que solo es accesible via túnel SSH (`ssh -L 8080:localhost:8080 ubuntu@<ip>`).
