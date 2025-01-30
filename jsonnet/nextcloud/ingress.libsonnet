local k = import '../vendor/1.28/main.libsonnet';

local ingress = k.networking.v1.ingress;
local ingressTLS = k.networking.v1.ingressTLS;

{
  params:: {
    name: error 'name is required',
    namespace: error 'namespace is required',
    host: 'nextcloud.localhost',
    ingress_class_name: 'nginx',
  },

  local rule = k.networking.v1.ingressRule.withHost($.params.host) +
               k.networking.v1.ingressRule.http.withPaths([
                 k.networking.v1.httpIngressPath.withPath('/') +
                 k.networking.v1.httpIngressPath.withPathType('Prefix') +
                 k.networking.v1.httpIngressPath.backend.service.withName($.params.name) +
                 k.networking.v1.httpIngressPath.backend.service.port.withNumber($.params.port),
               ]),

  ingress: ingress.new($.params.name) +
           ingress.metadata.withNamespace($.params.namespace) +
           ingress.metadata.withAnnotations({
             'nginx.ingress.kubernetes.io/proxy-body-size': '512m',
           }) +
           ingress.spec.withRules([rule]) +
           ingress.spec.withIngressClassName($.params.ingress_class_name) +
           ingress.spec.withTLS(ingressTLS.withHosts([$._config.host]) + ingressTLS.withSecretName($.params.name + '-tls')),
}
