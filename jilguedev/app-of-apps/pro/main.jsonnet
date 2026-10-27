local secrets = import 'secrets.json';
local app_of_apps = (import '../lib/main.libsonnet');

// Proyectos dados de alta en este entorno. Añadir uno nuevo es una entrada
// aquí (y su deploy key en secrets.enc si el repo es privado); la plantilla
// que los materializa está en lib/project.libsonnet.
app_of_apps(secrets, [
  {
    name: 'y-tu-que-compras',
    repoUrl: 'git@github.com:CallePuzzle/y-tu-que-compras.git',
    deployKey: secrets.y_tu_que_compras_deploy_key,
    // La app vive en deploy/pro de su repo: es su entorno de producción
    // (el «dev» del clúster es del entorno de infra, no de la app). El
    // CMP tanka-sops ejecuta `tk show pro` dentro de deploy/.
    environment: 'pro',
  },
])
