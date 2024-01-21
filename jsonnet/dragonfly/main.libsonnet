{
  params:: {
    namespace: error 'namespace is required',
  },
  dragonfly: {
    apiVersion: 'dragonflydb.io/v1alpha1',
    kind: 'Dragonfly',
    metadata: {
      labels: {
        'app.kubernetes.io/name': 'dragonfly',
        'app.kubernetes.io/instance': 'dragonfly-sample',
        'app.kubernetes.io/part-of': 'dragonfly-operator',
        'app.kubernetes.io/managed-by': 'kustomize',
        'app.kubernetes.io/created-by': 'dragonfly-operator',
      },
      name: 'dragonfly-sample',
      namespace: $.params.namespace,
    },
    spec: {
      replicas: 1,
      resources: {
        requests: {
          cpu: '500m',
          memory: '500Mi',
        },
        limits: {
          cpu: '600m',
          memory: '750Mi',
        },
      },
    },
  },
}
