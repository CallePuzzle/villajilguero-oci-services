# Plan: Migrar de Podman a Docker Rootless para Nextcloud AIO

## Problema
Nextcloud AIO requiere Docker API v1.44. Podman no es 100% compatible con la API de Docker y no está soportado oficialmente por los mantenedores de Nextcloud AIO. La documentación oficial recomienda usar Docker (incluyendo Docker rootless) o la instalación manual.

## Enfoque
Migrar el rol Ansible `nextcloud_aio` de Podman a **Docker Rootless**. Docker rootless ejecuta el daemon de Docker como usuario sin privilegios (sin root), manteniendo la seguridad similar a Podman.

## Cambios necesarios

### 1. `roles/nextcloud_aio/tasks/main.yml`
- **Eliminar** la instalación de paquetes Podman (`podman`, `podman-compose`, `podman-docker`, `slirp4netns`, `uidmap`)
- **Añadir** instalación de Docker CE oficial (repo de Docker, no el de Ubuntu) + `docker-compose-plugin`
- **Añadir** configuración de Docker rootless:
  - Instalar `docker-ce-rootless-extras`
  - Configurar `sysctl` para unprivileged user namespaces (necesario para Docker rootless)
  - Inicializar Docker rootless para el usuario (`dockerd-rootless-setuptool.sh install`)
- **Mantener** `loginctl enable-linger` (necesario para que el daemon rootless sobreviva al logout)
- **Actualizar** la ruta del socket: de `/run/user/<uid>/podman/podman.sock` a `/run/user/<uid>/docker.sock`
- **Actualizar** el servicio systemd: de `podman-compose` a `docker compose`
- **Mantener** las tareas de creación de directorios, templates, y espera al servicio

### 2. `roles/nextcloud_aio/templates/docker-compose.yml.j2`
- Cambiar el mount del socket de `{{ podman_socket_path }}` a `{{ docker_socket_path }}`
- Eliminar `WATCHTOWER_DOCKER_SOCKET_PATH` (es específico de Podman)
- Mantener `SKIP_DOMAIN_VALIDATION: true`

### 3. `roles/nextcloud_aio/templates/podman-compose.service.j2` → renombrar a `docker-compose.service.j2`
- Cambiar descripción a "Docker Compose - Nextcloud AIO"
- Cambiar dependencia de `podman.socket` a `docker.socket` (el socket del usuario rootless)
- Cambiar `ExecStart` de `/usr/bin/podman-compose up -d` a `/usr/bin/docker compose up -d`
- Cambiar `ExecStop` de `/usr/bin/podman-compose down` a `/usr/bin/docker compose down`
- Cambiar variable de entorno de `PODMAN_SOCK` a `DOCKER_HOST`

### 4. `roles/nextcloud_aio/defaults/main.yml`
- Renombrar/actualizar variables: `podman_user` → `docker_user` (o mantener `podman_user` para no romper inventory)
- Añadir `docker_socket_path` con la ruta del socket rootless

### 5. `group_vars/podman_servers.yml`
- Actualizar variables para reflejar el cambio a Docker

### 6. `inventory/oci_podman.yml`
- Renombrar grupo de `podman_servers` a `docker_servers` (o mantener para compatibilidad)
- Eliminar `podman_uid` hardcodeado (se calcula dinámicamente)

### 7. `playbook.yml`
- Actualizar nombre/descripción del playbook

## Consideraciones de seguridad
- Docker rootless ejecuta contenedores en un namespace de usuario, sin necesidad de root
- Los contenedores no tienen acceso real a root del host
- Es la alternativa recomendada por Docker para entornos donde no se quiere dar privilegios de root

## Pasos de Docker rootless en Ubuntu
1. Añadir repo oficial de Docker
2. Instalar `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`, `docker-ce-rootless-extras`
3. Configurar sysctl `kernel.unprivileged_userns_clone=1` y `net.ipv4.ip_unprivileged_port_start=0`
4. Ejecutar `dockerd-rootless-setuptool.sh install` como el usuario
5. Establecer `DOCKER_HOST=unix:///run/user/<uid>/docker.sock`
