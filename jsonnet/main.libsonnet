{
  params:: {
    namespace: 'default',
    database:: {
      user_name: 'nextcloud',
      user_secret_name: 'nextcloud-mariadb',
      user_secret_key: 'MYSQL_PASSWORD',
    },
    mariadb:: {},
    nextcloud:: {
      name: 'nextcloud',
      namespace: 'default',
      port: 8080,
      redis_host: 'redis-dragonfly',
    },
    dragonfly:: {},
  },
  user: ((import 'mariadb/database.libsonnet') + {
           params+: $.params.database {
             namespace: $.params.namespace,
           },
         }).user,
  database: ((import 'mariadb/database.libsonnet') + {
               params+: $.params.database {
                 namespace: $.params.namespace,
               },
             }).database,
  grant: ((import 'mariadb/database.libsonnet') + {
            params+: $.params.database {
              namespace: $.params.namespace,
            },
          }).grant,
  mariadb: ((import 'mariadb/instance.libsonnet') + {
              params+: $.params.mariadb {
                namespace: $.params.namespace,
              },
            }).mariadb,
  backup: ((import 'mariadb/backup.libsonnet') + {
             params+: $.params.mariadb {
               namespace: $.params.namespace,
             },
           }).backup,
  db_config_map: ((import 'mariadb/instance.libsonnet') + {
                    params+: $.params.mariadb {
                      namespace: $.params.namespace,
                    },
                  }).config_map,
  secret: ((import 'mariadb/instance.libsonnet') + {
             params+: $.params.mariadb {
               namespace: $.params.namespace,
             },
           }).secret,

  deployment: ((import 'nextcloud/deployment.libsonnet') + {
                 params+: $.params.nextcloud {
                   namespace: $.params.namespace,
                 },
               }).deployment,
  service: ((import 'nextcloud/service.libsonnet') + {
              params+: $.params.nextcloud {
                namespace: $.params.namespace,
              },
            }).service,
  ingress: ((import 'nextcloud/ingress.libsonnet') + {
              params+: $.params.nextcloud {
                namespace: $.params.namespace,
              },
            }).ingress,
  pvc_html: ((import 'nextcloud/pvc.libsonnet') + {
               params+: $.params.nextcloud {
                 namespace: $.params.namespace,
               },
             }).html,
  nginx_config: ((import 'nextcloud/configmap.libsonnet') + {
                   params+: $.params.nextcloud {
                     namespace: $.params.namespace,
                   },
                 }).nginx_config,
  dragonfly: ((import 'dragonfly/main.libsonnet') + {
                params+: $.params.dragonfly {
                  namespace: $.params.namespace,
                  name: $.params.nextcloud.redis_host,
                },
              }).dragonfly,

}
