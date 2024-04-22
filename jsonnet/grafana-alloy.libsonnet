(import './base.libsonnet') + {
  params+:: {
    name: 'alloy',
    destination_namespace: 'alloy',
    repo_url: 'https://grafana.github.io/helm-charts',
    target_revision: '0.1.1',
    chart: 'alloy',
  },
} + { spec+: { syncPolicy: { syncOptions: ['CreateNamespace=true'] } } }
