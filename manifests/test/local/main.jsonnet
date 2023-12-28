local k = import 'github.com/jsonnet-libs/k8s-libsonnet/1.28/main.libsonnet';

local secret = k.core.v1.secret;

{
  minio: import 'minio.jsonnet',
  mariadb: import '../../../jsonnet/mariadb/main.libsonnet',
  nextcloud: import '../../../jsonnet/nextcloud/main.libsonnet',
  mariadb_secret: secret.new('nextcloud-mariadb', {
    MYSQL_USER: std.base64('user'),
    MYSQL_PASSWORD: std.base64('mariadb123'),
    MYSQL_DATABASE: std.base64('data-test'),
    MYSQL_HOST: std.base64('mariadb'),
  }, 'Opaque'),
  admin_secret: secret.new('nextcloud-admin', {
    NEXTCLOUD_ADMIN_USER: std.base64('admin'),
    NEXTCLOUD_ADMIN_PASSWORD: std.base64('admin'),
  }, 'Opaque'),
  s3_secret: secret.new('nextcloud-s3', {
    OBJECTSTORE_S3_HOST: std.base64('minio'),
    OBJECTSTORE_S3_BUCKET: std.base64('nextcloud'),
    OBJECTSTORE_S3_KEY: std.base64('minioadmin'),
    OBJECTSTORE_S3_SECRET: std.base64('minioadmin'),
    OBJECTSTORE_S3_USEPATH_STYLE: std.base64('true'),
    OBJECTSTORE_S3_PORT: std.base64('9000'),
    OBJECTSTORE_S3_SSL: std.base64('false'),
    OBJECTSTORE_S3_AUTOCREATE: std.base64('true'),
  }),
}
