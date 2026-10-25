# AGENTS.md - jilguedev

Entorno de desarrollo: **cluster k0s de un nodo** en OCI Ubuntu, gestionado con Terraform (infra) + ArgoCD (GitOps).

> **En migración** (rama `30-migrar-jilguedev`): el antiguo stack Nextcloud AIO + Docker rootless + Caddy + Ansible está siendo sustituido. Terraform ya no aprovisiona AIO ni genera `ansible/inventory/oci_docker.yml`; el directorio `ansible/` queda huérfano en este entorno. Para el stack AIO (producción) ver `jilgue/AGENTS.md`.

## Arquitectura

- **OCI Instance**: Ubuntu 24.04 (shape VM.Standard.A1.Flex) via `terraform-module-k0s-oci` con `enable_k0s = true`. k0sctl instala el cluster (controller+worker sin taints, k0s 1.36.x) usando `k0sctl.yaml` (generado, gitignored) y deja `kubeconfig` (gitignored).
- **Ingress/TLS**: Traefik (Helm extension de k0s), ingressClass `nginx`. El LB de OCI va en **passthrough TCP** (`https_backend_port = 443`): el TLS lo termina Cloudflare (proxy, modo "Full" sin strict) y Traefik usa certificado self-signed. **Sin cert-manager**.
- **Storage**: `enable_openebs = true` → storage class `openebs-hostpath`, requerida por CloudNativePG.
- **ArgoCD**: `https://argocd.callepuzzle.com` con SSO GitHub vía Dex (org `CallePuzzle`, admin local deshabilitado). Plugin CMP **tanka-sops** (sidecar en el repoServer con `SOPS_AGE_KEY`). Los values se generan desde `argocd-values.yaml.tmpl` + `secrets.enc.yaml`.
- **AppProject `app-of-apps-dev`**: apunta a `jilguedev/app-of-apps` en este repo (`main`, auto-sync) — **ese path aún no existe en el árbol**. Repos permitidos: `y-tu-que-compras` y el chart de CloudNativePG; namespaces de destino `callepuzzle-dev` + `cnpg-system` (con whitelists cluster-scope para CRDs, RBAC y webhooks de CNPG).

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

## Backups (ytqc-db → OCI Object Storage, barman)

- Bucket `jilguedev-db-backups`, **versioning Disabled**: la API de OCI no soporta reglas lifecycle sobre versiones no actuales (acumularían delete markers sin purga); la retención de barman es el único mecanismo de borrado.
- Terraform crea el bucket porque **barman 3.16+ ya no crea buckets automáticamente**.
- Usuario IAM dedicado `jilguedev-db-backup` (nunca la Customer Secret Key del usuario admin). Policy con scope `in tenancy` (el compartment es la tenancy) filtrando por bucket.
- La Customer Secret Key **solo es legible en la creación** (queda en el tfstate de TFC). Outputs `db_backup_access_key_id` / `db_backup_secret_access_key` (sensitive) → credenciales S3 para los secrets de Tanka (`jilguedev/app-of-apps/dev/secrets.enc`).

## Advertencias

- `terraform apply` falla sin `SOPS_AGE_KEY_FILE` apuntando a la age key privada.
- La IP del nodo y el kubeconfig cambian con recreaciones de la instancia; no versionar `k0sctl.yaml`/`kubeconfig` (gitignored).
- El app-of-apps de ArgoCD referencia `jilguedev/app-of-apps`, que todavía hay que crear en el repo (Tanka + `secrets.enc`).
