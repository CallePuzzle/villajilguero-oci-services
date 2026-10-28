# AGENTS.md - jilguedev

Entorno de desarrollo: **cluster k0s de un nodo** en OCI Ubuntu, gestionado con Terraform (infra) + ArgoCD (GitOps).

> **Migración completada en la rama `30-migrar-jilguedev`** (issue #30): el stack Nextcloud AIO + Docker rootless + Caddy + Ansible fue eliminado (`ansible/` ya no existe en este entorno; solo en el historial git). Pendiente al merge: devolver `target_revision` del AppProject a `main` y quitar el caveat de rama del `AGENTS.md` raíz. Para el stack AIO (producción) ver `jilgue/AGENTS.md`.

## Arquitectura

- **OCI Instance**: Ubuntu 24.04 (shape VM.Standard.A1.Flex) via `terraform-module-k0s-oci` con `enable_k0s = true`. k0sctl instala el cluster (controller+worker sin taints, k0s 1.36.x) usando `k0sctl.yaml` (generado, gitignored) y deja `kubeconfig` (gitignored).
- **Ingress/TLS**: Traefik (Helm extension de k0s), ingressClass `nginx`. El LB de OCI va en **passthrough TCP** (`https_backend_port = 443`): el TLS lo termina Cloudflare (proxy, modo "Full" sin strict) y Traefik usa certificado self-signed. **Sin cert-manager**.
- **Origen solo vía Cloudflare** (issue #32): el NSG del LB (80/443) solo admite los rangos IPv4 de Cloudflare (`lb_allowed_cidrs` del módulo, ≥ v1.5.0). La lista se lee en cada plan de `https://api.cloudflare.com/client/v4/ips` (data source `http`, con postcondition si falla), así que las rotaciones de Cloudflare se aplican con el siguiente `terraform apply`. Sin esto, quien conociera la IP del LB podía ir directo a Traefik y falsear `cf-connecting-ip`, la IP que usa el rate limit de las apps. Sin IPv6: el LB solo tiene IP pública IPv4. El LB es passthrough, así que sus health checks (LB → backend) no se ven afectados. La instancia solo abre 80/443 a la subnet, de modo que el NSG del LB es el único camino público.
- **Storage**: `enable_openebs = true` → storage class `openebs-hostpath`, requerida por CloudNativePG.
- **ArgoCD**: `https://argocd.callepuzzle.com` con SSO GitHub vía Dex (org `CallePuzzle`, admin local deshabilitado). Plugin CMP **tanka-sops** (sidecar en el repoServer con `SOPS_AGE_KEY`). Los values se generan desde `argocd-values.yaml.tmpl` + `secrets.enc.yaml`.
- **AppProject `app-of-apps-pro`**: apunta a `jilguedev/app-of-apps` en este repo (auto-sync; mientras dure la rama, `target_revision = "30-migrar-jilguedev"` en `main.tf` — devolver a `main` en el merge), con plugin CMP `tanka-sops` y `ENVIRONMENT=pro`. Repos permitidos: `y-tu-que-compras` y el chart de CloudNativePG; namespaces de destino `callepuzzle-pro` + `cnpg-system` (con whitelists cluster-scope para CRDs, RBAC y webhooks de CNPG).
- **GitOps (`app-of-apps/`)**: proyecto Tanka único con entorno `pro/` (`main.jsonnet` + `spec.json` + `secrets.enc`). `lib/main.libsonnet(secrets, projects)` genera la infraestructura compartida (el `Namespace` `callepuzzle-pro`, el Secret `token-registry` para pull de ghcr.io y la `Application` `cnpg-pro` con el chart `cloudnative-pg` 0.29.0 en ns `cnpg-system`, antes que las apps) y un par `Repository` + `Application` por cada entrada de la lista `projects`, mediante la plantilla `lib/project.libsonnet`. **Añadir un proyecto = una entrada en `pro/main.jsonnet`** (`name`, `repoUrl`, `deployKey`, `environment`; defaults `targetRevision: main`, `autoSync: true`, `prune: false`) y, si el repo es privado, su deploy key en `pro/secrets.enc`. path `deploy`, plugin `tanka-sops`; autoSync **sin** prune y **sin** finalizer: el CI de la app es dueño de los manifiestos y borrar la Application no borra lo desplegado.
- **Pin de la lib**: `jsonnet-lib-manifests` va fijado a `2da3fe2` (el mismo de Zytera): genera `path` + `plugin tanka-sops` + `ENVIRONMENT` desde `values.environment`; versiones posteriores hacen `path` y `plugin` excluyentes. Tras cambiar dependencias: `cd jilguedev/app-of-apps && jb install`.

## Despliegue

```bash
cd jilguedev
export SOPS_AGE_KEY_FILE=$HOME/projects/age-key.txt   # requerido por el provider carlpett/sops
terraform apply
```

- State remoto en Terraform Cloud (org `villajilguero`, workspace `jilguedev`) — requiere `terraform login`.
- El módulo Terraform vive fuera del repo: `source = "../../terraform-module-k0s-oci/"` → checkout hermano (`~/projects/terraform-module-k0s-oci`).
- Secrets SOPS/age: `credentials.enc.json` (API OCI) y `secrets.enc.yaml` (`github_client_id/secret`, `sops_age_key`, `infra_repo_deploy_key`).
- Provider OCI en **~> 9.0** (lock a 9.11.0): el módulo v1.4.1 exige >= 9.0 y la 8.12.0 rechazaba `versioning = "Suspended"` en el create del bucket.
- Outputs: `public_ip`, `private_ip` y `lb_public_ip` (destino de los registros DNS en Cloudflare, proxied).

### Render local del app-of-apps

```bash
cd jilguedev/app-of-apps
jb install                                              # solo la primera vez (vendor/, gitignored)
export SOPS_AGE_KEY_FILE=$HOME/projects/age-key.txt
sops -d --output-type json pro/secrets.enc > pro/secrets.json   # gitignored
tk show pro --dangerous-allow-redirect
rm pro/secrets.json
```

## Backups (ytqc-db → OCI Object Storage, barman)

- Bucket `jilguedev-db-backups`, **versioning Disabled**: la API de OCI no soporta reglas lifecycle sobre versiones no actuales (acumularían delete markers sin purga); la retención de barman es el único mecanismo de borrado.
- Terraform crea el bucket porque **barman 3.16+ ya no crea buckets automáticamente**.
- Usuario IAM dedicado `jilguedev-db-backup` (nunca la Customer Secret Key del usuario admin). Policy con scope `in tenancy` (el compartment es la tenancy) filtrando por bucket.
- La Customer Secret Key **solo es legible en la creación** (queda en el tfstate de TFC). Outputs `db_backup_access_key_id` / `db_backup_secret_access_key` (sensitive) → credenciales S3 para los secrets de Tanka (`jilguedev/app-of-apps/pro/secrets.enc`).

### Secrets de Tanka (`app-of-apps/pro/secrets.enc`)

SOPS/age (mismo recipient que `secrets.enc.yaml`), **formato JSON obligatorio** (el CMP descifra con `--input-type json`; guardarlo como YAML rompe el render del app-of-apps, pasó en `ff5d998`). El CMP lo desencripta a `pro/secrets.json` (gitignored) en cada `generate`. Claves:

| Clave | Consumidor | Estado |
|---|---|---|
| `registry_password` | Secret `token-registry` (pull de ghcr.io) | PAT `read:packages` de ghcr.io |
| `y_tu_que_compras_deploy_key` | `Repository` de Argo CD (clone SSH de la app) | deploy key read-only `argocd-jilguedev-ytqc` (copia privada en `~/projects/ytqc-argocd-ed25519`) |
| `DB_APP_PASSWORD` | rol app de `ytqc-db` (fase 3, en el `deploy/` de la app) | generado aleatorio |
| `BACKUP_ACCESS_KEY_ID` / `BACKUP_ACCESS_SECRET_KEY` | backups barman de `ytqc-db` (fase 3) | outputs de Terraform |
| `BETTER_AUTH_SECRET` | Secret de la app (fase 3) | generado aleatorio |
| `SMTP_HOST`, `SMPT_AUTH_USER`, `SMPT_AUTH_PASS`, `SMPT_SENDER` | envío OTP por email | **No viven aquí**: están en el `deploy/pro/secrets.enc` del repo `y-tu-que-compras` (todas rellenas; typo `SMPT_` intencional en tres, así las lee `sender.ts`) |

## Advertencias

- `terraform apply` falla sin `SOPS_AGE_KEY_FILE` apuntando a la age key privada.
- La IP del nodo y el kubeconfig cambian con recreaciones de la instancia; no versionar `k0sctl.yaml`/`kubeconfig` (gitignored).
- `app-of-apps/pro/secrets.enc` está completo; si se rellena o edita con `sops`, conservar el **formato JSON** (`sops` lo reescribe en el formato de entrada; verificar con `head -c 5` → `{`).
