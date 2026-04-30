# Plan: Extender módulo terraform-module-k0s-oci para soportar Podman

## Resumen

Modificar el módulo `../../terraform-module-k0s-oci/` para que sea compatible con dos modos de operación:
1. **k0s** (actual): Crea instancia con k0s (Kubernetes)
2. **podman** (nuevo): Crea instancia con Podman para ejecutar containers

## Cambios Propuestos

### 1. Nueva variable `deployment_mode` en `variables.tf`

Agregar variable para seleccionar el modo de despliegue:

```hcl
variable "deployment_mode" {
  description = "Modo de despliegue: 'k0s' para Kubernetes o 'podman' para contenedores"
  type        = string
  default     = "k0s"
  validation {
    condition     = contains(["k0s", "podman"], var.deployment_mode)
    error_message = "El modo de despliegue debe ser 'k0s' o 'podman'."
  }
}
```

### 2. Modificar `instances.tf`

- Actualizar `freeform_tags` para que el tag `part_of` use el modo en lugar de hardcodear "k0s"
- El user_data se mantiene apuntando a `user-data.sh` (se modificará el script)

### 3. Modificar `user-data.sh`

Convertir en template (`user-data.sh.tmpl`) que genere diferentes scripts según el modo:

**Para k0s (actual):**
- Update/upgrade del sistema
- Disable ufw/iptables
- Instalar kubectl via snap
- Configurar bashrc con KUBECONFIG

**Para podman (nuevo):**
- Update/upgrade del sistema
- Disable ufw/iptables
- Instalar podman y podman-compose
- (Opcional) Configurar rootless containers si es necesario

### 4. Modificar `main.tf`

- El `local_file.k0sctl` solo se creará cuando `deployment_mode == "k0s"`
- El contenido de `local.k0s_file_content` solo se computa para modo k0s

### 5. Modificar `outputs.tf`

- `public_ip`: Funciona para ambos modos
- `k0s_file_content`: Solo disponible cuando `deployment_mode == "k0s"`, null en caso contrario
- Agregar `private_ip` como output útil para ambos modos

### 6. Modificar `vcn.tf`

- Las reglas de seguridad k0s-específicas (puertos 2380, 6443, 10250, 9443, 8132, etc.) deben ser condicionales
- Solo aplicar cuando `deployment_mode == "k0s"`
- Para podman, mantener reglas básicas (80, 443) y permitir configuración adicional

### 7. Modificar `load_balancer.tf`

- Hacer el módulo lb condicional: solo crear si se solicita explícitamente
- Agregar variable `enable_load_balancer` (default: true para k0s, false para podman)

### 8. Actualizar `jilguedev/main.tf`

Ejemplo de uso para modo podman:

```hcl
module "oci-podman" {
  source = "../../terraform-module-k0s-oci/"

  compartment_id  = data.sops_file.credentials.data["tenancy_ocid"]
  deployment_mode = "podman"
  ssh_public_key  = ""
  
  # Opcional: variables específicas de podman
  podman_compose_file = filebase64("docker-compose.yaml")
}
```

## Archivos a Modificar

| Archivo | Cambios |
|---------|---------|
| `variables.tf` | Agregar `deployment_mode`, `enable_load_balancer`, variables específicas de podman |
| `instances.tf` | Tags dinámicos según modo |
| `user-data.sh` → `user-data.sh.tmpl` | Template condicional para k0s vs podman |
| `main.tf` | Recursos condicionales según modo |
| `outputs.tf` | Outputs condicionales |
| `vcn.tf` | Reglas de seguridad condicionales |
| `load_balancer.tf` | Módulo lb condicional |

## Compatibilidad Hacia Atrás

- El valor por defecto de `deployment_mode` será `"k0s"`, manteniendo el comportamiento actual
- Las configuraciones existentes continuarán funcionando sin cambios

## Opcional: Variables Adicionales para Podman

Considerar agregar:
- `podman_user_data_extra`: Script adicional personalizado
- `podman_ports`: Lista de puertos a exponer en security groups
