# AGENTS.md - jilgue

Entorno de producción para Nextcloud All-in-One (AIO) desplegado en una instancia OCI Ubuntu con Docker rootless.

## Arquitectura

- **OCI Instance**: Ubuntu 24.04 (shape VM.Standard.A1.Flex) provisionada via Terraform (`terraform-module-k0s-oci` con `enable_k0s = false`, pineado por tag git: `?ref=v1.7.2` en `main.tf`). El módulo **nunca reemplaza la instancia viva** (submódulo `compute-instance` vendorizado con `ignore_changes = [metadata, source_details]`): cloud-init e imagen solo aplican en el primer boot; los parches van por unattended-upgrades.
- **Roles de Ansible**: `docker_host` (base del host: Docker rootless, hardening, CLI de Backblaze B2), `caddy` (reverse proxy con compose propio y snippets de sitio por app), `nextcloud_aio` y `wallabag` (apps). El playbook los ejecuta en ese orden.
- **Docker**: Rootless mode con socket en `/run/user/<uid>/docker.sock`.
- **Reverse Proxy**: Caddy en `network_mode: host` escuchando en 80/443(TCP+UDP para HTTP/3) y proxyficando a `localhost:11000`. Compose y Caddyfile base los gestiona el rol `caddy` (proyecto compose `caddy`, volúmenes nombrados `caddy_config`/`caddy_data` reutilizados del layout anterior); cada rol de app escribe su snippet de sitio en `caddy_sites_path` (p. ej. `nextcloud.caddy`, `wallabag.caddy`) y reinicia el contenedor `caddy` si cambia.
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
- **Wallabag** (deshabilitada por defecto: poner `wallabag_enabled: true` en group_vars para desplegarla): `https://wallabag.callepuzzle.com`. El login por defecto de la imagen es `wallabag` / `wallabag`: **cambia la contraseña tras el primer acceso** (Configuración → Mi cuenta) y crea usuarios individuales; el registro público ya viene desactivado.

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
El log queda en `/home/ubuntu/nextcloud-aio-b2-sync.log`. El CLI lo instala automáticamente el rol `docker_host` (`docker_host_b2_cli_enabled`), pero requiere autorización manual y fuera de banda (`b2 account authorize`) ya que las credenciales todavía no se gestionan vía SOPS.

**Backup de Wallabag** (cuando `wallabag_enabled: true`): un cron diario (por defecto a las 04:00) toma un snapshot consistente de la BD SQLite con la API de backup online (`sqlite3 <wallabag_data_path>/db/wallabag.sqlite ".backup ..."`) en `wallabag_backup_dir`, y un segundo cron (04:30) sincroniza ese directorio al bucket B2 (`wallabag_b2_bucket`, subcarpeta `wallabag/` del bucket de AIO):
```bash
/usr/bin/sqlite3 /home/ubuntu/wallabag/data/db/wallabag.sqlite ".backup '/home/ubuntu/wallabag-backups/wallabag.sqlite'"
/usr/local/bin/b2 sync /home/ubuntu/wallabag-backups b2://callepuzzle-nextcloud-borg-backup/wallabag/
```
Los horarios van entre el backup Borg de AIO (02:00) y su sincronización B2 (05:00) para que los dos procesos `b2` no se solapen. El snapshot se sobreescribe a diario; `b2 sync` conserva en el bucket las versiones anteriores de los ficheros cambiados. Logs en `/home/ubuntu/wallabag-sqlite-backup.log` y `/home/ubuntu/wallabag-b2-sync.log`. Comparte la misma deuda del CLI `b2` sin autorizar (ver Advertencias). Las imágenes de las entradas no van al backup (volumen nombrado, contenido re-descargable); la BD sí incluye los artículos, usuarios y ajustes.

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
- **Security List OCI** (módulo ≥ v1.6.0, efectivo tras el siguiente `terraform apply`): el 22 (SSH) solo admite la IP pública `/32` de quien ejecuta terraform (data source `http` contra `ipv4.icanhazip.com`; si cambias de red, el siguiente apply actualiza la regla). El 80/443 siguen abiertos a `0.0.0.0/0` via `additional_security_list_rules` (tráfico web necesario para Nextcloud).
- **fail2ban**: Protege SSH contra fuerza bruta.
- **unattended-upgrades**: Actualizaciones de seguridad automáticas del SO.
- UFW, fail2ban y unattended-upgrades los instala y configura el rol `docker_host` (conmutadores `docker_host_enable_*`).
- **Docker rootless**: Reduce la superficie de ataque; los contenedores corren sin privilegios de root.
- **Log driver**: Docker usa `log-driver: local` para evitar crecimiento descontrolado de logs.
- **Trusted proxies**: `NEXTCLOUD_TRUSTED_PROXIES=127.0.0.1` configurado para Caddy en host network.

### Variables importantes

Las del rol `docker_host` están en `ansible/roles/docker_host/defaults/main.yml`; las de `caddy` en `ansible/roles/caddy/defaults/main.yml`; las de `nextcloud_aio` en `ansible/roles/nextcloud_aio/defaults/main.yml`; las de `wallabag` en `ansible/roles/wallabag/defaults/main.yml`. Todas son sobrescribibles en `group_vars/docker_servers.yml`.

**Rol `docker_host`** (base del host):

