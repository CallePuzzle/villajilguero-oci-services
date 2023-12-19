{
  params:: {
    name: 'nextcloud',
    namespace: 'default',
    port: 8080,
  },
  deployment: (import 'deployment.libsonnet') + {
    params+: $.params,
  },
  service: (import 'service.libsonnet') + {
    params+: $.params,
  },
}
