# Plan: Test del backup/restore de Nextcloud AIO usando el backup de producción en B2

## Estado actual

**Fase 1 implementada y funcionando.** Se ha creado un test reproducible con Molecule que verifica el backup de producción descargado de Backblaze B2. El test levanta un contenedor Podman, comprueba la integridad del repositorio Borg y valida que contiene los usuarios esperados (`cesar` y `nuria`).

Se deja también un playbook Ansible local equivalente para ejecuciones rápidas sin contenedor.

**Fase 2 (parcial, implementada y validada): escenario Molecule que instala el rol `nextcloud_aio` y deja una instancia de AIO funcional para restore manual.** Se ha creado el escenario `aio-functional`, que ejecuta el rol Ansible completo (Docker rootless anidado, mastercontainer, Caddy) dentro de un contenedor de prueba y deja la interfaz de administración de AIO accesible desde el navegador del host, con el backup y la passphrase montados dentro, para que el restore se compruebe **a mano** a través del asistente web de AIO. No se automatiza el propio restore (ver sección "Por qué no automatizar el restore" más abajo). De camino se encontraron y corrigieron dos bugs reales del rol (no específicos de Molecule). El usuario ya restauró el backup real y se verificó con `occ` que los usuarios y ficheros están intactos. Ver detalle en "Pasos implementados → 6".

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

**Fase 2 (parcial, implementada): escenario Molecule `aio-functional` con el rol real, para restore manual.**

En vez de automatizar el restore contra la API interna (no documentada) del mastercontainer de AIO, se optó por que Molecule se limite a levantar una instancia de AIO **funcional y accesible** — instalando el rol `nextcloud_aio` de verdad — con el backup y la passphrase ya disponibles dentro del contenedor. El restore en sí se hace a mano desde el navegador, siguiendo el asistente de AIO. Ver "Pasos implementados → 6" para el detalle técnico y los hallazgos.

**Fase 2 (pendiente): automatizar la sincronización B2 → local.**

Una vez demostrado que el backup es restaurable, se añadirá al rol Ansible la descarga/sincronización automática del repositorio Borg desde B2 antes de ejecutar un restore, y se documentará el timer/servicio necesario para mantener una copia local sincronizada.

## Por qué no otras opciones

- **Crear un backup nuevo en el test**: No valida el backup de producción real, que es lo que queremos probar.
- **Descargar directamente desde B2 dentro del test**: Como la sincronización es manual y queríamos priorizar la verificación, es más rápido usar la copia local temporal.
- **Terraform + OCI (nueva instancia de prueba)**: Máxima fidelidad, pero tiene coste, es lenta y no es iterable en local.
- **Driver `podman` de `molecule-plugins`**: Tiene problemas de compatibilidad con Ansible 2.20 en este entorno (`parsing reference ""`, `ALLOW_BROKEN_CONDITIONALS`). El driver `default` con playbooks personalizados funciona.
- **Automatizar el restore vía la API interna del mastercontainer de AIO**: Investigado en detalle (código de `nextcloud/all-in-one`, `php/src/Controller/DockerController.php`, `ConfigurationController.php`, `LoginController.php`). El restore se dispara con `POST /api/docker/restore` con `selected_restore_time`, pero ese valor no es el nombre del archive de Borg: hay que autenticarse primero (token de los logs del mastercontainer o password), fijar la ubicación/passphrase vía `POST /api/configuration`, lanzar `POST /api/docker/backup-list` y luego parsear el HTML de `GET /containers` para sacar `backup_times` (no hay endpoint JSON). Es un API interno, no documentado ni versionado — automatizarlo dejaría el test frágil ante cualquier cambio de AIO. Se prefirió que Molecule deje el entorno listo y el restore se compruebe a mano.
- **Docker rootless anidado dentro de un contenedor Podman *rootless***: Probado y descartado. Falla con `newuidmap: write to uid_map failed: Operation not permitted` al intentar crear el segundo nivel de user namespaces — limitación conocida de Podman rootless (no puede delegar más privilegio de que el que él mismo tiene). Solución adoptada: el contenedor de prueba se crea con Podman **rootful** (`sudo podman`, ver más abajo), lo que sí permite el anidamiento de Docker rootless dentro.

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

### 6. Escenario Molecule `aio-functional`: instala el rol real y deja AIO funcional

