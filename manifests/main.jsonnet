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
      version: '30.0.5',
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

local grafana_monitoring = {
  grafana_monitoring: (import '../jsonnet/grafana-monitoring.libsonnet') + {
    grafana_monitoring+: {
      values: |||
        cluster:
          name: my-cluster
        externalServices:
          prometheus:
            host: https://prometheus-prod-24-prod-eu-west-2.grafana.net
            basicAuth:
              username: "1539321"
              password: %(grafana_cloud_api_key)s
          loki:
            host: https://logs-prod-012.grafana.net
            basicAuth:
              username: "870117"
              password: %(grafana_cloud_api_key)s
          tempo:
            host: https://tempo-prod-10-prod-eu-west-2.grafana.net:443
            basicAuth:
              username: "864433"
              password: %(grafana_cloud_api_key)s
        metrics:
          enabled: true
          cost:
            enabled: false
          node-exporter:
            enabled: true
        logs:
          enabled: true
          pod_logs:
            enabled: true
          cluster_events:
            enabled: true
        traces:
          enabled: true
        receivers:
          grpc:
            enabled: true
          http:
            enabled: true
          zipkin:
            enabled: true
        opencost:
          enabled: false
        kube-state-metrics:
          enabled: true
        prometheus-node-exporter:
          enabled: true
        prometheus-operator-crds:
          enabled: true
        alloy: {}
        alloy-logs: {}
      ||| % {
        grafana_cloud_api_key: enc_secrets.grafana_cloud.api_key,
      },
    },
  },
};

local metrics_server = {
  metrics_server: import '../jsonnet/metrics-server.libsonnet',
};

local cert_manager = {
  cert_manager: (import '../jsonnet/cert-manager.libsonnet') + {
    cert_manager+: {
      values: |||
        crds:
          enabled: true
        resources:
          requests:
            cpu: 10m
            memory: 32Mi
          limits:
            memory: 64Mi
        prometheus:
          enabled: false
      |||,
    },
  },
};

local cert_manager_issuer = {
  apiVersion: 'cert-manager.io/v1',
  kind: 'Issuer',
  metadata: {
    name: 'letsencrypt-prod',
    namespace: 'cert-manager',
  },
  spec: {
    acme: {
      server: 'https://acme-v02.api.letsencrypt.org/directory',
      email: 'user@example.com',
      privateKeySecretRef: {
        name: 'letsencrypt-prod',
      },
      solvers: [
        {
          http01: {
            ingress: {
              ingressClassName: 'nginx',
            },
          },
        },
      ],
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
};

std.objectValues(mariadb_operator) + std.objectValues(dragonfly_operator) + std.objectValues(grafana_monitoring) + std.objectValues(metrics_server) + std.objectValues(cert_manager) + cert_manager_issuer + std.objectValues(this) + std.objectValues(secrets)
