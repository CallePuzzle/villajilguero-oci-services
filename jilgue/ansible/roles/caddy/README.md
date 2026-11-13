# caddy

Reverse proxy común a todas las apps: Caddy con compose propio (proyecto
`caddy`) en `network_mode: host`, escuchando en 80/443 (TCP+UDP para
HTTP/3). No despliega ninguna app; cada rol de app (`nextcloud_aio`,
`wallabag`, ...) escribe su snippet de sitio en el directorio de sitios y
reinicia el contenedor cuando cambia.

## Qué hace

- **Compose propio**: `docker-compose.yml` en `caddy_compose_path` con el
  servicio `caddy` (`caddy_image`), `network_mode: host` y los volúmenes
  nombrados `caddy_config` / `caddy_data` — los mismos que usaba el
  compose de AIO antes de #38, de modo que los certificados Let's Encrypt
  existentes se conservan sin re-emisión.
- **Caddyfile base**: importa los snippets del directorio de sitios
  (`caddy_sites_path`, montado en `/etc/caddy/sites`) e incluye un
  placeholder `:80` para que la config siga siendo válida cuando todavía
  no existe ningún snippet. El placeholder solo responde por HTTP a hosts
  que ningún snippet reclama: las redirecciones automáticas HTTP→HTTPS de
  los sitios importados y los retos ACME HTTP-01 tienen prioridad sobre
  él.
- **Unit systemd** `docker-compose-caddy.service` (ámbito usuario):
  oneshot + `RemainAfterExit` que lanza `docker compose up -d` cuando el
  socket rootless está disponible.
- **Migración con guard** (layout anterior a #38): si existe un contenedor
  `caddy` del proyecto compose de AIO
  (`com.docker.compose.project=nextcloud-aio`), el rol **no lo toca**: lo
  deja sirviendo, habilita la unit sin arrancarla y exporta
  `caddy_legacy_migration_pending: true`. Mientras ese fact está activo,
  los roles de app no reinician el proxy. El traspaso lo hace el handler
  al final del play (`tasks/migrate_legacy.yml`), solo si ninguna tarea
  ha fallado y hay al menos un snippet:
  1. para el contenedor antiguo y lo renombra a `caddy-legacy-pre38`;
  2. arranca el compose propio y espera a que esté `healthy`;
  3. borra el antiguo.

  Si el nuevo no queda `healthy`, hace rollback automático al antiguo y
  deshabilita la unit. Los volúmenes nombrados no se borran nunca. El
  corte dura segundos y los certificados no se reemiten. En hosts recién
  instalados o ya migrados el guard no hace nada. Procedimiento completo
  y rollback manual: [`jilgue/MIGRATION.md`](../../../MIGRATION.md).
  Lo cubre el escenario de Molecule `caddy-migration`.

## Variables

| Variable | Descripción | Default |
|----------|-------------|---------|
| `caddy_compose_path` | Directorio del proyecto compose | `/home/ubuntu/caddy` |
| `caddy_compose_file` | Nombre del fichero compose | `docker-compose.yml` |
| `caddy_sites_path` | Directorio de snippets que importa el Caddyfile | `{{ caddy_compose_path }}/sites` |
| `caddy_container_name` | Nombre del contenedor del proxy | `caddy` |
| `caddy_image` | Imagen de Caddy | `caddy:alpine` |
| `docker_host_user` | Usuario que ejecuta Docker rootless y es propietario del compose (compartido con los roles de app) | `ubuntu` |
| `caddy_legacy_compose_project` | Proyecto compose cuyo contenedor `caddy` se considera legacy y se migra | `nextcloud-aio` |
| `caddy_legacy_backup_name` | Nombre temporal del contenedor legacy durante el traspaso (para rollback) | `{{ caddy_container_name }}-legacy-pre38` |

## Facts derivados

El rol deja en el play (vía `set_fact`, que tiene prioridad sobre los
defaults que cada rol de app replica):

- `caddy_sites_path`: directorio de sitios resuelto; los roles de app
  escriben ahí sus snippets (p. ej. `nextcloud.caddy`).
- `caddy_container_name`: contenedor que los roles de app deben reiniciar
  tras cambiar un snippet (`docker restart caddy`).
- `caddy_legacy_migration_pending`: `true` mientras el traspaso desde el
  layout anterior a #38 esté pendiente. Los roles de app **no** deben
  reiniciar el proxy en ese caso (ver el patrón de abajo).

## Uso

```yaml
- hosts: docker_servers
  roles:
    - docker_host   # primero
    - caddy         # este rol
    - nextcloud_aio # las apps, después
```

Patrón para un rol de app (snippet + reinicio del proxy):

```yaml
- name: Write the app site snippet for Caddy
  ansible.builtin.template:
    src: miapp.caddy.j2
    dest: "{{ caddy_sites_path }}/miapp.caddy"
    mode: "0640"
  register: miapp_caddy_site

- name: Restart Caddy to apply the site snippet changes
  ansible.builtin.command:
    cmd: docker restart {{ caddy_container_name }}
  when:
    - miapp_caddy_site.changed
    - not (caddy_legacy_migration_pending | default(false) | bool)
```

## Tests

```bash
cd jilgue/ansible/roles/caddy
poetry run molecule test --scenario-name caddy-migration
```

Recrea el layout anterior a #38 y ejecuta los roles `docker_host` + `caddy`,
más una app simulada que escribe su snippet. Comprueba:

- que el Caddy antiguo sigue sirviendo hasta que corre el handler;
- que el contenedor nuevo pertenece al proyecto `caddy` y está `healthy`;
- que se reutiliza el volumen `caddy_data`;
- que HTTP responde con un 308 a HTTPS (el placeholder `:80` no lo tapa);
- que la segunda ejecución sale sin cambios.
