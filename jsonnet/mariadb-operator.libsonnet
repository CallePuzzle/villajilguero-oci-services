(import './base.libsonnet') + {
  params+:: {
    name: 'mariadb-operator',
    destination_namespace: 'mariadb-operator',
    repo_url: 'https://mariadb-operator.github.io/mariadb-operator',
    target_revision: '0.24.0',
    chart: 'mariadb-operator',
  },
} + { spec+: { syncPolicy: { syncOptions: ['CreateNamespace=true', 'ServerSideApply=true'] } } }
