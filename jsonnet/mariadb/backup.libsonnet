{
  params:: {
    namespace: error 'namespace is required',
    name: 'mariadb',
    max_retention: '720h',
    bucket: error 'bucket is required',
    endpoint: error 'endpoint is required',
    access_secret_name: 'nextcloud-s3',
  },
  backup: {
    apiVersion: 'mariadb.mmontes.io/v1alpha1',
    kind: 'Backup',
    metadata: {
      namespace: $.params.namespace,
      name: $.params.name,
    },
    spec: {
      mariaDbRef: {
        name: $.params.name,
      },
      maxRetention: $.params.max_retention,
      storage: {
        s3: {
          bucket: $.params.bucket,
          endpoint: $.params.endpoint,
          accessKeyIdSecretKeyRef: {
            name: $.params.access_secret_name,
            key: 'OBJECTSTORE_S3_KEY',
          },
          secretAccessKeySecretKeyRef: {
            name: $.params.access_secret_name,
            key: 'OBJECTSTORE_S3_SECRET',
          },
        },
      },
    },
  },
}
