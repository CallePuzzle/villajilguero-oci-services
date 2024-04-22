local get_path(path) = if path != '' then {
  path: path,
} else {};

local get_chart(chart) = if chart != '' then {
  chart: chart,
} else {};

local get_values(values) = if values != '' then {
  helm: {
    values: values,
  },
} else {};

{
  params:: {
    name: error 'name is required',
    mattermost_notification_channel: '',
    destination_namespace: error 'destination_namespace is required',
    repo_url: error 'repo_url is required',
    target_revision: error 'target_revision is required',
    path: '',
    chart: '',
    values: '',
    extra_source: {},
  },
  apiVersion: 'argoproj.io/v1alpha1',
  kind: 'Application',
  metadata: {
    name: $.params.name,
    namespace: 'argocd',
  },
  spec: {
    destination: {
      namespace: $.params.destination_namespace,
      server: 'https://kubernetes.default.svc',
    },
    project: 'default',
    source: {
              repoURL: $.params.repo_url,
              targetRevision: $.params.target_revision,
            } +
            $.params.extra_source +
            get_path($.params.path) +
            get_chart($.params.chart) +
            get_values($.params.values),
  },
}
