local k = import '../vendor/1.28/main.libsonnet';

local deployment = k.apps.v1.deployment;
local container = k.core.v1.container;
local envFrom = k.core.v1.envFromSource;
local service = k.core.v1.service;

{
  params:: {
    name: error 'name is required',
    namespace: error 'namespace is required',
    port: error 'port is required',
    version: 'latest',
    db_secret_name: 'nextcloud-mariadb',
    admin_secret_name: 'nextcloud-admin',
    s3_secret_name: 'nextcloud-s3',
  },
  local nextcloud_container = container.new('nextcloud', 'nextcloud:' + $.params.version) +
                              container.withEnvFrom([
                                envFrom.secretRef.withName($.params.db_secret_name),
                                envFrom.secretRef.withName($.params.s3_secret_name),
                                envFrom.secretRef.withName($.params.admin_secret_name),
                              ]) +
                              container.withPorts(k.core.v1.containerPort.newNamed($.params.port, 'http')),

  deployment: deployment.new(
    $.params.name, 1, [nextcloud_container], {
      app: $.params.name,
    },
  ) + deployment.metadata.withNamespace($.params.namespace),
}
