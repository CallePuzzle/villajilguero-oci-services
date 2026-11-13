# wallabag

App Wallabag (read-it-later) detrás del Caddy compartido: compose propio,
SQLite en bind mount del host y copia de seguridad diaria a Backblaze B2.
**Deshabilitada por defecto** (`wallabag_enabled: false`); actívala en
`group_vars/docker_servers.yml` para desplegarla.

## Qué hace

- **Compose propio**: `docker-compose.yml` en `wallabag_compose_path` con la
  imagen oficial `wallabag/wallabag`, publicada en multi-arch (amd64/arm64
  construidos de forma nativa — sin emulación; el host es aarch64). Pinneada
  a una tag de versión concreta (`2.6.15.1`) para que las subidas sean
  previsibles: upstream solo publica tags de versión + `latest` (no hay tag
  flotante `2.6`/`2`), así que subir de versión es un cambio deliberado del
  default (o un override en group_vars).
- **Servicio solo en loopback**: publica `wallabag_ip_binding:wallabag_port`
  (`127.0.0.1:8081` por defecto — 8080 y 11000 ya los usa AIO). Caddy (host
  network) proxyfíca `wallabag_domain` a ese puerto. La imagen trae su propio
  `HEALTHCHECK` (curl contra `/api/info`), no hace falta uno en compose.
- **SQLite en bind mount**: `wallabag_data_path` se monta en
  `/var/www/wallabag/data`, así la BD queda en el host en
  `<wallabag_data_path>/db/wallabag.sqlite`. El rol crea el directorio con
  modo `0755` (propietario `docker_host_user`): el entrypoint de la imagen
  corre como root del contenedor, que Docker rootless mapea al propio
  `docker_host_user` (por eso su "mkdir and chown are mandatory for local
  folder binding" funciona y deja `data/db` en el subuid del `nobody` del
  contenedor), pero la app corre como ese `nobody` y con `0750` se queda
  sin el bit de traverse sobre el bind mount — la BD no se llega a abrir
  ("unable to open database file", visto en el scenario Molecule
  `wallabag-functional`). El fichero SQLite resultante es `0644`, legible
  por el cron de backup. Las imágenes de las entradas, en cambio, van en
  un volumen nombrado (`wallabag_images`), inicializado desde la imagen y
  ya con el propietario correcto. No se incluyen en el backup: son
  contenido re-descargable.
- **Unit systemd** `docker-compose-wallabag.service` (ámbito usuario):
  oneshot + `RemainAfterExit` que lanza `docker compose up -d` cuando el
  socket rootless está disponible. Mismo patrón que `caddy` y `nextcloud_aio`.
- **Snippet de sitio**: `wallabag.caddy` en `caddy_sites_path` con
  `wallabag_domain` (HSTS + reverse proxy al puerto de loopback); reinicia el
  contenedor Caddy si cambia (solo lee los snippets al arrancar).
- **Backup diario**: cron (`wallabag_backup_time`, 04:00) con snapshot
  consistente de la BD (`sqlite3 .backup`, API de backup online de SQLite;
  instala el paquete `sqlite3` si hace falta) sobre
  `wallabag_backup_dir/wallabag_backup_file`, y segundo cron
  (`wallabag_b2_sync_time`, 04:30) que hace `b2 sync` del directorio al
  bucket B2 existente (`wallabag_b2_bucket`: subcarpeta `wallabag/` del
  bucket que ya usa AIO). Horarios elegidos entre el backup Borg de AIO
  (02:00) y su sincronización B2 (05:00) para que los dos procesos `b2` no
  se solapen. El snapshot se sobreescribe a diario: `b2 sync` conserva por
  defecto las versiones anteriores de los ficheros cambiados, así que la
  historia queda en el bucket sin copias locales con timestamp.
  Los logs van a `~/wallabag-sqlite-backup.log` y `~/wallabag-b2-sync.log`.

## Variables

