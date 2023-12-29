local tanka = import "github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet";
local helm = tanka.helm.new(std.thisFile);

{
    mariadboperator: helm.template("mariadb-operator", "../charts/mariadb-operator", {}),
}
