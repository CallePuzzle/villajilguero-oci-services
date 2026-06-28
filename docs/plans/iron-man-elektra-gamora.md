# Plan: Caddy Reverse Proxy + LB HTTPS para Nextcloud AIO en jilguedev

## Resumen

Configurar Nextcloud AIO en `jilguedev/ansible/` con un reverse proxy **Caddy** que gestione automáticamente los certificados TLS para el dominio `aio.callepuzzle.com`, y adaptar el **Load Balancer de OCI** para que el tráfico público entre por el puerto 443 (TLS passthrough) directamente a Caddy.

## Contexto

- El workspace `jilguedev` usa una instancia plana OCI (`enable_k0s = false`) con Nextcloud AIO desplegado mediante Ansible + Docker Compose (rootless).
- Actualmente el LB de OCI solo escucha en HTTP (puerto 80) y redirige al backend en puerto 80.
- El archivo `all-in-one/docker-compose.yml` ya contiene un ejemplo comentado de configuración Caddy con Nextcloud AIO (`APACHE_PORT: 11000`, `APACHE_IP_BINDING: 127.0.0.1`, servicio `caddy` con `network_mode: "host"`).
- Caddy gestionará automáticamente los certificados Let's Encrypt para `aio.callepuzzle.com`.

## Cambios Propuestos

### 1. Ansible — Añadir Caddy como reverse proxy

**Archivo nuevo:** `jilguedev/ansible/roles/nextcloud_aio/templates/Caddyfile.j2`
```
aio.callepuzzle.com {
  reverse_proxy localhost:11000
}
```
Caddy escucha por defecto en 80 y 443. Al usar un dominio sin puerto explícito, Caddy configura automáticamente HTTP→HTTPS redirect y solicita certificados vía ACME.

**Modificar:** `jilguedev/ansible/roles/nextcloud_aio/templates/docker-compose.yml.j2`
- Añadir al servicio `nextcloud-aio-mastercontainer`:
  - `APACHE_PORT: 11000`
  - `APACHE_IP_BINDING: 127.0.0.1`
- Añadir servicio `caddy`:
  - Imagen: `caddy:alpine`
  - `restart: always`
  - `network_mode: "host"` (necesario para que Caddy pueda escuchar en 80/443 del host sin NAT de Docker)
  - Volumen que monte el `Caddyfile` generado en `/etc/caddy/Caddyfile`
  - Volúmenes nombrados: `caddy_config`, `caddy_data`
- Añadir volúmenes nombrados al final del compose:
  - `caddy_config`
  - `caddy_data`

**Modificar:** `jilguedev/ansible/roles/nextcloud_aio/tasks/main.yml`
- Añadir tarea para copiar el template `Caddyfile.j2` al directorio de composición (`{{ nextcloud_aio_compose_path }}/Caddyfile`), justo antes de copiar el `docker-compose.yml`.
- Actualizar la tarea `Wait for AIO interface to be available` para que espere a `https://localhost:11000` (puerto interno de Apache) en lugar de `https://localhost:8080`, ya que Caddy ahora expone el tráfico web en 443 y el AIO interface sigue en 8080. Se mantendrá el check a 8080 para verificar que el mastercontainer está levantado.

**Modificar:** `jilguedev/ansible/roles/nextcloud_aio/defaults/main.yml`
- Añadir variable `nextcloud_aio_domain: aio.callepuzzle.com` (usada por el template del Caddyfile).

### 2. Terraform Module — Load Balancer puerto 443 (TLS passthrough)

El módulo `terraform-module-k0s-oci/lb/` debe modificarse para permitir tráfico HTTPS.

**Modificar:** `terraform-module-k0s-oci/lb/main.tf`
- **Backend set existente**: cambiar a protocolo `TCP`, puerto de backend `443`, health checker `TCP` en puerto `443`.
- **Backend**: cambiar puerto a `443`.
- **Listener existente**: cambiar puerto a `443`, protocolo a `TCP`.
- Añadir un **segundo listener/backend-set** para el puerto 80 (HTTP) con protocolo `TCP`, de modo que Caddy pueda responder a los desafíos ACME HTTP-01 y redirigir a HTTPS. Este es opcional pero **recomendado** para que Let's Encrypt funcione sin problemas.

**Modificar:** `terraform-module-k0s-oci/lb/nsg.tf`
- Añadir regla NSG para permitir tráfico TCP en el puerto `443` desde `0.0.0.0/0`.

### 3. Validación de red

- El VCN ya tiene la regla de seguridad 443 permitida desde `local.subnet_cidr_block` (10.2.0.0/24), por lo que el LB (que reside en esa subnet) puede comunicarse con la instancia backend en 443.
- Caddy con `network_mode: "host"` escuchará en `0.0.0.0:443` y `0.0.0.0:80` del host, recibiendo directamente el tráfico del LB sin NAT de contenedores.

## Pasos de ejecución tras aprobar el plan

1. Crear/modificar los archivos Ansible indicados.
2. Modificar los archivos del módulo Terraform `terraform-module-k0s-oci/lb/`.
3. Ejecutar `terraform fmt` en `jilguedev/` y en `terraform-module-k0s-oci/`.
4. Ejecutar `terraform plan` en `jilguedev/` para validar los cambios de infraestructura.
5. Aplicar con `terraform apply`.
6. Ejecutar el playbook Ansible:
   ```bash
   cd jilguedev/ansible
   poetry run ansible-playbook -i inventory/oci_docker.yml playbook.yml
   ```
7. Verificar que Caddy responde en `https://aio.callepuzzle.com` y redirige correctamente a Nextcloud AIO.
8. Acceder a la interfaz de administración AIO vía túnel SSH:
   ```bash
   ssh -L 8080:localhost:8080 ubuntu@<public_ip>
   ```
   Luego `https://localhost:8080`.

## Notas

- Caddy gestiona automáticamente la renovación de certificados Let's Encrypt; no es necesario certbot ni cert-manager.
- El puerto 8080 (AIO interface) **no** se expone en el LB; se accede solo por túnel SSH por seguridad.
- Si en el futuro se quisiera terminar TLS en el LB de OCI en lugar de Caddy, sería necesario subir los certificados manualmente a OCI; el enfoque de passthrough a Caddy es más sencillo y automatizado.
