local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local tk = import 'tk';
local _argocd_app = (import 'github.com/CallePuzzle/jsonnet-lib-manifests/argocd-app.libsonnet');
local _argocd_repository = (import 'github.com/CallePuzzle/jsonnet-lib-manifests/argocd-repository.libsonnet');

// Contenido del app-of-apps del entorno dev. La Application raíz
// `app-of-apps-dev` (chart argocd-apps, creada por Terraform) apunta a este
// proyecto Tanka con `plugin.env ENVIRONMENT=dev`; el CMP tanka-sops
// desencripta dev/secrets.enc a dev/secrets.json, que este fichero recibe
// como parámetro.
//
// Pin de jsonnet-lib-manifests en 2da3fe2: es la versión en la que la lib
// genera `path` + `plugin.tanka-sops` con `ENVIRONMENT` a partir de
// values.environment (patrón Zytera); versiones posteriores hacen path y
// plugin excluyentes.
function(secrets)
  {
    local common_values = {
      destinationNamespace: 'callepuzzle-' + tk.env.metadata.name,
      namespace: tk.env.spec.namespace,
      environment: tk.env.metadata.name,
      path: 'deploy',
      projectName: 'app-of-apps-' + tk.env.metadata.name,
      registryUsername: 'callepuzzle',
      registryPassword: secrets.registry_password,
    },
    namespace: k.core.v1.namespace.new(common_values.destinationNamespace),
    tokenRegistry: k.core.v1.secret.new('token-registry', {
                     '.dockerconfigjson': std.base64(std.toString({
                       auths: { 'ghcr.io': {
                         username: common_values.registryUsername,
                         password: common_values.registryPassword,
                         auth: std.base64(std.toString(common_values.registryUsername + ':' + common_values.registryPassword)),
                       } },
                     })),
                   }, 'kubernetes.io/dockerconfigjson') +
                   k.core.v1.secret.metadata.withNamespace(common_values.destinationNamespace),
    // Antes que la app: los CRDs del operador deben existir cuando Argo CD
    // reconcilie el Cluster ytqc-db de la app. Si el primer sync llega antes,
    // se resuelve en la reconciliación siguiente (patrón conocido en Zytera).
    cnpg: {
      apiVersion: 'argoproj.io/v1alpha1',
      kind: 'Application',
      metadata: { name: 'cnpg-' + tk.env.metadata.name, namespace: common_values.namespace },
      spec: {
        destination: { namespace: 'cnpg-system', server: 'https://kubernetes.default.svc' },
        project: common_values.projectName,
        source: {
          repoURL: 'https://cloudnative-pg.io/charts',
          chart: 'cloudnative-pg',
          targetRevision: '0.29.0',
        },
        syncPolicy: {
          automated: { prune: true },
          syncOptions: ['CreateNamespace=true', 'ServerSideApply=true'],
        },
      },
    },
    y_tu_que_compras_repository: _argocd_repository {
      values+:: {
        name: 'y-tu-que-compras-' + tk.env.metadata.name,
        namespace: common_values.namespace,
        projectName: common_values.projectName,
        repositoryUrl: 'git@github.com:CallePuzzle/y-tu-que-compras.git',
        sshPrivateKey: secrets.y_tu_que_compras_deploy_key,
      },
    },
    y_tu_que_compras: _argocd_app {
      values+:: {
        name: 'y-tu-que-compras',
        repoURL: 'git@github.com:CallePuzzle/y-tu-que-compras.git',
        targetRevision: 'main',
        autoSync: true,
      } + common_values + {
        // La app vive en deploy/pro de su repo: es su entorno de producción
        // (el «dev» del clúster es del entorno de infra, no de la app). El
        // CMP tanka-sops ejecuta `tk show pro` dentro de deploy/.
        environment: 'pro',
      },
      // La lib compone el nombre como name + '-' + projectName; conservamos
      // el nombre corto, igual que hace Zytera con sus apps.
      metadata+: {
        name: 'y-tu-que-compras-' + tk.env.metadata.name,
      },
      // autoSync con la lib 2da3fe2 activa prune: el CI de la app es dueño de
      // los manifiestos (commits de version.jsonnet), así que prune false.
      // La lib nunca añade resources-finalizer.argoproj.io: borrar la
      // Application no borra los recursos desplegados en el clúster.
      spec+: {
        syncPolicy+: {
          automated+: { prune: false },
        },
      },
    },
  }