| Variable | Descripción | Default |
|----------|-------------|---------|
| `docker_host_user` | Usuario que ejecuta Docker rootless (compartido con los roles de app) | `ubuntu` |
| `docker_host_storage_driver` | Storage driver de Docker (vacío = default; `fuse-overlayfs` en entornos anidados) | `""` |
| `docker_host_enable_ufw` | Habilitar UFW | `true` |
| `docker_host_enable_fail2ban` | Habilitar fail2ban | `true` |
| `docker_host_enable_unattended_upgrades` | Habilitar unattended-upgrades | `true` |
| `docker_host_b2_cli_enabled` | Instalar el CLI de Backblaze B2 (lo usan los crons de las apps) | `true` |
| `docker_host_b2_version` | Versión del CLI de Backblaze B2 a instalar | `4.7.1` |

**Rol `caddy`** (reverse proxy):

| Variable | Descripción | Default |
|----------|-------------|---------|
| `caddy_compose_path` | Directorio del proyecto compose de Caddy | `/home/ubuntu/caddy` |
| `caddy_sites_path` | Directorio de snippets de sitio que importa el Caddyfile base (derivado; lo exportan como fact tanto `caddy` como los roles de app) | `{{ caddy_compose_path }}/sites` |
| `caddy_container_name` | Contenedor que los roles de app reinician tras cambiar un snippet | `caddy` |
| `caddy_image` | Imagen de Caddy | `caddy:alpine` |

El rol deja `caddy_sites_path` y `caddy_container_name` como facts para los roles de app (ver README del rol). El Caddyfile base incluye un placeholder `:80` para que la config siga siendo válida cuando no hay snippets.

**Rol `nextcloud_aio`** (app):

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
| `nextcloud_aio_b2_sync_enabled` | Habilitar sincronización diaria del backup a Backblaze B2 (requiere `docker_host_b2_cli_enabled`) | `true` |
| `nextcloud_aio_b2_sync_time` | Hora de la sincronización a B2 | `05:00` |
| `nextcloud_aio_b2_bucket` | Bucket B2 destino de la sincronización | `b2://callepuzzle-nextcloud-borg-backup/` |

**Rol `wallabag`** (app, deshabilitada por defecto):

| Variable | Descripción | Default |
|----------|-------------|---------|
| `wallabag_enabled` | Desplegar la app y sus crons de backup | `false` |
| `wallabag_compose_path` | Directorio del proyecto compose | `/home/ubuntu/wallabag` |
| `wallabag_compose_file` | Nombre del fichero compose | `docker-compose.yml` |
| `wallabag_domain` | Dominio público de Wallabag | `wallabag.callepuzzle.com` |
| `wallabag_image` | Imagen oficial multi-arch (arm64 nativo), pinneada a la tag minor | `wallabag/wallabag:2.6` |
| `wallabag_port` | Puerto en loopback que proxyfíca Caddy (8080 y 11000 ya ocupados) | `8081` |
| `wallabag_ip_binding` | IP donde se publica el puerto (no exponer salvo tests) | `127.0.0.1` |
| `wallabag_locale` | Idioma de la interfaz | `en` |
| `wallabag_secret` | Secreto de tokens de la app (vacío = default público de la imagen) | `""` |
| `wallabag_data_path` | Bind mount del host para la BD SQLite | `{{ wallabag_compose_path }}/data` |
| `wallabag_backup_dir` | Directorio local del snapshot SQLite que se sincroniza a B2 | `/home/ubuntu/wallabag-backups` |
| `wallabag_backup_file` | Nombre del fichero snapshot | `wallabag.sqlite` |
| `wallabag_backup_enabled` | Habilitar el snapshot SQLite diario | `true` |
| `wallabag_backup_time` | Hora del snapshot SQLite | `04:00` |
| `wallabag_b2_sync_enabled` | Habilitar la sincronización diaria del snapshot a B2 (requiere `docker_host_b2_cli_enabled`) | `true` |
| `wallabag_b2_sync_time` | Hora de la sincronización a B2 | `04:30` |
| `wallabag_b2_bucket` | Bucket B2 destino (subcarpeta del bucket de AIO) | `b2://callepuzzle-nextcloud-borg-backup/wallabag/` |

### Docker daemon
El daemon rootless se configura con:
- `log-driver: local`
- `live-restore: false` (rootless no soporta live-restore)

### Advertencias
- `NEXTCLOUD_DATADIR` **solo puede configurarse antes del primer arranque** de Nextcloud. Cambiarlo después requiere recrear la instalación.
- El puerto 8080 (AIO admin) está denegado en UFW y no tiene regla de ingress en la Security List de OCI, por lo que solo es accesible via túnel SSH (`ssh -L 8080:localhost:8080 ubuntu@<ip>`).
- `nextcloud_aio_b2_sync_enabled` requiere que el CLI `b2` esté autorizado manualmente en el host (`b2 account authorize`) antes de que el cron pueda sincronizar; las credenciales aún no se gestionan vía SOPS. Lo mismo aplica al cron de Wallabag (`wallabag_b2_sync_enabled`).
- El login por defecto de Wallabag es `wallabag` / `wallabag`: **cambia la contraseña tras el primer acceso** (Configuración → Mi cuenta); el registro público ya viene desactivado de fábrica. El primer arranque puede tardar unos minutos (inicializa la BD y compila assets).
