(import './base.libsonnet') + {
  params+:: {
    name: 'metrics-server',
    destination_namespace: 'kube-system',
    repo_url: 'https://kubernetes-sigs.github.io/metrics-server',
    target_revision: '3.12.1',
    chart: 'metrics-server',
    values: |||
      resources:
        requests:
          cpu: 50m
          memory: 64Mi
    |||,
  },
}
