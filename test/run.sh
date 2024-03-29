#!/usr/bin/env bash

set -o errexit

export NAME=jilgue
export MARIADB_PATH=$(pwd)/mariadb
source ~/.b2_env

envsubst < kind-config.yaml.tpl | tee kind-config.yaml

kind create cluster --config kind-config.yaml || true

kind_context="kind-$NAME"

kubectl --context $kind_context apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

sleep 60

kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=90s

terraform init
terraform apply  -var="kind_context=$kind_context" -auto-approve

echo "Admin password: $(kubectl --context $kind_context -n argocd get secret argocd-initial-admin-secret --template={{.data.password}} | base64 -d)"