Ruta del escenario: `jilguedev/ansible/roles/nextcloud_aio/molecule/aio-functional/`.

**Objetivo del escenario:** a diferencia de `b2-restore` (que solo lee el repositorio Borg con `borg`/`borgbackup`), este escenario ejecuta el **rol Ansible `nextcloud_aio` de verdad** — Docker rootless, mastercontainer, Caddy — dentro de un contenedor de prueba, y deja la interfaz de administración de AIO accesible desde `https://localhost:8443` en el host real, con el backup de producción y la passphrase ya montados dentro del contenedor. El restore se hace **a mano**, siguiendo el asistente web de AIO (decisión explícita, ver "Por qué no otras opciones").

#### Hallazgo 1: Docker rootless anidado necesita un contenedor exterior *rootful*

Docker rootless dentro de un contenedor Podman rootless falla (`newuidmap: Operation not permitted`): Podman rootless no puede delegar una segunda capa de user namespaces porque él mismo no tiene privilegio real de root. La solución es crear el contenedor de prueba con Podman **root** (`sudo podman`).

Para no tener que dar `sudo` sin restricciones, se añadió una regla sudoers acotada al binario `podman`:

```
# /etc/sudoers.d/cesar-podman (aplicado por el usuario, con visudo)
cesar ALL=(root) NOPASSWD: /usr/bin/podman
```

Esto es un cambio en el sistema del host (no en el repo) — queda documentado aquí porque es un requisito para ejecutar este escenario en cualquier máquina de desarrollo.

Con esa regla, ni `become: true` de Ansible ni el escenario en sí pueden invocar sudo directamente sobre el intérprete de Python del módulo (eso pediría contraseña, porque la regla solo cubre `/usr/bin/podman`). En su lugar:

- `create.yml`/`destroy.yml` pasan `executable: "{{ playbook_dir }}/files/sudo-podman"` al módulo `containers.podman.podman_container`.
- El resto de tareas (`converge.yml`, `verify.yml`) llegan al contenedor vía el plugin de conexión `podman`, al que se le indica el mismo wrapper mediante la variable de entorno `ANSIBLE_PODMAN_EXECUTABLE` (configurada en `molecule.yml`, `provisioner.env`).
- El wrapper es `molecule/aio-functional/files/sudo-podman`: un script de una línea (`exec sudo -n podman "$@"`).

#### Hallazgo 2: overlayfs nativo no funciona en Docker anidado tan profundo

Con Docker rootless ya instalado, `docker run` fallaba al montar el filesystem overlay (`invalid argument`). Se resuelve forzando el storage driver `fuse-overlayfs` (paquete `fuse-overlayfs` + `"storage-driver": "fuse-overlayfs"` en `daemon.json`). Se añadió la variable de rol `nextcloud_aio_docker_storage_driver` (vacía por defecto = comportamiento de producción sin cambios) para poder activarlo solo en este escenario.

#### Dos bugs reales del rol encontrados y corregidos (no específicos de Molecule)

