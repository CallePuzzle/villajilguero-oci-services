local k = import '../vendor/1.28/main.libsonnet';

local deployment = k.apps.v1.deployment;
local container = k.core.v1.container;
local envFrom = k.core.v1.envFromSource;
local mount = k.core.v1.volumeMount;
local volume = k.core.v1.volume;

{
  params:: {
    name: error 'name is required',
    namespace: error 'namespace is required',
    port: error 'port is required',
    version: '28',
    db_secret_name: 'nextcloud-mariadb',
    admin_secret_name: 'nextcloud-admin',
    s3_secret_name: 'nextcloud-s3',
    s3_configmap_name: 'nextcloud-s3',
    nginx_default_configmap_name: 'nextcloud-nginx-default',
    host: 'nextcloud.localhost',
    redis_host: 'redis-dragonfly',
    enable_notify_push: false,
  },
  local nextcloud_container = container.new('nextcloud', 'nextcloud:' + $.params.version + '-fpm') +
                              container.withEnvFrom([
                                envFrom.secretRef.withName($.params.db_secret_name),
                                envFrom.secretRef.withName($.params.s3_secret_name),
                                envFrom.secretRef.withName($.params.admin_secret_name),
                              ]) +
                              container.withEnvMap({
                                NEXTCLOUD_TRUSTED_DOMAINS: $.params.host,
                                REDIS_HOST: $.params.redis_host,
                              }),

  local nginx = container.new('nginx', 'nginx:1.25') +
                container.withPorts(k.core.v1.containerPort.newNamed(80, 'http')) +
                container.withVolumeMounts(
                  [
                    mount.new('nginx-config', '/etc/nginx/nginx.conf') + mount.withSubPath('nginx.conf'),
                  ]
                ),

  local nextcloud_occ = container.new('occ', 'nextcloud:' + $.params.version) +
                        container.withArgs(['sleep', 'infinity']) +
                        container.securityContext.withRunAsUser(33),

  local notify_push = container.new('notify_push', 'nextcloud:' + $.params.version) +
                      container.withArgs([
                        './custom_apps/notify_push/bin/$(uname -m)/notify_push',
                        '--database-url',
                        'mysql://$(echo $MYSQL_USER):$(echo $MYSQL_PASSWORD)@$(echo $MYSQL_HOST)/$(echo $MYSQL_DATABASE)',
                        '--database-prefix',
                        'oc_',
                        '--redis-host',
                        'redis://$(echo $REDIS_HOST)',
                        '--nextcloud-url',
                        'http://' + $.params.name + ':8080',
                        '--port',
                        '7867',
                      ]) +
                      container.securityContext.withRunAsUser(33) +
                      container.withEnvFrom([
                        envFrom.secretRef.withName($.params.db_secret_name),
                      ]) +
                      container.withEnvMap({
                        NEXTCLOUD_TRUSTED_DOMAINS: $.params.host,
                        REDIS_HOST: $.params.redis_host,
                      }),

  local containers = if $.params.enable_notify_push then
    [nextcloud_container, nginx, nextcloud_occ, notify_push]
  else
    [nextcloud_container, nginx, nextcloud_occ],

  deployment: deployment.new(
                $.params.name, 1, containers, {
                  app: $.params.name,
                },
              ) +
              deployment.metadata.withNamespace($.params.namespace) +
              deployment.spec.strategy.withType('Recreate') +
              deployment.pvcVolumeMount('nextcloud-html', '/var/www/html') +
              deployment.spec.template.spec.withVolumesMixin([
                volume.fromConfigMap(
                  name='nginx-config',
                  configMapName=$.params.nginx_default_configmap_name,
                ),
              ]),

}
