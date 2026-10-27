local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local tk = import 'tk';
local _project = (import 'project.libsonnet');

// Contenido del app-of-apps del entorno pro. La Application raíz
// `app-of-apps-pro` (chart argocd-apps, creada por Terraform) apunta a este
// proyecto Tanka con `plugin.env ENVIRONMENT=pro`; el CMP tanka-sops
// desencripta pro/secrets.enc a pro/secrets.json, que este fichero recibe
// como parámetro.
//
// La infraestructura compartida (namespace, token de registry y operador
// CNPG) vive aquí; cada proyecto del entorno es una entrada en la lista
// `projects` que recibe esta función (ver pro/main.jsonnet y la plantilla
// en project.libsonnet).
//
// Pin de jsonnet-lib-manifests en 2da3fe2: es la versión en la que la lib
// genera `path` + `plugin.tanka-sops` con `ENVIRONMENT` a partir de
// values.environment (patrón Zytera); versiones posteriores hacen path y
// plugin excluyentes.
function(secrets, projects)
  local common_values = {
    destinationNamespace: 'callepuzzle-' + tk.env.metadata.name,
    namespace: tk.env.spec.namespace,
    environment: tk.env.metadata.name,
    path: 'deploy',
    projectName: 'app-of-apps-' + tk.env.metadata.name,
    registryUsername: 'callepuzzle',
    registryPassword: secrets.registry_password,
  };
  // Subconjunto de common_values que necesita la plantilla de proyecto.
  local common = {
    env: common_values.environment,
    namespace: common_values.namespace,
    projectName: common_values.projectName,
    destinationNamespace: common_values.destinationNamespace,
    path: common_values.path,
  };
  {
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
    // Antes que las apps: los CRDs del operador deben existir cuando Argo CD
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
  } +
  // Un par Repository + Application por proyecto, en el orden de la lista.
  std.foldl(function(acc, project) acc + _project(project, common), projects, {})
