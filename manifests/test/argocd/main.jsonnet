local this = (import '../../../jsonnet/main.libsonnet') + {
    params+: {
        namespace: 'default2',
    }
};

local k = import '../../../jsonnet/vendor/1.28/main.libsonnet';

local secret = k.core.v1.secret;

local enc_secrets = import 'secrets.json';

local secrets = {
  mariadb_secret: secret.new('nextcloud-mariadb', {
    MYSQL_USER: std.base64(enc_secrets.nextcloud_mariadb.user),
    MYSQL_PASSWORD: std.base64(enc_secrets.nextcloud_mariadb.password),
    MYSQL_DATABASE: std.base64(enc_secrets.nextcloud_mariadb.database),
    MYSQL_HOST: std.base64(enc_secrets.nextcloud_mariadb.host),
  },),
  admin_secret: secret.new('nextcloud-admin', {
    NEXTCLOUD_ADMIN_USER: std.base64(enc_secrets.nextcloud_admin.user),
    NEXTCLOUD_ADMIN_PASSWORD: std.base64(enc_secrets.nextcloud_admin.password),
  },),
};

std.objectValues(this) + std.objectValues(secrets)
