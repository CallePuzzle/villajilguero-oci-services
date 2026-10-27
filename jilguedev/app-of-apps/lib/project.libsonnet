local _argocd_app = (import 'github.com/CallePuzzle/jsonnet-lib-manifests/argocd-app.libsonnet');
local _argocd_repository = (import 'github.com/CallePuzzle/jsonnet-lib-manifests/argocd-repository.libsonnet');

// Plantilla de proyecto: el par Repository + Application que da de alta una
// app en el app-of-apps. Dar de alta un proyecto nuevo es una entrada en el
// main del entorno (pro/main.jsonnet); este fichero no necesita cambios.
//
// project:
//   name: nombre corto de la app; de él derivan las claves del objeto de
//         salida y los nombres de los recursos («<name>-<env>»).
//   repoUrl: URL git del repo de la app.
//   deployKey: deploy key SSH (read-only) para que Argo CD lo clone; null
//         para repos públicos.
//   environment: entorno dentro del repo de la app que renderiza el CMP
//         tanka-sops (`tk show <environment>` dentro de su deploy/).
//   targetRevision: rama o tag a trackear (opcional, main).
//   autoSync: sync automático (opcional, true).
//   prune: prune del autoSync (opcional, false): el CI de la app es dueño de
//         los manifiestos (commits de version.jsonnet), así que el prune
//         corresponde al repo de la app, no a este.
//
// common: valores compartidos del entorno
//   { env, namespace, projectName, destinationNamespace, path }.
//
// Pin de jsonnet-lib-manifests en 2da3fe2: la lib compone el nombre como
// name + '-' + projectName y activa prune con autoSync; de ahí los overrides
// de metadata.name y syncPolicy.automated.prune. La lib nunca añade
// resources-finalizer.argoproj.io: borrar la Application no borra los
// recursos desplegados en el clúster.
function(project, common)
  local p = {
    // Defaults; la entrada del proyecto los sobreescribe.
    targetRevision: 'main',
    autoSync: true,
    prune: false,
  } + project;
  // Las claves del objeto de salida sustituyen guiones por guiones bajos
  // («y-tu-que-compras» → «y_tu_que_compras»).
  local key = std.strReplace(p.name, '-', '_');
  {
    [key + '_repository']: _argocd_repository {
      values+:: {
        name: p.name + '-' + common.env,
        namespace: common.namespace,
        projectName: common.projectName,
        repositoryUrl: p.repoUrl,
        sshPrivateKey: p.deployKey,
      },
    },
    [key]: _argocd_app {
      values+:: {
        name: p.name,
        repoURL: p.repoUrl,
        targetRevision: p.targetRevision,
        autoSync: p.autoSync,
        destinationNamespace: common.destinationNamespace,
        namespace: common.namespace,
        path: common.path,
        projectName: common.projectName,
        environment: p.environment,
      },
      // Conservamos el nombre corto «<name>-<env>» (la lib compondría
      // «<name>-<projectName>»), igual que hace Zytera con sus apps.
      metadata+: {
        name: p.name + '-' + common.env,
      },
      spec+: {
        syncPolicy+: (
          // autoSync con la lib 2da3fe2 activa prune: sin este override el
          // prune borraría lo que gestiona el CI de la app.
          if p.autoSync then {
            automated+: { prune: p.prune },
          } else {}
        ),
      },
    },
  }
