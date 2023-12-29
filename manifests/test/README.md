# Manifiestos de pruebas

En esta carpeta tenemos lo necesario para montar un nextcloud completamente local. Usando kind y tanka.

Y además con [main.jsonnet](main.jsonnet) que instalará lo mismo que en la versión de producción usando ArgoCD.

## Despliegue con Tanka

Primero necesitamos descargar las dependencias:

```bash
jb install
tk tool charts vendor
````

[create-cluster.sh](create-cluster.sh) creará un cluster de kind con el nombre `local`. Para desplegar nextcloud:

```bash
tk apply operators
tk apply local
```
