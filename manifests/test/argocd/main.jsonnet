
  #params:: {
  #  namespace: 'default',
  #  mariadb:: {
  #    database:: {
  #      user_name: 'nextcloud',
  #      user_secret_name: 'nextcloud-mariadb',
  #      user_secret_key: 'MYSQL_PASSWORD',
  #    },
  #  },
  #},
local mariadb_operator = (import '../../../jsonnet/mariadb-operator.libsonnet');
local mariadb = (import '../../../jsonnet/mariadb/main.libsonnet');
local nextcloud = (import '../../../jsonnet/nextcloud/main.libsonnet');


std.objectValues(mariadb_operator) + std.objectValues(mariadb) + std.objectValues(nextcloud)
