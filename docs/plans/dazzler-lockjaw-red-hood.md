# Plan: Convertir jilguedev a instancia plana con Podman + Nextcloud AIO

## Resumen

Transformar el workspace `jilguedev` de un despliegue k0s/Kubernetes a una instancia OCI plana que ejecute Nextcloud AIO mediante Podman. Terraform se encarga de la infraestructura; Ansible gestiona la configuración del nodo y el orquestado de contenedores.

## Contexto

- El módulo `terraform-module-k0s-oci` ya fue simplificado en `fire-wonder-man-pantha.md`: se eliminó toda la lógica de Podman del módulo. Ahora con `enable_k0s = false` crea una instancia Ubuntu limpia con red básica (puertos 22, 80, 443) y un Load Balancer en el puerto 80.
- El archivo `all-in-one/docker-compose.yml` ya existe y está preparado para Podman (usa `/run/user/1000/podman/podman.sock`).
- No existe infraestructura Ansible en el proyecto todavía.

## Cambios Propuestos

### 1. Simplificar `jilguedev/main.tf`

**Eliminar:**
- `data "sops_file" "argo"` y sus referencias
- `locals { argocd_host = ... }`
- `k0s_config_path`, `k0s_version`, `argocd_host`, `projects`, `argocd_values` del módulo
- Provider `b2` (Backblaze) si no se usa en otro lugar del workspace
- Cualquier output o recurso relacionado exclusivamente con k0s/ArgoCD

**Modificar:**
- `enable_k0s = false`
- Mantener `data "sops_file" "credentials"`, `provider "oci"`, y el módulo `oci-k0s` con los parámetros mínimos (`compartment_id`, `enable_k0s`, `ssh_public_key`)
- Añadir output `private_ip` útil para debug
- Añadir recurso `local_file.ansible_inventory` para generar automáticamente `ansible/inventory/oci_podman.yml`

### 2. Eliminar archivos obsoletos de `jilguedev/`

- `argocd-values.yaml.tmpl` (ya no aplica)
- Eliminar referencias a `k0sctl.yaml` si quedan

### 3. Crear estructura Ansible en `jilguedev/ansible/`

```
jilguedev/ansible/
├── ansible.cfg
├── inventory/
│   └── oci_podman.yml          # Generado por Terraform (local_file)
├── group_vars/
│   └── podman_servers.yml
├── playbook.yml
└── roles/
    └── nextcloud_aio/
        ├── defaults/
        │   └── main.yml
        ├── tasks/
        │   └── main.yml
        └── templates/
            ├── docker-compose.yml.j2
            └── podman-compose.service.j2
```

#### 3.1 `ansible.cfg`
Configuración básica apuntando al inventario generado.

#### 3.2 `group_vars/podman_servers.yml`
Variables comunes: `podman_user: ubuntu`, `podman_uid: 1000`, rutas del proyecto.

#### 3.3 `playbook.yml`
Playbook principal que aplica el rol `nextcloud_aio` a los hosts `podman_servers`.

#### 3.4 Rol `nextcloud_aio`

**`defaults/main.yml`:**
- `nextcloud_aio_compose_path`: `/home/ubuntu/nextcloud-aio`
- `nextcloud_aio_compose_file`: `docker-compose.yml`
- `podman_user`: `ubuntu`
- `podman_uid`: `1000`

**`tasks/main.yml`:**
1. Instalar `podman`, `podman-compose`, `slirp4netns` (si es necesario para rootless)
2. Habilitar `linger` para el usuario `ubuntu` (`loginctl enable-linger ubuntu`)
3. Crear directorio `~/nextcloud-aio` y subdirectorios de configuración si aplica
4. Copiar el template `docker-compose.yml.j2` a `~/nextcloud-aio/docker-compose.yml`
5. Asegurar que el socket de Podman esté disponible (`/run/user/1000/podman/podman.sock`)
6. Crear el servicio systemd de usuario desde el template `podman-compose.service.j2`
7. Recargar systemd de usuario (`systemctl --user daemon-reload`)
8. Iniciar y habilitar el servicio (`systemctl --user enable --now podman-compose-nextcloud`)
9. Healthcheck opcional: esperar a que `localhost:8080` responda (interfaz AIO)

**`templates/docker-compose.yml.j2`:**
Basado en `all-in-one/docker-compose.yml` con las siguientes adaptaciones para funcionar sin reverse proxy adicional y exponerse directamente al Load Balancer de OCI:
- Descomentar mapeo de puerto `80:80` para que el LB pueda llegar al contenedor Apache
- Eliminar `APACHE_PORT: 11000` y `APACHE_IP_BINDING: 127.0.0.1` (no se necesitan sin reverse proxy local)
- Mantener `SKIP_DOMAIN_VALIDATION: true`
- Mantener `WATCHTOWER_DOCKER_SOCKET_PATH: /run/user/1000/podman/podman.sock`
- Conservar el volumen `nextcloud_aio_mastercontainer`

**`templates/podman-compose.service.j2`:**
Unit file systemd de usuario (`~/.config/systemd/user/podman-compose-nextcloud.service`) que ejecute `podman-compose up -d` en el directorio del proyecto al arrancar.

### 4. Consideraciones de red y acceso

- **Puerto 80**: El Load Balancer de OCI escucha en 80 y redirige a la instancia en 80. Nextcloud AIO estará disponible públicamente vía HTTP en el dominio/DNS apuntado al LB.
- **Puerto 8080 (interfaz AIO)**: No está expuesto en el LB ni en las reglas de seguridad del VCN. Se accede vía túnel SSH para la configuración inicial:
  ```bash
  ssh -L 8080:localhost:8080 ubuntu@<public_ip>
  ```
  Luego abrir `https://localhost:8080` en el navegador.
- **Puerto 443/HTTPS**: El LB actual solo escucha en 80. En una fase posterior se podría añadir HTTPS (cert-manager no aplica aquí; se podría usar Caddy o certbot en la instancia, pero queda fuera del alcance de este plan).

### 5. Pasos de ejecución tras aprobar el plan

1. Editar `jilguedev/main.tf` según lo especificado.
2. Eliminar `jilguedev/argocd-values.yaml.tmpl`.
3. Crear todos los archivos Ansible listados.
4. Ejecutar `terraform fmt` en `jilguedev/`.
5. Ejecutar `terraform plan` en `jilguedev/` para validar.
6. Si el plan es correcto, aplicar con `terraform apply`.
7. Ejecutar el playbook Ansible:
   ```bash
   cd jilguedev/ansible
   ansible-playbook -i inventory/oci_podman.yml playbook.yml
   ```
8. Acceder vía túnel SSH al puerto 8080 para completar la configuración inicial de Nextcloud AIO.

## Notas

- Con `enable_k0s = false`, el módulo crea una instancia limpia. Ansible toma el control total del software instalado.
- El LB se mantiene activo (comportamiento del módulo), por lo que no es necesario configurar un reverse proxy adicional en la instancia para el tráfico básico.
- La interfaz de administración AIO (8080) queda intencionalmente no expuesta a Internet por seguridad; solo se accede por túnel SSH.
