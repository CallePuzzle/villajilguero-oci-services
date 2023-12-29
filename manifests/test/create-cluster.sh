#!/usr/bin/env bash

set -o errexit

kind create cluster --config kind-config.yaml || true

kind_context="kind-local"

kubectl --context $kind_context apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
