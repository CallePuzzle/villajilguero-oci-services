{
  params:: {
    namespace: error 'namespace is required',
    user_name: 'user',
    user_secret_name: 'user-secret',
    user_secret_key: 'user-key',
    database_name: 'data-test',
    grant_name: 'grant',
  },
  user: {
    apiVersion: 'mariadb.mmontes.io/v1alpha1',
    kind: 'User',
    metadata: {
      namespace: $.params.namespace,
      name: $.params.user_name,
    },
    spec: {
      mariaDbRef: {
        name: 'mariadb',
      },
      passwordSecretKeyRef: {
        name: $.params.user_secret_name,
        key: $.params.user_secret_key,
      },
      maxUserConnections: 20,
      host: '%',
      retryInterval: '5s',
    },
  },
  database: {
    apiVersion: 'mariadb.mmontes.io/v1alpha1',
    kind: 'Database',
    metadata: {
      namespace: $.params.namespace,
      name: $.params.database_name,
    },
    spec: {
      mariaDbRef: {
        name: 'mariadb',
      },
      characterSet: 'utf8',
      collate: 'utf8_general_ci',
      retryInterval: '5s',
    },
  },
  grant: {
    apiVersion: 'mariadb.mmontes.io/v1alpha1',
    kind: 'Grant',
    metadata: {
      namespace: $.params.namespace,
      name: $.params.grant_name,
    },
    spec: {
      mariaDbRef: {
        name: 'mariadb',
      },
      privileges: [
        'ALL',
      ],
      database: $.params.database_name,
      table: '*',
      username: $.params.user_name,
      grantOption: true,
      host: '%',
      retryInterval: '5s',
    },
  },
}
