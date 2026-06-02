# Plan: Revisión de código — fixes post-merge (diff contra main)

> Plan generado a partir de la revisión de código del diff actual contra `main`. Cada ítem es una tarea accionable con prioridad, archivo afectado y acción recomendada.

---

## 🔴 CRÍTICO

### Tarea 1: Eliminar secretos expuestos en `README.md`
- [ ] **Archivo:** `README.md`
- [ ] **Líneas:** 23–24

**Problema:** El README contiene en texto plano lo que parece ser una contraseña/seed de AIO (`mocker purgatory scam ...`) y un token/ID de backup (`a4ede937...`). Además, la línea 13 referencia un socket de Podman (`/run/user/1000/podman/podman.sock`) que ya no se usa en el flujo actual.

**Acción:**
1. Eliminar inmediatamente esa información del README.
2. Si esos secretos son válidos en producción, **rotarlos** (ya están en el historial de git).
3. Añadir `README.md` a una lista de revisión pre-commit si se incluirán notas operativas temporales.

---

### Tarea 2: Bajar requisito de Python en `pyproject.toml`
- [ ] **Archivo:** `jilguedev/ansible/pyproject.toml`
- [ ] **Línea:** 8

**Problema:**
```toml
requires-python = ">=3.14"
```
Esto es excesivamente restrictivo. Ubuntu 24.04 LTS (la imagen probable de OCI) trae Python 3.12. Ansible 13.6 funciona perfectamente desde 3.10+. Esto impedirá que Poetry resuelva dependencias en la mayoría de entornos.

**Acción:** Cambiar a `requires-python = ">=3.10"` (o `>=3.12` como mínimo realista).

---

### Tarea 3: Corregir idempotencia rota en `loginctl enable-linger`
- [ ] **Archivo:** `jilguedev/ansible/roles/nextcloud_aio/tasks/main.yml`
- [ ] **Línea:** 72

**Problema:**
```yaml
changed_when: true
```
Esto marca la tarea como `changed` en cada ejecución, rompiendo la idempotencia y los reportes de Ansible.

**Acción:** Reemplazar por:
```yaml
- name: Check if linger is enabled
  ansible.builtin.stat:
    path: "/var/lib/systemd/linger/{{ docker_user }}"
  register: linger_stat
  changed_when: false

- name: Enable linger for user
  ansible.builtin.command: loginctl enable-linger {{ docker_user }}
  when: not linger_stat.stat.exists
  become: true
```

---

## 🟠 ALTO

### Tarea 4: Corregir `creates` en `dockerd-rootless-setuptool.sh`
- [ ] **Archivo:** `jilguedev/ansible/roles/nextcloud_aio/tasks/main.yml`
- [ ] **Líneas:** 75–81

**Problema:**
```yaml
creates: "/home/{{ docker_user }}/.config/docker/daemon.json"
```
La siguiente tarea sobreescribe ese archivo. Si `daemon.json` ya existe, `dockerd-rootless-setuptool.sh` no se ejecutará, pero el entorno rootless podría no estar completamente inicializado (faltan unit files de systemd u otros archivos).

**Acción:** Cambiar el `creates` a algo que indique que la inicialización rootless ya ocurrió:
```yaml
creates: "/home/{{ docker_user }}/.config/systemd/user/docker.service"
```

---

### Tarea 5: Corregir dependencia `docker.socket` en systemd user service
- [ ] **Archivo:** `jilguedev/ansible/roles/nextcloud_aio/templates/docker-compose.service.j2`
- [ ] **Líneas:** 4–5

**Problema:**
```ini
Wants=docker.socket
After=docker.socket
```
En Docker rootless (user scope), no siempre existe un unit `docker.socket`. Docker rootless expone el socket directamente vía `docker.service`.

**Acción:** Cambiar a:
```ini
Wants=docker.service
After=docker.service
```
O eliminar esas líneas y confiar solo en el `ConditionPathExists` que ya está presente.

---

### Tarea 6: Evaluar `ExecStop=docker compose down` vs `stop`
- [ ] **Archivo:** `jilguedev/ansible/roles/nextcloud_aio/templates/docker-compose.service.j2`
- [ ] **Línea:** 16

**Problema:**
```ini
ExecStop=/usr/bin/docker compose down
```
Esto elimina los contenedores (no solo los detiene) cuando se hace `systemctl --user stop docker-compose-nextcloud`. Para infraestructura persistente, `down` puede ser destructivo.

**Acción:** Considerar usar `stop` en lugar de `down`:
```ini
ExecStop=/usr/bin/docker compose stop
```
Si el comportamiento deseado es realmente destruirlos al parar el servicio, documentar esa decisión explícitamente.

---

## 🟡 MEDIO

### Tarea 7: Parametrizar `NEXTCLOUD_TRUSTED_PROXIES`
- [ ] **Archivo:** `jilguedev/ansible/roles/nextcloud_aio/templates/docker-compose.yml.j2`
- [ ] **Línea:** 20