1. **`/etc/apt/keyrings` se creaba con modo `0750`.** El usuario de sandbox de apt (`_apt`) no tiene grupo `root`, así que no podía ni recorrer el directorio para leer la keyring de Docker, aunque el fichero en sí fuera 644. Resultado: `apt-get update` fallaba con `NO_PUBKEY ...` al instalar Docker CE, en cualquier despliegue real, no solo en el test. Corregido a `0755` (el permiso que recomienda la propia documentación de Docker).
2. **`daemon.json` generaba JSON inválido** al activar `nextcloud_aio_docker_storage_driver`: se construía con concatenación de cadenas Jinja (`'...\n...' if ... else ''`), y `\n` dentro de un literal de cadena Jinja no se interpreta como salto de línea, así que quedaba un `\` literal rompiendo el JSON. Corregido usando `{% if %}` directamente en el bloque de contenido en vez de construir la cadena a mano.

#### Variables de rol nuevas (`defaults/main.yml`)

- `nextcloud_aio_mastercontainer_ip_binding` (por defecto `127.0.0.1`): IP a la que se vincula el puerto 8080 del mastercontainer. En producción se deja en loopback; el escenario de test lo pone en `0.0.0.0` para poder publicar el puerto hacia el host real.
- `nextcloud_aio_docker_storage_driver` (por defecto `""` = driver nativo de Docker): permite forzar `fuse-overlayfs`, necesario en contenedores anidados.

#### Cómo se protege el backup real de producción

`create.yml` monta el backup de producción (`tmp/nextcloud-aio-borg-backup/`) y la passphrase (`.borg.txt`) **solo de lectura**, en rutas de "staging" (`/mnt/aio-backup-source`, `/mnt/aio-borg-passphrase-source`) dentro del contenedor. `converge.yml` los copia (`cp -a`/`ansible.builtin.copy` con `remote_src`) a rutas que viven enteramente en el filesystem del contenedor. Esto es necesario porque el propio rol hace `chown`/`chmod` sobre `nextcloud_aio_backup_dir`: si esa ruta fuera el mismo bind-mount que el directorio real del host, esas llamadas cambiarían los permisos del backup de producción en el disco real. Verificado tras el test: `tmp/nextcloud-aio-borg-backup/` y `.borg.txt` conservan su propietario/permisos originales.

#### Archivos del escenario

- `molecule.yml`: driver `default`; `provisioner.env` fija `ANSIBLE_PODMAN_EXECUTABLE` y `ANSIBLE_ROLES_PATH` (necesario porque el escenario vive dentro de `roles/nextcloud_aio/molecule/`, y sin esto Ansible no encuentra el rol al incluirlo por nombre).
- `inventory.yml`: host `aio-functional-test`, imagen `geerlingguy/docker-ubuntu2204-ansible` (systemd de PID 1, necesario para systemd de usuario/rootless Docker), puerto publicado `8443`.
- `create.yml`: crea el contenedor con Podman root, `systemd: always`, `privileged: true`, monta los orígenes de solo lectura del backup/passphrase.
- `converge.yml`: dos plays — (1) bootstrap como root: crea el usuario `aiotest`, sudo sin contraseña (solo dentro del contenedor descartable), copia el backup/passphrase a rutas nativas del contenedor; (2) incluye el rol `nextcloud_aio` conectando como `aiotest`, con hardening (UFW/fail2ban/unattended-upgrades/timer de backup) desactivado porque es ortogonal a lo que este escenario valida.
- `verify.yml`: comprueba que `https://localhost:8080` (dentro del contenedor) responde, y muestra por pantalla las instrucciones de restore manual (URL publicada, ruta del backup, ruta de la passphrase).
- `destroy.yml`: elimina el contenedor (mismo wrapper `sudo-podman`).
- `files/sudo-podman`: wrapper `exec sudo -n podman "$@"`.

#### Uso

```bash
cd jilguedev/ansible/roles/nextcloud_aio
poetry run molecule converge --scenario-name aio-functional
poetry run molecule verify --scenario-name aio-functional   # opcional: reachability + instrucciones
```

Luego, en el navegador: `https://localhost:8443` (certificado autofirmado, aceptar el aviso). En el asistente de AIO, indicar como ubicación del backup `/home/aiotest/nextcloud-aio-backups` y la passphrase de `/home/aiotest/borg-passphrase.txt` dentro del contenedor (o `.borg.txt` en la raíz del repo). Cuando se termine de comprobar:

```bash
poetry run molecule destroy --scenario-name aio-functional
```

`molecule test` ejecuta el ciclo completo (incluyendo `destroy` al final) y sirve como comprobación de que el rol converge y la UI responde, pero para el flujo de "restaurar y comprobar a mano" hay que usar `converge`/`destroy` por separado, sin dejar que `molecule test` destruya el contenedor antes de tiempo.

**Validado en esta sesión:** `molecule converge` y `molecule verify` completan sin fallos; `curl -sk https://localhost:8443` desde el host real (fuera del contenedor) devuelve `302` (login de AIO); dentro del contenedor anidado se ven corriendo `nextcloud-aio-mastercontainer` y `caddy`. El restore manual vía navegador lo hizo el usuario y se verificó con éxito (ver "Comandos de verificación" más abajo).

### 7. Acceso por navegador a la instancia real de Nextcloud (no solo al panel de AIO) y causa raíz de la inestabilidad

Además del panel de administración de AIO (puerto 8080), se quiso poder entrar también a la instancia real de Nextcloud restaurada.

