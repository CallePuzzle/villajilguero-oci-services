local k = import 'github.com/jsonnet-libs/k8s-libsonnet/1.28/main.libsonnet';

local deployment = k.apps.v1.deployment;
local container = k.core.v1.container;
local service = k.core.v1.service;
local pvc = k.core.v1.persistentVolumeClaim;

{
  local minio_container = container.new('minio', 'quay.io/minio/minio:latest') +
                          container.withArgs(['server', '/data', '--console-address', ':9001']) +
                          container.withPorts([
                            k.core.v1.containerPort.newNamed(9000, 'http'),
                            k.core.v1.containerPort.newNamed(9001, 'console'),
                          ]),
  deployment: deployment.new('minio', 1, [minio_container], {
                app: 'minio',
              }) +
              deployment.pvcVolumeMount('minio-data', '/data'),

  local ports = [
    k.core.v1.servicePort.newNamed('http', 9000, 'http'),
    k.core.v1.servicePort.newNamed('console', 9001, 'console'),
  ],
  service: service.new('minio', {
    app: 'minio',
  }, ports),

  pvc: pvc.new('minio-data') +
       pvc.spec.withAccessModes(['ReadWriteOnce']) +
       pvc.spec.resources.withRequests({
         storage: '10Gi',
       }),
}
