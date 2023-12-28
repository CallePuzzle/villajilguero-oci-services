{
  params:: {
    namespace: 'default',
    mariadb:: {
      database:: {
        user_name: 'nextcloud',
        user_secret_name: 'nextcloud-mariadb',
        user_secret_key: 'MYSQL_PASSWORD',
      },
    },
  },
  mariadb_operator: (import 'mariadb-operator.libsonnet'),
  mariadb: (import 'mariadb/main.libsonnet'),
  nextcloud: (import 'nextcloud/main.libsonnet'),
}
