(import './base.libsonnet') + {
  grafana_monitoring:: {
    values: '',
  },
  params+:: {
    name: 'grafana-monitoring',
    destination_namespace: 'monitoring',
    repo_url: 'https://grafana.github.io/helm-charts',
    target_revision: '1.0.1',
    chart: 'k8s-monitoring',
    values: $.grafana_monitoring.values,
  },
} + { spec+: { syncPolicy: { syncOptions: ['CreateNamespace=true', 'ServerSideApply=true'] } } }
