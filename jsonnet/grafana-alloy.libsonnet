(import './base.libsonnet') + {
  params+:: {
    name: 'alloy',
    destination_namespace: 'alloy',
    repo_url: 'https://grafana.github.io/helm-charts',
    target_revision: '0.1.1',
    chart: 'alloy',
    values: |||
      alloy:
        configMap:
          content: |-
            logging {
              level  = "info"
            format = "logfmt"
            }
            discovery.kubernetes "pods" {
              role = "pod"
            }
            discovery.kubernetes "nodes" {
              role = "node"
            }
            discovery.kubernetes "services" {
              role = "service"
            }
            discovery.kubernetes "endpoints" {
              role = "endpoints"
            }
            discovery.kubernetes "endpointslices" {
              role = "endpointslice"
            }
            discovery.kubernetes "ingresses" {
              role = "ingress"
            }
    |||,
  },
} + { spec+: { syncPolicy: { syncOptions: ['CreateNamespace=true'] } } }
