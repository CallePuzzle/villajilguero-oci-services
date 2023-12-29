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
  ingress: (import 'ingress.libsonnet') + {
    params+: $.params,
  },
  persistentVolumeClaim: (import 'pvc.libsonnet') + {
    params+: $.params,
  },
  configmap: (import 'configmap.libsonnet') + {
    params+: $.params,
  },
}
