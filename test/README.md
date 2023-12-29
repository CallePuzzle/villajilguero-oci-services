# Integration test

## Borrar bucket

Para poder hacer el destroy primero hay que borrar los datos del bucket:

```bash
source ~/.b2_env
b2 rm --versions --recursive callepuzzle-nextcloud-temp
```
