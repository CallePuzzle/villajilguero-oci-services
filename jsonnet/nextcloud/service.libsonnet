local k = import '../vendor/1.28/main.libsonnet';

local service = k.core.v1.service;

{
  params:: {
    name: error 'name is required',
    namespace: error 'namespace is required',
    port: error 'port is required',
  },
  local port = k.core.v1.servicePort.newNamed($.params.name, $.params.port, 'http'),
  service: service.new('nextcloud', {
             app: $.params.name,
           }, port) +
           service.metadata.withNamespace($.params.namespace),
}
