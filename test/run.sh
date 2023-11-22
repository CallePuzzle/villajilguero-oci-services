#!/usr/bin/env bash

set -o errexit

kind create cluster --config kind-config.yaml || true

kubectl --context kind-jilgue apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
