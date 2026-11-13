# Migración a roles separados (#36: `docker_host` + `caddy` + `nextcloud_aio` + `wallabag`)

Procedimiento para aplicar en **producción** (`jilgue`, Nextcloud AIO en uso)
el refactor de roles de Ansible (#37 `docker_host`, #38 `caddy`, #39 `wallabag`,
#40 molecule). Se acepta un corte de servicio corto; **no se toca ningún dato de
Nextcloud**.

## Qué cambia en el host

| Elemento | Antes (main) | Después |
|----------|--------------|---------|
| Caddy | servicio `caddy` del proyecto compose `nextcloud-aio` | proyecto compose propio `caddy` en `~/caddy`, unit `docker-compose-caddy.service` |
| Config de Caddy | `~/nextcloud-aio/Caddyfile` | `~/caddy/Caddyfile` (base) + `~/caddy/sites/nextcloud.caddy` (snippet) |
| Volúmenes `caddy_config` / `caddy_data` | del proyecto `nextcloud-aio` | **los mismos volúmenes**, reutilizados por nombre: los certificados de Let's Encrypt no se reemiten |
| Mastercontainer AIO, sus volúmenes, datadir, backups | — | **sin cambios** (el compose renderiza igual para el mastercontainer: no se recrea) |
| Timer de backup Borg y cron de B2 | — | sin cambios (mismo `name` y `job`) |
| `daemon.json` de Docker | — | sin cambios (no se reinicia dockerd) |
| UFW | `ufw reset` en cada ejecución | sin reset: añade las reglas que falten (ver más abajo) |
| fail2ban | se reiniciaba en cada ejecución | solo se reinicia si cambia `jail.local` |
| Wallabag | — | rol presente pero inerte (`wallabag_enabled: false`) |
| Variable `docker_user` | inventario y group_vars | renombrada a `docker_host_user` (el inventario generado por Terraform ya está actualizado) |

### Cómo se hace el traspaso de Caddy

1. El rol `caddy` crea `~/caddy`, su compose, el Caddyfile base y la unit, y detecta
   el contenedor `caddy` antiguo (label `com.docker.compose.project=nextcloud-aio`).
   **No lo toca**: lo deja sirviendo y difiere el traspaso a un handler.
2. El rol `nextcloud_aio` escribe `~/caddy/sites/nextcloud.caddy` y aplica su compose
   sin el servicio `caddy`. No hay efecto en el mastercontainer. Mientras el
   traspaso está pendiente no reinicia Caddy ni borra el `~/nextcloud-aio/Caddyfile`
   antiguo, que el contenedor antiguo sigue montando.
3. **Al final del play**, y solo si ninguna tarea ha fallado, el handler:
   - comprueba que hay al menos un snippet `*.caddy`; si no, aborta sin tocar nada;
   - para el contenedor antiguo y lo renombra a `caddy-legacy-pre38`. **Aquí empieza el corte**;
   - arranca `docker-compose-caddy` y espera a que el contenedor nuevo esté `healthy`
     (máximo ~90 s; lo normal son ~30 s por el `start_period` del healthcheck, aunque
     el servicio responde antes);
   - si queda `healthy`, borra `caddy-legacy-pre38` (sin `-v`: los volúmenes se quedan);
   - **si no queda `healthy`, hace rollback automático**: `docker compose down` del
     proyecto nuevo (sin `-v`), devuelve el nombre `caddy` al contenedor antiguo y lo
     vuelve a arrancar. Después el play falla con un mensaje explícito.

El corte va desde el `docker stop` hasta que el Caddy nuevo escucha en 443: segundos.

Este flujo lo reproduce el escenario de Molecule `caddy-migration`
(`ansible/roles/caddy/molecule/caddy-migration`). El escenario comprueba además que
el volumen `caddy_data` se reutiliza y que HTTP redirige a HTTPS (308) a pesar del
placeholder `:80`.

## Antes de desplegar

En el servidor (`ssh ubuntu@<ip>`):

```bash
export DOCKER_HOST=unix:///run/user/$(id -u)/docker.sock

# 1. Último backup Borg correcto (timer de las 02:00) y último sync a B2 (05:00)
systemctl --user status nextcloud-aio-backup.service --no-pager
journalctl --user -u nextcloud-aio-backup.service -n 50 --no-pager
tail -n 20 ~/nextcloud-aio-b2-sync.log

# 2. Estado de partida (para comparar después)
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Label "com.docker.compose.project"}}'

# 3. (Opcional) Copia de caddy_data: certificados y CA interna. No es
#    imprescindible (Let's Encrypt los reemitiría), pero evita depender de ello.
docker run --rm -v caddy_data:/data:ro -v "$HOME":/backup alpine \
  tar czf /backup/caddy_data-pre38.tgz -C /data .
```

Si el backup del día ha fallado, lanza uno manual desde la UI de AIO (túnel SSH al
8080) antes de seguir.

Elige un momento con poco uso: los backups son a las 02:00 y 05:00, así que evita
coincidir con ellos.

## Despliegue

Desde el repo, con la rama ya mergeada en `main`:

```bash
cd jilgue/ansible
poetry install

# Simulación: muestra los diffs de plantillas. Las tareas `command` no se
# ejecutan; el traspaso aparece como un mensaje del handler en vez de hacerse.
poetry run ansible-playbook playbook.yml --check --diff

# Despliegue real
poetry run ansible-playbook playbook.yml
```

No hace falta `terraform apply`: el único cambio de Terraform es el contenido del
inventario generado (`docker_user` → `docker_host_user`), que ya está commiteado. Un
`apply` posterior no debería mostrar cambios en `local_file`.

Ejecuta el playbook **una segunda vez**. Esa ejecución borra el
`~/nextcloud-aio/Caddyfile` obsoleto, que se conserva durante el traspaso por si
hace falta el rollback. Una **tercera** ejecución debe salir con `changed=0`.

## Comprobaciones después

```bash
# Desde cualquier sitio
curl -sI https://aio.callepuzzle.com | head -n 1        # 200/302
curl -sI http://aio.callepuzzle.com | head -n 3         # 308 + Location: https://...
echo | openssl s_client -connect aio.callepuzzle.com:443 -servername aio.callepuzzle.com 2>/dev/null \
  | openssl x509 -noout -issuer -dates                  # mismo emisor/fechas que antes (no reemitido)

# En el servidor
export DOCKER_HOST=unix:///run/user/$(id -u)/docker.sock
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Label "com.docker.compose.project"}}'
#   caddy -> proyecto "caddy", healthy; nextcloud-aio-* sin reinicios inesperados
docker ps -a --filter name=caddy-legacy-pre38           # vacío
systemctl --user is-enabled docker-compose-caddy docker-compose-nextcloud
systemctl --user list-timers nextcloud-aio-backup.timer --no-pager
crontab -l | grep b2                                     # cron de B2 sin cambios
sudo ufw status verbose                                  # 22/80/443 allow, 8080 deny, active
```

Comprueba también el login en Nextcloud y la sincronización de algún cliente.

## Rollback

### A. Automático (durante el traspaso)

Si el Caddy nuevo no queda `healthy`, el propio handler restaura el contenedor
antiguo y el play falla. Se queda así:

- el Caddy antiguo sirve como antes;
- `~/caddy` y la unit `docker-compose-caddy` existen, pero la unit está deshabilitada
  y parada. Un reinicio del servidor solo levanta el Caddy antiguo;
- el compose de `nextcloud-aio` ya no tiene el servicio `caddy`. No afecta mientras
  el contenedor antiguo exista; `docker compose up` en ese proyecto solo avisa de un
  contenedor huérfano;
- `~/nextcloud-aio/Caddyfile` se conserva, porque lo monta el contenedor antiguo.

Para investigar: el handler muestra en la salida del play las últimas 100 líneas de
log del contenedor nuevo, que se capturan antes de borrarlo. También sirve
`cd ~/caddy && docker compose config`. Arreglado el problema, vuelve a ejecutar el
playbook: el traspaso se reintenta.

Si se prefiere volver por completo al layout anterior, sigue el apartado B.

### B. Manual: volver al layout de `main` anterior

Sirve cuando el traspaso terminó pero algo va mal, o cuando se decide abandonar la
migración. **Nunca uses `-v`, `docker volume rm` ni `docker volume prune`.**

En el servidor:

```bash
export DOCKER_HOST=unix:///run/user/$(id -u)/docker.sock

# Retirar el proxy nuevo (los volúmenes caddy_config/caddy_data se quedan)
systemctl --user disable --now docker-compose-caddy
cd ~/caddy && docker compose down
docker rm -f caddy-legacy-pre38 2>/dev/null || true   # restos, si los hubiera
rm ~/.config/systemd/user/docker-compose-caddy.service
systemctl --user daemon-reload
```

En local, desde el commit de `main` anterior al merge:

```bash
git checkout <commit-de-main-previo>   # p. ej. e03759d
cd jilgue/ansible && poetry run ansible-playbook playbook.yml
```

Ese playbook vuelve a escribir `~/nextcloud-aio/Caddyfile` y el compose con el
servicio `caddy`, y lo levanta con `docker compose up -d`. El servicio se recrea con
los mismos volúmenes nombrados. Compose avisará de que los volúmenes los creó otro
proyecto: es solo un aviso.

Hay un corte desde el `down` hasta que el playbook termina. Si urge acortarlo, ejecuta
el playbook justo después del `down`.

Después:

- comprueba lo mismo que en "Comprobaciones después";
- borra `~/caddy` (solo contiene configuración);
- haz `git checkout -` para volver a tu rama.

### C. Certificados

Si tras cualquiera de los pasos Caddy no encuentra los certificados (no debería: los
volúmenes no se borran nunca), restaura la copia del paso 3 de "Antes de desplegar":

```bash
docker stop caddy
docker run --rm -v caddy_data:/data -v "$HOME":/backup alpine \
  sh -c 'cd /data && tar xzf /backup/caddy_data-pre38.tgz'
docker start caddy
```

## Notas

- **UFW**: ya no se resetea en cada ejecución. Las reglas que gestiona el rol (22, 80
  y 443 allow, 8080 deny, policy deny) se añaden si faltan. Las reglas que se añadan a
  mano, o las que se retiren algún día del rol, **no se borran solas**: hay que quitarlas
  con `sudo ufw delete ...`.
- **Wallabag** queda inerte. Para desplegarlo, pon `wallabag_enabled: true` en
  `group_vars/docker_servers.yml` y ejecuta el playbook (ver `AGENTS.md`). Al estar ya
  migrado Caddy, el rol solo añade su snippet y reinicia el proxy.
