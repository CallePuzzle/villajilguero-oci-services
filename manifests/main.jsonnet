local enc_secrets = import 'secrets.json';

local namespace = 'default';

local this = (import '../jsonnet/main.libsonnet') + {
  params+: {
    namespace: namespace,
    mariadb+: {
      storage_class_name: 'openebs-hostpath',
      storage: '10Gi',
      backup_storage: '2Gi',
    },
    database+: {
      user_name: enc_secrets.nextcloud_mariadb.user,
      database_name: enc_secrets.nextcloud_mariadb.database,
    },
    nextcloud+: {
      version: '28.0.4',
      host: 'casa.callepuzzle.com',
      storage_class_name: 'openebs-hostpath',
      redis_host: 'redis-dragonfly',
      enable_notify_push: true,
      storage: '5Gi',
    },
  },
};

local mariadb_operator = {
  mariadb_operator: import '../jsonnet/mariadb-operator.libsonnet',
};

local dragonfly_operator = {
  dragonfly_operator: import '../jsonnet/dragonfly-operator.libsonnet',
};

local grafan_alloy = {
  grafana_alloy: (import '../jsonnet/grafana-alloy.libsonnet') + {
    grafana_alloy+: {
      values: |||
        alloy:
          envFrom:
            - secretRef:
              name: grafana-alloy
          configMap:
            content: |-
                logging {
                  level  = "info"
                  format = "logfmt"
                }
                discovery.kubernetes "pods" {
                  role = "pod"
                }
                discovery.kubernetes "nodes" {
                  role = "node"
                }
                discovery.kubernetes "services" {
                  role = "service"
                }
                discovery.kubernetes "endpoints" {
                  role = "endpoints"
                }
                discovery.kubernetes "endpointslices" {
                  role = "endpointslice"
                }
                discovery.kubernetes "ingresses" {
                  role = "ingress"
                }

                prometheus.remote_write "grafana_cloud_prometheus" {
                  endpoint {
                      url = "https://prometheus-prod-24-prod-eu-west-2.grafana.net/api/prom/push"
                      basic_auth {
                          username = 1539321
                          password = env("GRAFANA_CLOUD_API_KEY")
                      }
                  }
                }

                loki.write "grafana_cloud_loki" {
                  endpoint {
                    url = "https://logs-prod-012.grafana.net/loki/api/v1/push"
                    basic_auth {
                      username = 870117
                      password = env("GRAFANA_CLOUD_API_KEY")
                    }
                  }
                }
      |||,
    },
  },
};

local k = import '../jsonnet/vendor/1.28/main.libsonnet';

local secret = k.core.v1.secret;

local secrets = {
  mariadb_secret: secret.new('nextcloud-mariadb', {
    MYSQL_USER: std.base64(enc_secrets.nextcloud_mariadb.user),
    MYSQL_PASSWORD: std.base64(enc_secrets.nextcloud_mariadb.password),
    MYSQL_DATABASE: std.base64(enc_secrets.nextcloud_mariadb.database),
    MYSQL_HOST: std.base64(enc_secrets.nextcloud_mariadb.host),
  }) + secret.metadata.withNamespace(namespace),
  admin_secret: secret.new('nextcloud-admin', {
    NEXTCLOUD_ADMIN_USER: std.base64(enc_secrets.nextcloud_admin.user),
    NEXTCLOUD_ADMIN_PASSWORD: std.base64(enc_secrets.nextcloud_admin.password),
  }) + secret.metadata.withNamespace(namespace),
  s3_secret: secret.new('nextcloud-s3', {
    OBJECTSTORE_S3_HOST: std.base64(enc_secrets.nextcloud_s3.host),
    OBJECTSTORE_S3_BUCKET: std.base64(enc_secrets.nextcloud_s3.bucket),
    OBJECTSTORE_S3_KEY: std.base64(enc_secrets.nextcloud_s3.key),
    OBJECTSTORE_S3_SECRET: std.base64(enc_secrets.nextcloud_s3.secret),
    OBJECTSTORE_S3_USEPATH_STYLE: std.base64('true'),
    OBJECTSTORE_S3_SSL: std.base64('true'),
  }) + secret.metadata.withNamespace(namespace),
  grafan_alloy_secret: secret.new('grafana-alloy', {
    GRAFANA_CLOUD_API_KEY: std.base64(enc_secrets.grafana_cloud.api_key),
  }) + secret.metadata.withNamespace('alloy'),
};

std.objectValues(mariadb_operator) + std.objectValues(dragonfly_operator) + std.objectValues(grafan_alloy) + std.objectValues(this) + std.objectValues(secrets)
