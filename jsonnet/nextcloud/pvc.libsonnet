local k = import '../vendor/1.28/main.libsonnet';

local pvc = k.core.v1.persistentVolumeClaim;

{
  params:: {
    namespace: error 'namespace is required',
    storage_class_name: 'standard',
    storage: '1Gi',
  },
  html: pvc.new('nextcloud-html') +
        pvc.metadata.withNamespace($.params.namespace) +
        pvc.spec.withAccessModes(['ReadWriteOnce']) +
        pvc.spec.resources.withRequests({
          storage: $.params.storage,
        }) +
        pvc.spec.withStorageClassName($.params.storage_class_name),
}
