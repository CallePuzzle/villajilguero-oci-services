# Plan: Optimización de Nextcloud All-in-One en jilguedev

## Estado actual

El despliegue de Nextcloud AIO en `jilguedev/` consta de:

- **Terraform**: Provisions una instancia OCI Ubuntu mediante el módulo local `terraform-module-k0s-oci` con `enable_k0s = false`. Genera un inventario Ansible dinámico. No configura reglas de firewall/NSG en OCI para restringir puertos.
- **Ansible**: Instala Docker CE rootless, despliega un compose con Caddy como reverse proxy, y gestiona el arranque via systemd user service.
- **Docker Compose** (`docker-compose.yml.j2`):
  - Mastercontainer en red `nextcloud-aio` con `APACHE_PORT=11000`, `APACHE_IP_BINDING=0.0.0.0`, `SKIP_DOMAIN_VALIDATION=true`.
  - Caddy en la misma red `nextcloud-aio` con Caddyfile apuntando a `nextcloud-aio-apache:11000`.
  - Puerto `8080` (AIO interface) expuesto públicamente.
  - Sin `NEXTCLOUD_DATADIR`, `NEXTCLOUD_MEMORY_LIMIT`, `NEXTCLOUD_UPLOAD_LIMIT`, `NEXTCLOUD_MAX_TIME`, `BORG_RETENTION_POLICY`, `AIO_LOG_LEVEL`.
  - Sin healthchecks.
- **Systemd service** (`docker-compose.service.j2`): Usa `Wants=docker.service` / `After=docker.service`, lo cual es incorrecto en Docker rootless (el daemon corre como servicio de usuario, no del sistema).
- **Hardening**: No hay configuración de firewall (`ufw`), `fail2ban`, `unattended-upgrades`, ni hardening del SO.
- **Backup**: Sin configuración de BorgBackup ni automatización.

## Hallazgos de la investigación (repo oficial nextcloud/all-in-one)

