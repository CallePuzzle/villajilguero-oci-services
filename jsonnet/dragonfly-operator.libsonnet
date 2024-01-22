(import './base.libsonnet') + {
  params+:: {
    name: 'dragonfly-operator',
    destination_namespace: 'dragonfly-operator-system',
    repo_url: 'https://github.com/CallePuzzle/villajilguero-oci-services',
    target_revision: 'main',
    path: 'manifests/dragonfly-operator',
    extra_source: {
      directory: {
        include: 'dragonfly-operator.yaml',
      },
    },
  },
} + { spec+: { syncPolicy: { syncOptions: ['CreateNamespace=true', 'ServerSideApply=true'] } } }
