# Plan: Ansible para gestión de Nextcloud AIO con Podman

## Resumen

Añadir Ansible al proyecto `villajilguero-oci-services` para gestionar el despliegue y ciclo de vida de Nextcloud AIO via Podman en la instancia OCI. Terraform se mantiene responsable de la infraestructura; Ansible toma el control de la configuración del nodo y el orquestado de contenedores.

## Contexto Actual

- El módulo `terraform-module-k0s-oci` ya soporta `deployment_mode = "podman"`.
- El `user-data.sh.tmpl` ya instala `podman`, `podman-compose` y habilita el socket.
- Existe `all-in-one/docker-compose.yml` preparado para Podman (usa `/run/user/1000/podman/podman.sock`).
- Falta: automatizar la copia del compose, la configuración rootless completa y el servicio systemd persistente.

## Cambios Propuestos

### 1. Nueva estructura de directorios Ansible

```
ansible/
├── ansible.cfg
├── inventory/
│   └── oci_podman.yml          # Inventario dinámico (generado por Terraform)
├── group_vars/
│   └── podman_servers.yml      # Variables comunes
├── roles/
│   └── nextcloud_aio/
│       ├── tasks/
│       │   └── main.yml
│       ├── templates/
│       │   └── podman-compose.service.j2
│       └── defaults/
│           └── main.yml
└── playbook.yml
```

### 2. Modificar `jilguedev/main.tf` (y/o crear nuevo workspace)

Agregar outputs útiles para Ansible:

```hcl
output "ansible_inventory" {
  value = <<-EOT
    podman_servers:
      hosts:
        ${module.oci-k0s.public_ip}:
          ansible_user: ubuntu
          ansible_ssh_private_key_file: ~/.ssh/id_rsa
          podman_user: ubuntu
          podman_uid: 1000
    EOT
}
```

Opcionalmente, usar `local_file` para escribir `ansible/inventory/oci_podman.yml` automáticamente.

### 3. Playbook Ansible (`ansible/playbook.yml`)

Tareas principales:

1. **Habilitar linger** para usuario `ubuntu` (permite que los servicios rootless persistan tras logout).
2. **Configurar Podman rootless**: crear `~/.config/containers/containers.conf` si es necesario.
3. **Copiar `docker-compose.yml`** a `~ubuntu/nextcloud-aio/docker-compose.yml`.
4. **Asegurar socket de Podman** en la ruta esperada (`/run/user/1000/podman/podman.sock`).
5. **Crear servicio systemd** para el compose vía `podman generate systemd` o un unit file custom.
6. **Iniciar y habilitar** el servicio (`systemctl --user enable --now podman-compose-nextcloud`).
7. **Healthcheck opcional**: esperar a que el puerto 8080 responda.

### 4. Servicio systemd rootless (`templates/podman-compose.service.j2`)

Unit file de usuario que ejecute `podman-compose up -d` en el directorio del proyecto.

### 5. Variables de rol (`defaults/main.yml`)

- `nextcloud_aio_compose_path`: `/home/ubuntu/nextcloud-aio`
- `nextcloud_aio_compose_file`: `docker-compose.yml`
- `podman_user`: `ubuntu`
- `podman_uid`: `1000`

## Dependencias

- `ansible-core` o `ansible` en la máquina de control (local).
- Conexión SSH a la instancia OCI (ya disponible via clave pública/privada).
- Módulo `containers.podman` de Ansible (colección de community).

## Compatibilidad

- No afecta el modo `k0s` existente.
- El modo `podman` en Terraform seguirá funcionando igual; Ansible es una capa opcional de gestión post-provision.

## Próximos pasos tras aprobar

1. Crear directorios y archivos Ansible.
2. Ajustar outputs de Terraform para generar inventario.
3. Ejecutar `ansible-playbook -i ansible/inventory/oci_podman.yml ansible/playbook.yml`.