### Configuración crítica del reverse proxy
La documentación oficial ([reverse-proxy.md](https://github.com/nextcloud/all-in-one/blob/main/reverse-proxy.md)) describe dos formas de usar Caddy:

1. **Caddy en `network_mode: host`** (recomendado para simplicidad): Caddy accede a `localhost:11000`. Requiere `APACHE_IP_BINDING=127.0.0.1`.
2. **Caddy y AIO en la misma red Docker bridge**: Requiere `APACHE_ADDITIONAL_NETWORK=<nombre-red>` para que el contenedor `nextcloud-aio-apache` (creado dinámicamente por el mastercontainer) se una a esa red. Sin esta variable, Caddy no puede resolver `nextcloud-aio-apache:11000`.

El template actual intenta la Opción 2 pero **falta `APACHE_ADDITIONAL_NETWORK`**, por lo que el reverse proxy no funcionará correctamente tras el primer despliegue.

### Variables de entorno esenciales (no configuradas)
- `NEXTCLOUD_DATADIR`: Path host para los datos. **Solo se puede definir antes de la primera instalación**; cambiarlo después implica pérdida de datos. Recomendado para producción/dev persistente.
- `NEXTCLOUD_MEMORY_LIMIT`: Default 512M, insuficiente. Recomendado 2048M-4096M.
- `NEXTCLOUD_UPLOAD_LIMIT` / `NEXTCLOUD_MAX_TIME`: Ajustar según necesidades de carga.
- `BORG_RETENTION_POLICY`: Política de retención de backups (ej: `--keep-within=7d --keep-weekly=4 --keep-monthly=6`).
- `AIO_LOG_LEVEL`: Reducir ruido de logs (`warn`).
- `NEXTCLOUD_TRUSTED_PROXIES` / `ADDITIONAL_TRUSTED_PROXY`: Necesario cuando el reverse proxy no es localhost, para que Nextcloud registre IPs reales de clientes y funcionen correctamente WebDAV, clientes móviles, etc.

### Seguridad
- **Puerto 8080**: La interfaz admin de AIO usa HTTPS con cert autofirmado. Expuesto públicamente incrementa la superficie de ataque. Debe restringirse a localhost/VPN o al menos protegerse con firewall.
- **SELinux/AppArmor**: Aunque Ubuntu no usa SELinux por defecto, en OCI pueden aplicarse perfiles AppArmor. La documentación menciona `security_opt: ["label:disable"]` para SELinux.
- **Trusted proxies**: Sin configurar, Nextcloud no confiará en las cabeceras `X-Forwarded-*` de Caddy, pudiendo causar redirecciones erróneas o problemas de autenticación.
- **HSTS y headers de seguridad**: El Caddyfile oficial no incluye `Strict-Transport-Security` ni redirecciones `.well-known` para CardDAV/CalDAV.

### Mantenimiento
- **Actualizaciones automáticas**: AIO incluye Watchtower, pero se recomienda ejecutar `/daily-backup.sh` con `AUTOMATIC_UPDATES=1` para backups + updates programados.
- **Healthchecks**: Los contenedores oficiales soportan `/healthcheck.sh`. Es buena práctica añadirlos en compose.
- **Log driver de Docker**: Configurar `logging: { driver: "local" }` para evitar crecimiento descontrolado de logs en `/var/lib/docker`.
- **Systemd rootless**: El servicio user no debe depender de `docker.service` (system), sino del socket o del servicio user de Docker (`docker-rootless.service` o similar).

### Backup
- **BorgBackup integrado**: AIO gestiona backups de PostgreSQL, datos Nextcloud y configuración del mastercontainer desde la UI.
- **Backup remoto**: Soporta repositorios Borg remotos via SSH con claves generadas automáticamente y modo append-only.
- **Automatización externa**: Se puede ejecutar `docker exec --env DAILY_BACKUP=1 nextcloud-aio-mastercontainer /daily-backup.sh` via cron/systemd timer.
- **Volúmenes críticos**: `nextcloud_aio_mastercontainer` (nombre inmutable) y `NEXTCLOUD_DATADIR` si se define.

### Hardening del sistema operativo (no implementado)
- **Firewall `ufw`**: Permitir solo 22 (SSH), 80, 443 y restringir 8080.
- **`fail2ban`**: Proteger SSH y eventualmente la interfaz web.
- **`unattended-upgrades`**: Actualizaciones de seguridad automáticas.
- **Docker daemon hardening**: Configurar `daemon.json` con log-driver, userns-remap (ya es rootless, pero se puede afinar), live-restore.

## Propuesta de implementación

### Opción A: Producción completa con Caddy en host network (Recomendada)
Usar `network_mode: host` para Caddy (como en el ejemplo oficial) y `APACHE_IP_BINDING=127.0.0.1`. Esto elimina la complejidad de `APACHE_ADDITIONAL_NETWORK`, DNS interno de Docker y `NEXTCLOUD_TRUSTED_PROXIES`.

Cambios:
1. **Terraform**:
   - Añadir recurso `oci_core_network_security_group` / `oci_core_network_security_group_security_rule` (o usar las del módulo subyacente si expone outputs) para restringir puertos: permitir 22, 80, 443 desde cualquier origen; restringir 8080 a IPs administrativas (o denegar explícitamente).
2. **Ansible - Rol `nextcloud_aio`**:
   - Corregir `docker-compose.yml.j2`:
     - Caddy: `network_mode: host`, puertos 80/443/443udp directamente.
     - Mastercontainer: eliminar red personalizada (usar `network_mode: bridge` como en el oficial), exponer solo `8080` (preferiblemente bind a `127.0.0.1:8080:8080` o restringir via firewall).
     - Añadir variables: `NEXTCLOUD_DATADIR`, `NEXTCLOUD_MEMORY_LIMIT=2048M`, `NEXTCLOUD_UPLOAD_LIMIT=16G`, `NEXTCLOUD_MAX_TIME=3600`, `BORG_RETENTION_POLICY`, `AIO_LOG_LEVEL=warn`.
     - Añadir `logging: { driver: "local" }` a todos los servicios.
     - Añadir `healthcheck` al mastercontainer.
   - Corregir `Caddyfile.j2`:
     - Apuntar a `localhost:11000`.
     - Añadir `header Strict-Transport-Security max-age=31536000`.
     - Añadir redirecciones `.well-known/carddav` y `.well-known/caldav`.
   - Corregir `docker-compose.service.j2`:
     - Cambiar dependencias: `Wants/After` deben apuntar al servicio de Docker rootless del usuario (`docker-rootless.service` o `docker.service` del user), no al del sistema. Alternativamente, usar `ConditionPathExists=/run/user/%U/docker.sock`.
   - Añadir tareas de hardening:
     - Instalar y configurar `ufw` (allow 22,80,443; deny 8080 o restrict).
     - Instalar y configurar `fail2ban` para SSH.
     - Instalar `unattended-upgrades`.
     - Crear `/home/{{ docker_user }}/.config/docker/daemon.json` con `log-driver: local` y `live-restore: false` (rootless tiene limitaciones).
   - Añadir tareas de backup:
     - Crear systemd user timer + service para ejecutar diariamente: `docker exec --env DAILY_BACKUP=1 --env AUTOMATIC_UPDATES=1 nextcloud-aio-mastercontainer /daily-backup.sh`.
     - Documentar en README cómo configurar Borg remoto desde la UI de AIO.
3. **Documentación**:
   - Actualizar `AGENTS.md` o README de `jilguedev/` con procedimiento de backup, restauración y mantenimiento.

### Opción B: Mantener red Docker bridge (más contenerizada)
Mantener Caddy y AIO en la red `nextcloud-aio` pero corrigiendo la configuración para que funcione correctamente.

Cambios:
1. **Terraform**: Igual que Opción A (firewall).
2. **Ansible - Rol `nextcloud_aio`**:
   - Corregir `docker-compose.yml.j2`:
     - Añadir `APACHE_ADDITIONAL_NETWORK: nextcloud-aio` para que el contenedor `nextcloud-aio-apache` se una a la red.
     - Añadir `NEXTCLOUD_TRUSTED_PROXIES` con la IP/subred de Caddy (o `172.0.0.0/8` de forma controlada) para que Nextcloud confíe en el reverse proxy.
     - Mismas variables de entorno, logging, healthchecks y corrección de systemd service que en Opción A.
     - Puerto 8080: bind a `127.0.0.1:8080:8080` si es posible, o restringir via firewall.
   - Corregir `Caddyfile.j2`:
     - Mantener `reverse_proxy nextcloud-aio-apache:11000` (ahora funcionará gracias a `APACHE_ADDITIONAL_NETWORK`).
     - Añadir headers HSTS y redirecciones well-known.
   - Hardening del SO y backup: idéntico a Opción A.
3. **Documentación**: Igual que Opción A.

## Archivos a modificar
- `jilguedev/main.tf` (añadir reglas de firewall NSG)
- `jilguedev/ansible/roles/nextcloud_aio/templates/docker-compose.yml.j2`
- `jilguedev/ansible/roles/nextcloud_aio/templates/Caddyfile.j2`
- `jilguedev/ansible/roles/nextcloud_aio/templates/docker-compose.service.j2`
- `jilguedev/ansible/roles/nextcloud_aio/tasks/main.yml` (nuevas tareas de hardening y backup)
- `jilguedev/ansible/roles/nextcloud_aio/defaults/main.yml` (nuevas variables parametrizables)
- `jilguedev/ansible/group_vars/docker_servers.yml` (posiblemente añadir vars de datadir, dominio, etc.)
- `jilguedev/README.md` o `AGENTS.md` (documentación de operaciones)

## Notas importantes
- `NEXTCLOUD_DATADIR` **solo debe establecerse antes del primer arranque** de Nextcloud. Si ya existe una instalación previa en la VM, cambiarlo requeriría migración manual o recreación.
- La corrección del systemd service es crítica para que el arranque automático funcione correctamente tras reboots en Docker rootless.
- Las reglas de firewall en OCI son críticas porque actualmente no hay restricciones de red explícitas en el módulo Terraform mostrado.
