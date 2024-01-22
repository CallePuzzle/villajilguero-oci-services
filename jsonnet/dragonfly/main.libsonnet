{
  params:: {
    namespace: error 'namespace is required',
    name: 'redis-dragonfly',
    replicas: 1,
    limits: {
      cpu: '600m',
      memory: '600Mi',
    },
  },
  dragonfly: {
    apiVersion: 'dragonflydb.io/v1alpha1',
    kind: 'Dragonfly',
    metadata: {
      labels: {
        'app.kubernetes.io/name': 'dragonfly',
        'app.kubernetes.io/instance': $.params.name,
        'app.kubernetes.io/part-of': 'dragonfly-operator',
        'app.kubernetes.io/created-by': 'dragonfly-operator',
      },
      name: $.params.name,
      namespace: $.params.namespace,
    },
    spec: {
      replicas: $.params.replicas,
      resources: {
        requests: {
          cpu: '500m',
          memory: '500Mi',
        },
        limits: $.params.limits,
      },
    },
  },
}
