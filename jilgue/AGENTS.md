# AGENTS.md - jilgue

Entorno de producción para Nextcloud All-in-One (AIO) desplegado en una instancia OCI Ubuntu con Docker rootless.

## Arquitectura

- **OCI Instance**: Ubuntu 24.04 (shape VM.Standard.A1.Flex) provisionada via Terraform (`terraform-module-k0s-oci` con `enable_k0s = false`).
- **Docker**: Rootless mode con socket en `/run/user/<uid>/docker.sock`.
- **Reverse Proxy**: Caddy en `network_mode: host` escuchando en 80/443(TCP+UDP para HTTP/3) y proxyficando a `localhost:11000`.
- **Nextcloud AIO**: Mastercontainer en `network_mode: bridge` con la interfaz admin restringida a `127.0.0.1:8080`.

## Operaciones comunes

### Despliegue inicial
```bash
cd jilgue
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

**Backup local**: El rol de Ansible crea por defecto `/home/ubuntu/nextcloud-aio-backups` y lo monta en el mastercontainer. En la UI de AIO se debe configurar ese mismo path como ubicación de backup para que Borg cree el repositorio en `/home/ubuntu/nextcloud-aio-backups/borg`.

**Backup automatizado**: Un systemd user timer ejecuta diariamente a las 02:00:
```bash
systemctl --user status nextcloud-aio-backup.timer
```

El script ejecuta:
```bash
docker exec --env DAILY_BACKUP=1 --env AUTOMATIC_UPDATES=1 nextcloud-aio-mastercontainer /daily-backup.sh
```

**Sincronización a Backblaze B2**: Un cron diario (por defecto a las 05:00, tres horas después del backup de Borg) sincroniza `nextcloud_aio_backup_dir` al bucket B2 configurado en `nextcloud_aio_b2_bucket` mediante el CLI `b2`:
```bash
/usr/local/bin/b2 sync /home/ubuntu/nextcloud-aio-backups b2://callepuzzle-nextcloud-borg-backup/
```
El log queda en `/home/ubuntu/nextcloud-aio-b2-sync.log`. El CLI se instala automáticamente por Ansible, pero requiere autorización manual y fuera de banda (`b2 account authorize`) ya que las credenciales todavía no se gestionan vía SOPS.

**Backup remoto**: Como alternativa al local, desde la UI de AIO se puede configurar un repositorio Borg remoto vía SSH. AIO genera automáticamente un par de claves SSH. Se recomienda usar modo append-only para protección contra ransomware.

**Restauración**: Solo se necesita el backup de Borg + la contraseña de encriptación. Se restaura completo desde la UI de AIO.

**Test de verificación del backup de producción (B2)**: Para comprobar que la copia sincronizada desde Backblaze B2 es válida y contiene los datos esperados, hay dos opciones:

1. **Molecule (recomendado)**: ejecuta la verificación dentro de un contenedor Podman desechable:

```bash
cd jilgue/ansible/roles/nextcloud_aio
# Asegúrate de tener el backup en tmp/nextcloud-aio-borg-backup/
# y la passphrase en .borg.txt (ambos ignorados por git)
poetry run molecule test --scenario-name b2-restore
```

2. **Playbook local**: para comprobaciones rápidas sin contenedor:

```bash
cd jilgue/ansible
poetry run ansible-playbook playbooks/verify-b2-backup.yml
```

Ambos test:
- Ejecutan `borg check` sobre el repositorio local.
- Listan los archives disponibles.
- Extraen el dump SQL de PostgreSQL.
- Verifican que los usuarios `cesar` y `nuria` existen en `oc_users`.

### Actualizaciones
- **Automáticas**: El timer de backup incluye `AUTOMATIC_UPDATES=1`, por lo que AIO se actualiza automáticamente durante el backup diario.
- **Manuales**: Desde la UI de AIO (`https://localhost:8080`) o ejecutando el script de backup manualmente.

### Seguridad
- **UFW**: Solo 22 (SSH), 80 (HTTP) y 443 (HTTPS) están abiertos públicamente. El puerto 8080 (AIO admin) está denegado desde fuera.
- **fail2ban**: Protege SSH contra fuerza bruta.
- **unattended-upgrades**: Actualizaciones de seguridad automáticas del SO.
- **Docker rootless**: Reduce la superficie de ataque; los contenedores corren sin privilegios de root.
- **Log driver**: Docker usa `log-driver: local` para evitar crecimiento descontrolado de logs.
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
| `nextcloud_aio_disable_backup_section` | Ocultar sección de backup en la UI de AIO | `false` |
| `nextcloud_aio_backup_dir` | Directorio host para backups locales de Borg | `/home/ubuntu/nextcloud-aio-backups` |
| `nextcloud_aio_backup_enabled` | Habilitar timer de backup diario | `true` |
| `nextcloud_aio_backup_time` | Hora del backup diario | `02:00` |
| `nextcloud_aio_b2_sync_enabled` | Habilitar sincronización diaria del backup a Backblaze B2 | `true` |
| `nextcloud_aio_b2_sync_time` | Hora de la sincronización a B2 | `05:00` |
| `nextcloud_aio_b2_version` | Versión del CLI de Backblaze B2 a instalar | `4.7.1` |
| `nextcloud_aio_b2_bucket` | Bucket B2 destino de la sincronización | `b2://callepuzzle-nextcloud-borg-backup/` |
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
- `nextcloud_aio_b2_sync_enabled` requiere que el CLI `b2` esté autorizado manualmente en el host (`b2 account authorize`) antes de que el cron pueda sincronizar; las credenciales aún no se gestionan vía SOPS.