**Hallazgo importante: el restore también restaura la configuración del propio mastercontainer.** El dominio (`aio.callepuzzle.com`), `overwritehost` y `overwriteprotocol=https` vienen en el volumen `nextcloud_aio_mastercontainer` restaurado, y el contenedor `nextcloud-aio-nextcloud` los reaplica en cada arranque vía la variable `NC_DOMAIN` que le pasa el mastercontainer — cambiar `nextcloud_aio_domain` en Ansible no tiene efecto sobre una instancia restaurada. Acceder en HTTP plano por la IP del contenedor funciona para ver la página de login, pero no para iniciar sesión de verdad: Nextcloud marca las cookies de sesión como `Secure` porque cree que la conexión es HTTPS, y el navegador las descarta si la conexión real es HTTP.

**Solución adoptada:**

- Nueva variable de rol `nextcloud_aio_caddy_tls_internal` (por defecto `false`): añade la directiva `tls internal` al `Caddyfile`, para que Caddy emita un certificado autofirmado local en vez de pedir uno real a Let's Encrypt (necesario porque el dominio de test no es alcanzable desde internet).
- En el escenario `aio-functional` se fija `nextcloud_aio_domain: aio.callepuzzle.com` (para que coincida exactamente con el dominio ya restaurado, en vez de inventar uno nuevo) y `nextcloud_aio_caddy_tls_internal: true`.
- Como Caddy usa `network_mode: host` dentro del Docker anidado, y el contenedor exterior corre con Podman *rootful* (cuya red bridge es directamente enrutable desde el host real, a diferencia de rootless/slirp4netns), no hace falta publicar el puerto 443: Caddy es alcanzable directamente en la IP del contenedor (`podman inspect <contenedor> --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'`, típicamente algo como `10.88.0.x`).
- Para el navegador del host real: añadir una entrada temporal en `/etc/hosts` (`<IP-del-contenedor> aio.callepuzzle.com`) y aceptar el aviso de certificado autofirmado.

**Causa raíz real de los fallos intermitentes (502, `procReady not received`, `fork/exec ... resource temporarily unavailable`):** no era Apache, ni Caddy, ni la red — era el **`pids-limit` por defecto de Podman (2048)**, que en un contenedor creado sin `--pids-limit` explícito limita la suma de *todos* los procesos/hilos de *todos* los contenedores anidados (mastercontainer + apache + nextcloud + postgres + redis + clamav + imaginary + notify-push + fail2ban + ...). En reposo el uso rondaba ~680/2048, pero en picos (reinicio de contenedores, Apache creando sus hilos de `mpm_event`, o simplemente `docker exec`) se superaba la cuota y cualquier `fork()`/`clone()` en cualquier punto del stack anidado fallaba con `EAGAIN` de forma aparentemente aleatoria. `podman container update --pids-limit`/`--cpus`/`--cpuset-cpus` en caliente no funciona en este contenedor (crun rechaza cualquier actualización de recursos en contenedores `--privileged` con programa BPF de dispositivos: `updating device access list not supported when using BPFProgram`), así que hay que fijarlo **en la creación**. Corregido en `create.yml` añadiendo `pids_limit: "-1"` (sin límite) al `containers.podman.podman_container`. Tras recrear el contenedor con este cambio, tanto Apache como `docker exec` dejaron de fallar.

**Dos mejoras adicionales al rol, encontradas al perseguir este problema:**

3. **`docker-compose.yml` cambiaba pero nada reiniciaba el stack.** La tarea que arranca `docker-compose-nextcloud` usa `state: started`, que no reinicia un servicio ya activo aunque el fichero subyacente cambie. Cualquier cambio a una variable que afecte al compose (como las dos añadidas en esta sesión) se quedaba sin aplicar hasta que alguien lo reiniciara a mano. Corregido: se registra el resultado de la tarea `Copy docker-compose.yml` y, si cambió, se ejecuta `docker compose up -d` para reconciliar.
4. **Lo mismo con el Caddyfile**, que ni siquiera es parte de la definición del servicio de compose (es un fichero montado): un cambio no provoca que Caddy lo relea. Corregido con una tarea que hace `docker restart caddy` cuando el Caddyfile cambia.

