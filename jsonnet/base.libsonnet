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

            if $.params.values != '' then {
              helm: {
                values: $.params.values,
              },
            } else {} +

                   if $.params.path != '' then {
                     path: $.params.path,
                   } else {} +

                          if $.params.chart != '' then {
                            chart: $.params.chart,
                          } else {},
  },
}
