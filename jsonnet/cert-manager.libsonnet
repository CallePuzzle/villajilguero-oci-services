(import './base.libsonnet') + {
  cert_manager:: {
    values: '',
  },
  params+:: {
    name: 'cert-manager',
    destination_namespace: 'cert-manager',
    repo_url: 'https://charts.jetstack.io',
    target_revision: 'v1.16.3',
    chart: 'cert-manager',
    values: $.cert_manager.values,
  },
}