| Variable | Descripción | Default |
|----------|-------------|---------|
| `wallabag_enabled` | Desplegar la app y sus crons de backup | `false` |
| `wallabag_compose_path` | Directorio del proyecto compose | `/home/ubuntu/wallabag` |
| `wallabag_compose_file` | Nombre del fichero compose | `docker-compose.yml` |
| `wallabag_domain` | Dominio público de Wallabag | `wallabag.callepuzzle.com` |
| `wallabag_caddy_tls_internal` | Servir el sitio con certificado autofirmado local en vez de pedirlo a Let's Encrypt (solo para escenarios de test con dominio no real; lo aplica el snippet `wallabag.caddy`) | `false` |
| `wallabag_image` | Imagen oficial (multi-arch, arm64 nativo), pinneada a una tag de versión concreta | `wallabag/wallabag:2.6.15.1` |
| `wallabag_port` | Puerto en loopback que proxyfíca Caddy | `8081` |
| `wallabag_ip_binding` | IP donde se publica el puerto (no exponer salvo tests) | `127.0.0.1` |
| `wallabag_locale` | Idioma de la interfaz | `en` |
| `wallabag_secret` | Secreto de tokens de la app; vacío = default público de la imagen (pón uno real, p. ej. `openssl rand -hex 32`) | `""` |
| `wallabag_data_path` | Bind mount del host para `/var/www/wallabag/data` (la BD SQLite) | `{{ wallabag_compose_path }}/data` |
| `wallabag_backup_dir` | Directorio local del snapshot SQLite que se sincroniza a B2 | `/home/ubuntu/wallabag-backups` |
| `wallabag_backup_file` | Nombre del fichero snapshot | `wallabag.sqlite` |
| `wallabag_backup_enabled` | Habilitar el snapshot SQLite diario | `true` |
| `wallabag_backup_time` | Hora del snapshot SQLite | `04:00` |
| `wallabag_b2_sync_enabled` | Habilitar la sincronización diaria del snapshot a B2 (requiere `docker_host_b2_cli_enabled`) | `true` |
| `wallabag_b2_sync_time` | Hora de la sincronización a B2 | `04:30` |
| `wallabag_b2_bucket` | Bucket B2 destino de la sincronización | `b2://callepuzzle-nextcloud-borg-backup/wallabag/` |
| `caddy_sites_path` | Directorio de snippets del proxy (fact del rol `caddy`; default replicado para poder ejecutarse en solitario) | `/home/ubuntu/caddy/sites` |
| `caddy_container_name` | Contenedor Caddy a reiniciar tras cambiar el snippet (fact del rol `caddy`) | `caddy` |
| `docker_host_user` | Usuario que ejecuta Docker rootless y es propietario del compose (compartido con los roles de host; default replicado) | `ubuntu` |

## Primer acceso

- El login por defecto de la imagen es **`wallabag` / `wallabag`**:
  **cambia la contraseña tras el primer acceso** (Configuración → Mi cuenta) y
  crea usuarios individuales para cada persona. El registro público ya viene
  desactivado de fábrica (`FOSUSER_REGISTRATION=false`).
- El primer arranque inicializa la BD y calienta cachés: puede tardar unos
  minutos (`docker logs wallabag` para seguirlo).

## Uso

```yaml
- hosts: docker_servers
  roles:
    - docker_host   # primero
    - caddy         # reverse proxy
    - nextcloud_aio # las apps, después
    - wallabag      # esta (no hace nada hasta wallabag_enabled: true)
```

## Test funcional

Escenario Molecule `wallabag-functional` (mismo patrón podman/sudo que
`aio-functional`): converge `[docker_host, caddy, wallabag]` en un contenedor
desechable con `wallabag_enabled: true` y TLS internal (dominio falso, sin
DNS/ACME real), con el sync a B2 desactivado. El verify comprueba que el login
responde a través de Caddy (`curl -k` con `--resolve`), que el contenedor está
healthy y que el cron de snapshot SQLite está presente (y el de B2 ausente).

```bash
cd jilgue/ansible/roles/wallabag
poetry run molecule test --scenario-name wallabag-functional
```

Para depurar una instancia en pie:

```bash
sudo podman exec -it wallabag-functional-test bash
su - wallatest
docker logs wallabag
```