**Nota para producción:** ninguno de estos cuatro cambios de rol (`nextcloud_aio_mastercontainer_ip_binding`, `nextcloud_aio_docker_storage_driver`, `nextcloud_aio_caddy_tls_internal`, el `pids_limit` del escenario) afecta al comportamiento por defecto — todo son variables nuevas con el valor por defecto que preserva el comportamiento actual. Las dos correcciones de "aplicar cambios sin reiniciar a mano" (`docker compose up -d` y `docker restart caddy` condicionados) sí son mejoras de comportamiento en producción: antes, cambiar cualquiera de estas variables en un despliegue ya instalado no tenía efecto hasta un reinicio manual.

**Importante — efecto secundario de reiniciar el mastercontainer sobre una instancia ya restaurada:** cada vez que `docker compose up -d` recrea el mastercontainer (por un cambio en `docker-compose.yml`), los contenedores que el mastercontainer gestiona internamente (apache, base de datos, redis, clamav, ...) se paran y **no se reinician solos** — hay que pulsar el botón de arrancar/reiniciar contenedores en el panel de AIO. Esto ocurrió dos veces durante esta sesión al iterar sobre la config. No se ha intentado automatizar (requeriría hablar con la API interna de AIO, ver "Por qué no otras opciones"); si se vuelve a tocar `nextcloud_aio_mastercontainer_ip_binding`, `nextcloud_aio_apache_ip_binding` o similar sobre una instancia ya en marcha, hay que contar con este paso manual.

### Comandos de verificación (occ + SQL) para futuros tests

Todos ejecutados así (sustituir el contenedor/credenciales según haga falta):

```bash
DOCKER="sudo podman exec --user aiotest -e XDG_RUNTIME_DIR=/run/user/1000 \
  -e DOCKER_HOST=unix:///run/user/1000/docker.sock aio-functional-test docker"
```

**Estado general y usuarios:**

```bash
$DOCKER exec --user www-data nextcloud-aio-nextcloud php occ status
$DOCKER exec --user www-data nextcloud-aio-nextcloud php occ user:list
$DOCKER exec --user www-data nextcloud-aio-nextcloud php occ check
$DOCKER exec --user www-data nextcloud-aio-nextcloud php occ files:scan <usuario>
```

**Fichero modificado más reciente** (`occ` no tiene un comando directo para esto; se consulta el filesystem — la imagen usa BusyBox, que no soporta `find -printf`, por eso se usa `stat` vía `-exec`):

```bash
$DOCKER exec nextcloud-aio-nextcloud sh -c '
find /mnt/ncdata -type f -not -path "*/appdata_*/*" -not -path "*/files_versions/*" \
  -exec stat -c "%Y %y %n" {} \; 2>/dev/null | sort -rn | head -20
'
```

**Último evento de calendario modificado** (útil como comprobación de "frescura": comparar contra la fecha/hora del archive de Borg restaurado). Requiere las credenciales de `dbname`/`dbuser`/`dbpassword` de `/var/www/html/config/config.php` dentro de `nextcloud-aio-nextcloud`:

```bash
$DOCKER exec nextcloud-aio-nextcloud grep -A3 "'dbname'\|'dbuser'\|'dbpassword'\|'dbhost'" /var/www/html/config/config.php

$DOCKER exec -e PGPASSWORD='<dbpassword>' nextcloud-aio-database \
  psql -h localhost -U oc_nextcloud -d nextcloud_database -c "
SELECT calendarid, uri, to_timestamp(lastmodified) AS lastmodified, componenttype,
       substring(convert_from(calendardata,'UTF8') from 'SUMMARY:([^\r\n]*)') AS summary,
       substring(convert_from(calendardata,'UTF8') from 'DTSTART[^:]*:([^\r\n]*)') AS dtstart
FROM oc_calendarobjects
ORDER BY lastmodified DESC
LIMIT 5;
"
```

`calendardata` es `bytea`; hay que convertirlo con `convert_from(..., 'UTF8')` antes de aplicar `substring` con regex, si no Postgres intenta resolver `substring(bytea, text)` como `substring(string, start_int)` y falla con `invalid input syntax for type integer`.

