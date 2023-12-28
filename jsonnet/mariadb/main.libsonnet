{
  params:: {
    namespace: 'default',
    database:: {},
    instance:: {},
  },
  database: (import 'database.libsonnet') + {
    params+: $.params.database {
      namespace: $.params.namespace,
    },
  },
  instance: (import 'instance.libsonnet') + {
    params+: $.params.instance {
      namespace: $.params.namespace,
    },
  },
}
