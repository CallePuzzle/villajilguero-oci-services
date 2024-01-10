local enc_secrets = import 'secrets.json';

local namespace = 'default';

local this = (import '../jsonnet/main.libsonnet') + {
    params+: {
        namespace: namespace,
        database+: {
            user_name: enc_secrets.nextcloud_mariadb.user,
            database_name: enc_secrets.nextcloud_mariadb.database,
        }
    }
};

local mariadb_operator = {
    mariadb_operator: import '../jsonnet/mariadb-operator.libsonnet'
};

local k = import '../jsonnet/vendor/1.28/main.libsonnet';

local secret = k.core.v1.secret;

local secrets = {
  mariadb_secret: secret.new('nextcloud-mariadb', {
    MYSQL_USER: std.base64(enc_secrets.nextcloud_mariadb.user),
    MYSQL_PASSWORD: std.base64(enc_secrets.nextcloud_mariadb.password),
    MYSQL_DATABASE: std.base64(enc_secrets.nextcloud_mariadb.database),
    MYSQL_HOST: std.base64(enc_secrets.nextcloud_mariadb.host),
  }) + secret.metadata.withNamespace(namespace),
  admin_secret: secret.new('nextcloud-admin', {
    NEXTCLOUD_ADMIN_USER: std.base64(enc_secrets.nextcloud_admin.user),
    NEXTCLOUD_ADMIN_PASSWORD: std.base64(enc_secrets.nextcloud_admin.password),
  }) + secret.metadata.withNamespace(namespace),
  s3_secret: secret.new('nextcloud-s3', {
    OBJECTSTORE_S3_HOST: std.base64(enc_secrets.nextcloud_s3.host),
    OBJECTSTORE_S3_BUCKET: std.base64(enc_secrets.nextcloud_s3.bucket),
    OBJECTSTORE_S3_KEY: std.base64(enc_secrets.nextcloud_s3.key),
    OBJECTSTORE_S3_SECRET: std.base64(enc_secrets.nextcloud_s3.secret),
    OBJECTSTORE_S3_USEPATH_STYLE: std.base64('true'),
    OBJECTSTORE_S3_SSL: std.base64('true'),
  }) + secret.metadata.withNamespace(namespace),
};

std.objectValues(mariadb_operator) + std.objectValues(this) + std.objectValues(secrets)
