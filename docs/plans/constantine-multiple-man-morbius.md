# Plan: Test del backup/restore de Nextcloud AIO usando el backup de producción en B2

## Estado actual

**Fase 1 implementada y funcionando.** Se ha creado un test reproducible con Molecule que verifica el backup de producción descargado de Backblaze B2. El test levanta un contenedor Podman, comprueba la integridad del repositorio Borg y valida que contiene los usuarios esperados (`cesar` y `nuria`).

Se deja también un playbook Ansible local equivalente para ejecuciones rápidas sin contenedor.

## Objetivo

Validar que el backup de producción de Nextcloud AIO almacenado en Backblaze B2 (`b2://callepuzzle-nextcloud-borg-backup/`) es usable: repositorio íntegro, archives presentes y datos reales recuperables (usuarios `cesar` y `nuria`). La sincronización a B2 se hace manualmente hoy; este plan cubre la **primera prueba funcional** y deja preparado el camino para automatizar la sincronización si el test es exitoso.

## Decisión

**Fase 1 (implementada): test con Molecule + Podman.**

El test parte del backup real de producción, que se deja en `tmp/nextcloud-aio-borg-backup/` (carpeta ignorada por git). El escenario Molecule (`jilguedev/ansible/roles/nextcloud_aio/molecule/b2-restore/`) usa el driver `default` con playbooks `create.yml` y `destroy.yml` personalizados que gestionan directamente el contenedor Podman, evitando los bugs del driver `podman` de `molecule-plugins` con Ansible 2.20.

El flujo del test:

1. Crea un contenedor `python:3.12-slim-bookworm` con Podman.
2. Monta el repo y el backup en el contenedor.
3. Instala `borgbackup`.
4. Ejecuta `borg check` sobre el repositorio.
5. Lista los archives.
6. Extrae el dump SQL de PostgreSQL.
7. Verifica que los usuarios `cesar` y `nuria` aparecen en la tabla `oc_users`.
8. Destruye el contenedor.

**Playbook local alternativo:** `jilguedev/ansible/playbooks/verify-b2-backup.yml` realiza la misma verificación sin contenedor, útil para comprobaciones rápidas.

**Fase 2 (pendiente): automatizar la sincronización B2 → local.**

Una vez demostrado que el backup es restaurable, se añadirá al rol Ansible la descarga/sincronización automática del repositorio Borg desde B2 antes de ejecutar un restore, y se documentará el timer/servicio necesario para mantener una copia local sincronizada.

## Por qué no otras opciones

- **Crear un backup nuevo en el test**: No valida el backup de producción real, que es lo que queremos probar.
- **Descargar directamente desde B2 dentro del test**: Como la sincronización es manual y queríamos priorizar la verificación, es más rápido usar la copia local temporal.
- **Terraform + OCI (nueva instancia de prueba)**: Máxima fidelidad, pero tiene coste, es lenta y no es iterable en local.
- **Driver `podman` de `molecule-plugins`**: Tiene problemas de compatibilidad con Ansible 2.20 en este entorno (`parsing reference ""`, `ALLOW_BROKEN_CONDITIONALS`). El driver `default` con playbooks personalizados funciona.

## Pasos implementados

### 1. Dependencias de Poetry

Añadidas a `jilguedev/ansible/pyproject.toml`:

```toml
[tool.poetry]
package-mode = false

[project]
dependencies = [
    "ansible (>=13.6.0,<14.0.0)",
    "molecule (>=25.0.0,<26.0.0)",
    "molecule-plugins[podman] (>=23.0.0,<24.0.0)",
    "pytest-testinfra (>=10.0.0,<11.0.0)"
]
```

Ejecutado:

```bash
cd jilguedev/ansible
poetry lock
poetry install
```

### 2. Test con Molecule

Ruta del escenario: `jilguedev/ansible/roles/nextcloud_aio/molecule/b2-restore/`

Archivos:

- `molecule.yml`: driver `default`, secuencia de test personalizada, referencia al `requirements.yml` de colecciones.
- `inventory.yml`: define el host `b2-restore-test`, la imagen del contenedor y las variables del test.
- `requirements.yml`: colección `containers.podman`.
- `create.yml`: crea el contenedor Podman, monta volúmenes y espera a que esté listo.
- `destroy.yml`: elimina el contenedor.
- `converge.yml`: instala `borgbackup`.
- `verify.yml`: verifica el backup y los usuarios.

Ejecución:

```bash
cd jilguedev/ansible/roles/nextcloud_aio
poetry run molecule test --scenario-name b2-restore
```

Resultado del test (éxito):

```text
Backup verification passed: users cesar, nuria found in database dump.
```

### 3. Playbook Ansible local alternativo

Ruta: `jilguedev/ansible/playbooks/verify-b2-backup.yml`

Realiza la misma verificación que Molecule pero directamente en el host, sin contenedor. Útil para comprobaciones rápidas.

Ejecución:

```bash
cd jilguedev/ansible
poetry run ansible-playbook playbooks/verify-b2-backup.yml
```

### 4. Ajustes al rol

No ha sido necesario modificar el rol `nextcloud_aio` para esta fase. Las adaptaciones para un restore completo (tag `aio-deploy`, soporte rootful, etc.) se dejan para la Fase 2.

### 5. `.gitignore`

Añadidos:

```gitignore
.venv*/
tmp/
```

Ya existía `.borg.txt`.

## Criterios de éxito

### Fase 1 (cumplidos)

- [x] El backup de B2 está disponible en `tmp/nextcloud-aio-borg-backup/`.
- [x] `molecule test --scenario-name b2-restore` pasa sin intervención manual.
- [x] `borg check` sobre la copia local no reporta errores.
- [x] Se ha demostrado que el backup contiene los usuarios `cesar` y `nuria`.
- [x] Playbook local `verify-b2-backup.yml` funciona como alternativa.

### Fase 2 (pendiente)

- [ ] Elegir herramienta de sincronización (recomendado `rclone`).
- [ ] Añadir al rol Ansible la sincronización B2 → local.
- [ ] Documentar credenciales y passphrase via SOPS.
- [ ] (Opcional) Extender el escenario Molecule para hacer un restore completo de AIO.

## Notas de seguridad

- La carpeta `tmp/nextcloud-aio-borg-backup/` contiene datos reales de producción y está en `.gitignore`. No debe comitearse.
- `.borg.txt` contiene la passphrase de Borg y también está en `.gitignore`.
- Las credenciales de B2 deben seguir en `jilguedev/secrets.enc.yaml` (SOPS) y no en texto plano.
- El volumen del backup se monta como lectura/escritura en el contenedor porque `borg check` necesita crear un lock. El test no modifica el contenido del backup.

## Nota sobre fidelidad

Este test valida que el **backup de producción en B2 es legible y contiene los datos esperados**. No valida la infraestructura completa (OCI, Docker rootless, UFW, fail2ban) ni la automatización de la subida a B2, que hoy se hace manualmente. La Fase 2 se encargará de la automatización de la bajada/sincronización y, eventualmente, de un restore completo de AIO validado por Molecule.
