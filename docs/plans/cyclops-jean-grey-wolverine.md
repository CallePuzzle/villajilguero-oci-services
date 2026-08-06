# Plan: Habilitar backup local en Nextcloud AIO de jilguedev

## Resumen

El backup diario de Nextcloud AIO en `jilguedev` estaba configurado para ejecutarse, pero fallaba silenciosamente porque no había ningún destino de backup (local ni remoto) configurado. AIO requiere que `/mnt/borgbackup` sea un mountpoint; al no serlo, el contenedor `nextcloud-aio-borgbackup` salía con código `1` y no se creaba ningún archivo de backup.

Este plan documenta los cambios manuales aplicados en producción y los ajustes necesarios en Ansible para que futuras instalaciones ya vengan preparadas para el backup local.

## Problema diagnosticado

- `nextcloud-aio-backup.timer` estaba activo y el servicio se ejecutaba a las `02:00 UTC`.
- `systemd` reportaba `SUCCESS` porque el script `/daily-backup.sh` del mastercontainer solo espera a que el contenedor `nextcloud-aio-borgbackup` se detenga, sin comprobar su código de salida.
- El contenedor `nextcloud-aio-borgbackup` fallaba con:
  ```text
  /mnt/borgbackup is not a mountpoint which is not allowed.
  ```
- Causa raíz: `AIO_DISABLE_BACKUP_SECTION=true` ocultaba la sección de backup en la UI, por lo que nunca se configuró un destino de backup.
- El volumen `nextcloud_aio_backup_cache` solo contenía cache; no había repositorio Borg ni archivos de backup.

## Cambios manuales aplicados en producción

### 1. Directorio de backup local

Creado en el servidor `143.47.33.25`:

```bash
mkdir -p /home/ubuntu/nextcloud-aio-backups
chmod 750 /home/ubuntu/nextcloud-aio-backups
chown ubuntu:ubuntu /home/ubuntu/nextcloud-aio-backups
```

Espacio disponible en disco: **176 GB libres** en `/`. Los datos actuales de Nextcloud ocupan aproximadamente **7 GB**.

### 2. Modificación de `docker-compose.yml`

Archivo: `/home/ubuntu/nextcloud-aio/docker-compose.yml`

Cambios:
- `AIO_DISABLE_BACKUP_SECTION: true` → `AIO_DISABLE_BACKUP_SECTION: false`
- Añadido bind mount al mastercontainer:
  ```yaml
  volumes:
    - nextcloud_aio_mastercontainer:/mnt/docker-aio-config
    - /run/user/1001/docker.sock:/var/run/docker.sock:ro
    - /home/ubuntu/nextcloud-aio-backups:/home/ubuntu/nextcloud-aio-backups
  ```

Se dejó una copia de seguridad del archivo original en:
`/home/ubuntu/nextcloud-aio/docker-compose.yml.backup.<timestamp>`

### 3. Re-aplicación del compose

```bash
cd /home/ubuntu/nextcloud-aio
docker compose up -d
```

Solo se reinició el contenedor `nextcloud-aio-mastercontainer`; el resto del stack (Nextcloud, PostgreSQL, Redis, Apache, etc.) siguió corriendo sin interrupción.

### 4. Configuración pendiente por el usuario

Tras los cambios, la UI de AIO expone la sección **Backup & Restore**. El usuario debe:

1. Abrir un túnel SSH:
   ```bash
   ssh -L 8080:localhost:8080 -i ~/.ssh/id_ed25519 ubuntu@143.47.33.25
   ```
2. Acceder a `https://localhost:8080`.
3. En **Backup & Restore**, introducir como ubicación de backup:
   ```text
   /home/ubuntu/nextcloud-aio-backups
   ```
4. Guardar la contraseña de encriptación de Borg fuera del servidor.
5. Lanzar un backup manual de prueba y verificar que el contenedor `nextcloud-aio-borgbackup` termina con código `0`.

## Cambios necesarios en Ansible

Para que futuras instalaciones no repitan el mismo problema:

### 1. `jilguedev/ansible/roles/nextcloud_aio/defaults/main.yml`

```yaml
# Habilitar la sección de backup en la UI de AIO
nextcloud_aio_disable_backup_section: false

# Directorio local para backups de Borg (vacío = sin backup local configurado)
nextcloud_aio_backup_dir: /home/ubuntu/nextcloud-aio-backups
```

### 2. `jilguedev/ansible/roles/nextcloud_aio/tasks/main.yml`

Añadir una tarea que cree el directorio de backup local:

```yaml
- name: Create local backup directory
  ansible.builtin.file:
    path: "{{ nextcloud_aio_backup_dir }}"
    state: directory
    owner: "{{ docker_user }}"
    group: "{{ docker_user }}"
    mode: "0750"
  when: nextcloud_aio_backup_dir | length > 0
```

### 3. `jilguedev/ansible/roles/nextcloud_aio/templates/docker-compose.yml.j2`

Añadir el bind mount del directorio de backup:

```jinja2
    volumes:
      - nextcloud_aio_mastercontainer:/mnt/docker-aio-config
      - {{ docker_socket_path }}:/var/run/docker.sock:ro
{% if nextcloud_aio_backup_dir | length > 0 %}
      - {{ nextcloud_aio_backup_dir }}:{{ nextcloud_aio_backup_dir }}
{% endif %}
```

Y asegurar que `AIO_DISABLE_BACKUP_SECTION` use la variable:

```jinja2
      AIO_DISABLE_BACKUP_SECTION: {{ nextcloud_aio_disable_backup_section | lower }}
```

## Verificación tras aplicar Ansible

1. Ejecutar el playbook en una instalación nueva o existente:
   ```bash
   cd jilguedev/ansible
   poetry run ansible-playbook -i inventory/oci_docker.yml playbook.yml
   ```
2. Comprobar que el directorio de backup existe y pertenece a `ubuntu`.
3. Acceder a la UI de AIO y configurar `/home/ubuntu/nextcloud-aio-backups` como destino de backup.
4. Ejecutar un backup manual y verificar:
   ```bash
   docker inspect --format='{{.State.ExitCode}}' nextcloud-aio-borgbackup
   ```
   Debe devolver `0`.
5. Comprobar que el timer automático sigue activo:
   ```bash
   systemctl --user status nextcloud-aio-backup.timer
   ```

## Notas sobre el timer de backup

El `nextcloud-aio-backup.timer` **sí sigue teniendo sentido** y no debe eliminarse. Este timer es el que ejecuta diariamente:

```bash
docker exec --env DAILY_BACKUP=1 --env AUTOMATIC_UPDATES=1 nextcloud-aio-mastercontainer /daily-backup.sh
```

Sin él, no habría backups automáticos ni actualizaciones automáticas de contenedores. El problema no era el timer, sino la falta de destino de backup.

Una vez configurado el destino en la UI, el timer seguirá funcionando correctamente a las `02:00 UTC`.