**Problema:**
```yaml
NEXTCLOUD_TRUSTED_PROXIES: 127.0.0.1
```
Aunque con Caddy en `network_mode: host` funciona, si en el futuro se añade otro reverse proxy o el LB de OCI hace NAT adicional, esto fallará silenciosamente (redirecciones erróneas, problemas con WebDAV, etc.).

**Acción:**
1. Añadir a `defaults/main.yml`:
   ```yaml
   nextcloud_aio_trusted_proxies: "127.0.0.1"
   ```
2. Usar en el template:
   ```yaml
   NEXTCLOUD_TRUSTED_PROXIES: "{{ nextcloud_aio_trusted_proxies }}"
   ```

---

### Tarea 8: Revisar healthcheck del mastercontainer
- [ ] **Archivo:** `jilguedev/ansible/roles/nextcloud_aio/templates/docker-compose.yml.j2`
- [ ] **Líneas:** 34–39

**Problema:**
```yaml
healthcheck:
  test: ["CMD", "curl", "-fsSL", "http://localhost:8080"]
```
La imagen de AIO no garantiza que tenga `curl` instalado. Alpine suele traer `wget` por defecto.

**Acción:** Verificar si la imagen tiene `curl` o `wget`. Si no se está seguro, usar:
```yaml
test: ["CMD", "wget", "--spider", "-q", "http://localhost:8080"]
```

---

### Tarea 9: Reforzar reglas UFW para el puerto 8080
- [ ] **Archivo:** `jilguedev/ansible/roles/nextcloud_aio/tasks/main.yml`
- [ ] **Líneas:** 140–151

**Problema:** El orden de reglas en UFW importa. Si hay una regla anterior que permite 8080 (de un playbook previo o configuración manual), la denegación no tendrá efecto.

**Acción:** Considerar añadir una tarea para resetear/asegurar UFW antes de aplicar reglas, o documentar explícitamente que el orden es importante y que el default policy es `deny`.

---

### Tarea 10: Considerar `AIO_DISABLE_BACKUP_SECTION`
- [ ] **Archivo:** `jilguedev/ansible/roles/nextcloud_aio/templates/docker-compose.yml.j2`

**Problema:** No hay configuración de `AIO_DISABLE_BACKUP_SECTION`. Dado que ya existe un systemd timer para backups automatizados, podría ser útil ocultar la sección de backup en la UI de AIO para evitar manipulación manual.

**Acción:** Evaluar si se quiere deshabilitar la sección de backup en la UI:
```yaml
AIO_DISABLE_BACKUP_SECTION: true
```
Si no, documentar que la UI permite backups manuales independientemente del timer.

---

## 🟢 BAJO / MEJORAS

### Tarea 11: Actualizar `all-in-one/docker-compose.yml` (ejemplo Podman)
- [ ] **Archivo:** `all-in-one/docker-compose.yml`
- [ ] **Línea:** 13

**Problema:**
```yaml
- /run/user/1000/podman/podman.sock:/var/run/docker.sock:ro
```
Este archivo parece ser un ejemplo/referencia. Ya que se migró a Docker rootless, el socket de referencia debería ser el de Docker.

**Acción:** Actualizar el socket a `/run/user/1000/docker.sock` o añadir un comentario indicando que es un ejemplo legado para Podman.

---

### Tarea 12: Parametrizar clave SSH en Terraform
- [ ] **Archivo:** `jilguedev/main.tf`
- [ ] **Línea:** 83

**Problema:**
```hcl
ansible_ssh_private_key_file: ~/.ssh/id_ed25519
```
Hardcodeado al entorno local del autor. Si otro desarrollador usa otra clave, fallará.

**Acción:** Considerar parametrizar con una variable de Terraform:
```hcl
variable "ssh_private_key_path" {
  default = "~/.ssh/id_ed25519"
}
```

---

### Tarea 13: Archivar o limpiar `.plans/` tras implementación
- [ ] **Directorio:** `.plans/`

**Problema:** Son 6+ planes de implementación en Markdown. Útiles como documentación histórica, pero una vez implementados y mergeados, aumentan el ruido en el repo.

**Acción:** Considerar moverlos a `docs/plans/` o a una wiki tras cerrar este ciclo de desarrollo.

---

## Checklist global

- [ ] Ningún secreto en texto plano en el repositorio
- [ ] `pyproject.toml` usa `requires-python >=3.10`
- [ ] Ansible es idempotente (ninguna tarea falsa `changed` en re-runs)
- [ ] Docker rootless se inicializa correctamente en instancias nuevas
- [ ] El servicio systemd de compose arranca tras reboot sin errores de dependencia
- [ ] UFW bloquea efectivamente el puerto 8080 desde fuera
- [ ] Healthchecks de contenedores funcionan con las herramientas disponibles en la imagen
