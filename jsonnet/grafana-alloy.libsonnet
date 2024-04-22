(import './base.libsonnet') + {
  grafana_alloy:: {
    values: '',
  },
  params+:: {
    name: 'alloy',
    destination_namespace: 'alloy',
    repo_url: 'https://grafana.github.io/helm-charts',
    target_revision: '0.1.1',
    chart: 'alloy',
    values: $.grafana_alloy.values,
  },
} + { spec+: { syncPolicy: { syncOptions: ['CreateNamespace=true'] } } }
