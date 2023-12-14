{
  user: {
    apiVersion: 'mariadb.mmontes.io/v1alpha1',
    kind: 'User',
    metadata: {
      namespace: 'default',
      name: 'user',
    },
    spec: {
      mariaDbRef: {
        name: 'mariadb',
      },
      passwordSecretKeyRef: {
        name: 'user',
        key: 'password',
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
      namespace: 'default',
      name: 'data-test',
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
      namespace: 'default',
      name: 'grant',
    },
    spec: {
      mariaDbRef: {
        name: 'mariadb',
      },
      privileges: [
        'ALL',
      ],
      database: 'data-test',
      table: '*',
      username: 'user',
      grantOption: true,
      host: '%',
      retryInterval: '5s',
    },
  },
}
