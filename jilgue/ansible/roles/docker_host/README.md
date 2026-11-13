# docker_host

Base de host común a todas las apps: Docker rootless, hardening del SO y CLI de
Backblaze B2. No despliega ninguna aplicación; los roles de app
(`nextcloud_aio`, `wallabag`, ...) se ejecutan después y despliegan sobre él.

## Qué hace

- **Docker rootless**: instala dependencias y repo apt de Docker CE, ajusta los
  sysctls necesarios (`kernel.unprivileged_userns_clone`,
  `net.ipv4.ip_unprivileged_port_start`), habilita linger para el usuario,
  inicializa el daemon rootless (`dockerd-rootless-setuptool.sh install`) y
  configura `daemon.json` (`log-driver: local`, `live-restore: false` — no
  soportado en rootless — y `storage-driver` opcional, p. ej.
  `fuse-overlayfs` en entornos anidados).
- **Hardening**: UFW (22/80/443 abiertos, 8080 denegado, policy deny),
  fail2ban (jail sshd) y unattended-upgrades. Idempotente sobre un host
  vivo: UFW ya no se resetea en cada ejecución (añade las reglas que
  falten; las reglas añadidas a mano o retiradas de aquí hay que borrarlas
  con `ufw delete`) y fail2ban solo se reinicia si cambia `jail.local`
  (así no se pierden los baneos activos).
- **Backblaze B2 CLI**: instala el binario `b2` en `/usr/local/bin/` (eligiendo
  variante `-aarch64` si aplica). Los crons que lo usan pertenecen a cada rol
  de app. Requiere autorización manual fuera de banda (`b2 account authorize`)
  hasta que las credenciales se gestionen vía SOPS.

## Variables

| Variable | Descripción | Default |
|----------|-------------|---------|
| `docker_host_user` | Usuario que ejecuta Docker rootless y es propietario de los compose | `ubuntu` |
| `docker_host_storage_driver` | Storage driver de Docker (`""` = default; `fuse-overlayfs` en tests anidados) | `""` |
| `docker_host_enable_ufw` | Instalar y configurar UFW | `true` |
| `docker_host_enable_fail2ban` | Instalar y configurar fail2ban | `true` |
| `docker_host_enable_unattended_upgrades` | Instalar y configurar unattended-upgrades | `true` |
| `docker_host_b2_cli_enabled` | Instalar el CLI de Backblaze B2 | `true` |
| `docker_host_b2_version` | Versión del CLI de Backblaze B2 | `4.7.1` |

`docker_host_user` se comparte con los roles de app (cada uno replica el
default para poder ejecutarse en solitario); sobrescríbela en
`group_vars/docker_servers.yml` para cambiarla en todas partes.

## Facts derivados

El rol calcula y deja en el play (vía `set_fact`):

- `docker_host_uid`: UID de `docker_host_user`.
- `docker_host_socket_path`: socket rootless de Docker
  (`/run/user/<uid>/docker.sock`), que consumen los roles de app.

## Uso

```yaml
- hosts: docker_servers
  roles:
    - docker_host   # primero
    - caddy         # reverse proxy
    - nextcloud_aio # las apps, después
    - wallabag      # opcional (inerte hasta wallabag_enabled: true)
```
