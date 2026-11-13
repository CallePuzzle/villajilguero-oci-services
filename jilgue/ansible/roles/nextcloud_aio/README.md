# nextcloud_aio

App Nextcloud All-in-One detrás del Caddy compartido: mastercontainer en su
propio proyecto compose, snippet de sitio para el proxy, timer de backup
diario y sincronización a Backblaze B2. Es el rol principal del entorno
`jilgue`; depende de que `docker_host` y `caddy` hayan corrido antes en el
mismo play (daemon rootless, CLI `b2`, directorio de sitios y contenedor
proxy).

## Qué hace

- **Compose propio**: `docker-compose.yml` en `nextcloud_aio_compose_path`
  (proyecto `nextcloud-aio`) con el mastercontainer de AIO
  (`ghcr.io/nextcloud-releases/all-in-one:latest`, red bridge, interfaz
  admin publicada solo en `127.0.0.1:8080`, socket rootless de Docker
  montado read-only y `nextcloud_aio_backup_dir` montado para Borg). Los
  cambios del compose se aplican con `docker compose up -d` explícito
  cuando el fichero cambia: la unit solo lo arranca si no estaba ya en
  marcha. El servicio `caddy` ya no está aquí: vive en el proyecto compose
  del rol `caddy` (#38), que reutiliza los volúmenes `caddy_config` /
  `caddy_data`.
- **Snippet de sitio**: `nextcloud.caddy` en `caddy_sites_path` con
  `nextcloud_aio_domain` (HSTS, `reverse_proxy` a
  `localhost:{{ nextcloud_aio_apache_port }}` y redirecciones
  `/.well-known/carddav` y `/.well-known/caldav` a `/remote.php/dav/`);
  reinicia el contenedor Caddy si cambia (solo lee los snippets al
  arrancar).
- **Unit systemd** `docker-compose-nextcloud.service` (ámbito usuario):
  oneshot + `RemainAfterExit` que lanza `docker compose up -d` cuando el
  socket rootless está disponible. Mismo patrón que `caddy` y `wallabag`.
- **Backup automático**: unit + timer `nextcloud-aio-backup` (ámbito
  usuario, `nextcloud_aio_backup_time`, 02:00 por defecto) que ejecuta
  `docker exec --env DAILY_BACKUP=1 --env AUTOMATIC_UPDATES=1
  nextcloud-aio-mastercontainer /daily-backup.sh`: backup Borg diario y
  actualizaciones automáticas de AIO en la misma pasada.
- **Sincronización a Backblaze B2**: cron diario
  (`nextcloud_aio_b2_sync_time`, 05:00) que hace `b2 sync` de
  `nextcloud_aio_backup_dir` al bucket `nextcloud_aio_b2_bucket`. Requiere
  el CLI `b2` instalado por el rol `docker_host` y autorizado a mano en el
  host (`b2 account authorize`; deuda conocida, las credenciales aún no se
  gestionan vía SOPS).

## Migración pendiente del Caddy legacy

Mientras el fact `caddy_legacy_migration_pending` esté activo (existe un
contenedor `caddy` del proyecto compose `nextcloud-aio`, layout anterior a
#38), este rol:

- **no reinicia el proxy** aunque cambie su snippet: el handler del rol
  `caddy` arranca el Caddy nuevo al final del play, y ese arranque lee
  todos los snippets;
- **conserva `~/nextcloud-aio/Caddyfile`**: el contenedor legacy lo sigue
  montando y haría falta si el traspaso hace rollback.

Ese Caddyfile es obsoleto desde #38 (el base está en `~/caddy/Caddyfile`):
la **siguiente ejecución** del playbook, con la migración ya hecha, lo
borra. Procedimiento en producción y rollback manual:
[`jilgue/MIGRATION.md`](../../../MIGRATION.md).

## Variables

| Variable | Descripción | Default |
|----------|-------------|---------|
| `nextcloud_aio_compose_path` | Directorio del proyecto compose | `/home/ubuntu/nextcloud-aio` |
| `nextcloud_aio_compose_file` | Nombre del fichero compose | `docker-compose.yml` |
| `nextcloud_aio_domain` | Dominio público de Nextcloud | `aio.callepuzzle.com` |
| `nextcloud_aio_apache_port` | Puerto de Apache (AIO) que proxyfíca Caddy | `11000` |
| `nextcloud_aio_apache_ip_binding` | IP donde AIO publica Apache (no exponer salvo tests) | `127.0.0.1` |
| `nextcloud_aio_skip_domain_validation` | Saltarse la validación de dominio de AIO (necesaria en tests con dominio no real) | `true` |
| `nextcloud_aio_mastercontainer_ip_binding` | IP de la interfaz admin del mastercontainer (8080); no exponer salvo tests | `127.0.0.1` |
| `nextcloud_aio_caddy_tls_internal` | Servir el sitio con certificado autofirmado local en vez de pedirlo a Let's Encrypt (solo para escenarios de test con dominio no real; lo aplica el snippet `nextcloud.caddy`) | `false` |
| `caddy_sites_path` | Directorio de snippets del proxy (fact del rol `caddy`; default replicado para poder ejecutarse en solitario) | `/home/ubuntu/caddy/sites` |
| `caddy_container_name` | Contenedor Caddy a reiniciar tras cambiar el snippet (fact del rol `caddy`) | `caddy` |
| `docker_host_user` | Usuario que ejecuta Docker rootless y es propietario del compose (compartido con los roles de host; default replicado) | `ubuntu` |
| `nextcloud_aio_datadir` | Path host para los datos — **solo puede fijarse antes del primer arranque** (vacío = volumen Docker) | `""` |
| `nextcloud_aio_memory_limit` | Límite de memoria PHP | `2048M` |
| `nextcloud_aio_upload_limit` | Límite de subida | `16G` |
| `nextcloud_aio_max_time` | Tiempo máximo de ejecución PHP | `3600` |
| `nextcloud_aio_borg_retention_policy` | Retención de backups Borg | `--keep-within=7d --keep-weekly=4 --keep-monthly=6` |
| `nextcloud_aio_log_level` | Nivel de log de AIO (`error`, `warn`, `info`, `debug`) | `warn` |
| `nextcloud_aio_trusted_proxies` | Proxies de confianza para Nextcloud (Caddy va en host network) | `127.0.0.1` |
| `nextcloud_aio_disable_backup_section` | Ocultar la sección de backup en la UI de AIO | `false` |
| `nextcloud_aio_backup_dir` | Directorio host destino de los backups Borg locales (montado en el mastercontainer) | `/home/ubuntu/nextcloud-aio-backups` |
| `nextcloud_aio_backup_enabled` | Habilitar el timer de backup diario | `true` |
| `nextcloud_aio_backup_time` | Hora del backup diario | `02:00` |
| `nextcloud_aio_b2_sync_enabled` | Habilitar la sincronización diaria del backup a Backblaze B2 (requiere `docker_host_b2_cli_enabled`) | `true` |
| `nextcloud_aio_b2_sync_time` | Hora de la sincronización a B2 | `05:00` |
| `nextcloud_aio_b2_bucket` | Bucket B2 destino de la sincronización | `b2://callepuzzle-nextcloud-borg-backup/` |

## Facts consumidos

Del rol `docker_host` (mismo play): `docker_host_socket_path` (socket
rootless de Docker).

Del rol `caddy` (mismo play): `caddy_sites_path`,
`caddy_container_name` y `caddy_legacy_migration_pending` (ver README del
rol `caddy`). Los defaults de los dos primeros están replicados aquí para
que el rol siga siendo ejecutable en solitario; los overrides del rol
`caddy` ganan, porque `set_fact` tiene prioridad sobre los defaults.

## Uso

```yaml
- hosts: docker_servers
  roles:
    - docker_host   # primero
    - caddy         # reverse proxy
    - nextcloud_aio # este rol
    - wallabag      # opcional (no hace nada hasta wallabag_enabled: true)
```

## Tests

```bash
cd jilgue/ansible/roles/nextcloud_aio
poetry run molecule test --scenario-name aio-functional   # AIO completo en podman
poetry run molecule test --scenario-name b2-restore       # verificación del backup B2
```

Alternativa sin contenedor para la verificación del backup:
`poetry run ansible-playbook playbooks/verify-b2-backup.yml` (desde
`jilgue/ansible`; bootstrapea su propio venv de borg en `.venv-borg/`).

Para depurar una instancia del escenario `aio-functional` en pie (ahí está
también la contraseña de admin de AIO):

```bash
sudo podman exec -it aio-functional-test bash
su - aiotest
docker exec nextcloud-aio-mastercontainer grep password /mnt/docker-aio-config/data/configuration.json
```