**Resultado obtenido en esta sesión (2026-08-06):** usuarios `admin`, `cesar`, `nuria` presentes; `occ check` sin errores; `files:scan cesar` → 174 carpetas / 1605 ficheros, 0 errores; fichero real más reciente de nuria con fecha 2026-07-30 (ningún dato posterior, coherente con que no se subió nada nuevo desde entonces); evento de calendario más reciente modificado el 2026-08-05 18:59:09, horas antes de que se tomara el archive de backup usado (`20260806_040126` → 2026-08-06 04:01) — confirma que el backup capturó cambios recientes.

## Criterios de éxito

### Fase 1 (cumplidos)

- [x] El backup de B2 está disponible en `tmp/nextcloud-aio-borg-backup/`.
- [x] `molecule test --scenario-name b2-restore` pasa sin intervención manual.
- [x] `borg check` sobre la copia local no reporta errores.
- [x] Se ha demostrado que el backup contiene los usuarios `cesar` y `nuria`.
- [x] Playbook local `verify-b2-backup.yml` funciona como alternativa.

### Fase 2 (parcial)

- [x] Escenario Molecule (`aio-functional`) que instala el rol `nextcloud_aio` real (Docker rootless anidado, mastercontainer, Caddy) en un contenedor de prueba.
- [x] La interfaz de administración de AIO es accesible desde el navegador del host real (`https://localhost:8443`), con el backup y la passphrase de producción disponibles dentro del contenedor.
- [x] Dos bugs reales del rol corregidos en el proceso (permisos de `/etc/apt/keyrings`, JSON inválido en `daemon.json` con storage driver personalizado).
- [x] El backup y la passphrase reales del host quedan protegidos frente a mutación durante el test (montaje de solo lectura + copia a ruta nativa del contenedor).
- [x] Restaurar el backup a través del asistente web de AIO y comprobar los datos. Hecho por el usuario el 2026-08-06; verificado con `occ` y consultas SQL directas — ver "Comandos de verificación (occ + SQL) para futuros tests" más abajo. Incluye una comprobación de **frescura**: el último evento de calendario modificado (`2026-08-05 18:59:09`) es horas anterior al momento en que se tomó el backup (`20260806_040126` → 2026-08-06 04:01), confirmando que la copia capturó cambios recientes y no es una copia obsoleta.
- [x] Diagnosticada y corregida la causa de la inestabilidad intermitente del contenedor anidado (`pids-limit` por defecto de Podman demasiado bajo para todo el stack de AIO combinado) — ver "Pasos implementados → 7".
- [x] Comprobación de frescura del backup (no solo que los datos existen, sino que son los más recientes): último evento de calendario modificado horas antes del archive de backup usado.
- [ ] Acceso por navegador a la instancia real de Nextcloud (no solo al panel de AIO) con login funcional: la infraestructura para ello (Caddy con `tls internal`, dominio alineado con el restaurado, IP de apache expuesta) está lista y compilada, pero no se ha vuelto a probar de punta a punta tras corregir el `pids-limit` — probable que ya funcione, pendiente de repetir la comprobación.
- [ ] Elegir herramienta de sincronización (recomendado `rclone`).
- [ ] Añadir al rol Ansible la sincronización B2 → local.
- [ ] Documentar credenciales y passphrase via SOPS.

## Notas de seguridad

- La carpeta `tmp/nextcloud-aio-borg-backup/` contiene datos reales de producción y está en `.gitignore`. No debe comitearse.
- `.borg.txt` contiene la passphrase de Borg y también está en `.gitignore`.
- Las credenciales de B2 deben seguir en `jilguedev/secrets.enc.yaml` (SOPS) y no en texto plano.
- El volumen del backup se monta como lectura/escritura en el contenedor porque `borg check` necesita crear un lock. El test no modifica el contenido del backup.

## Nota sobre fidelidad

El escenario `b2-restore` (Fase 1) valida que el **backup de producción en B2 es legible y contiene los datos esperados**, sin desplegar infraestructura real.

El escenario `aio-functional` (Fase 2, parcial) sí despliega el rol real y valida que **Docker rootless + mastercontainer + Caddy arrancan y la UI de AIO responde**, dentro de un contenedor de prueba (no una VM OCI). No valida UFW/fail2ban/unattended-upgrades (desactivados a propósito en el test) ni el propio restore (que se deja para verificación manual del usuario vía el asistente web). Tampoco automatiza la sincronización B2 → local, que sigue siendo manual.
