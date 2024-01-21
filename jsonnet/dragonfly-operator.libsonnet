(import './base.libsonnet') + {
  params+:: {
    name: 'dragonfly-operator',
    destination_namespace: 'dragonfly-operator-system',
    repo_url: 'https://github.com/dragonflydb/dragonfly-operator',
    target_revision: 'v1.0.0',
    path: 'manifests',
    extra_source: {
      directory: {
        include: 'dragonfly-operator.yaml',
      },
    },
  },
} + { spec+: { syncPolicy: { syncOptions: ['CreateNamespace=true', 'ServerSideApply=true'] } } }
