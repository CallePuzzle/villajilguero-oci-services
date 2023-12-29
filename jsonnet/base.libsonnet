{
  params:: {
    name: error 'name is required',
    mattermost_notification_channel: '',
    destination_namespace: error 'destination_namespace is required',
    repo_url: error 'repo_url is required',
    target_revision: error 'target_revision is required',
    chart: error 'chart is required',
    values: '',
  },
  apiVersion: 'argoproj.io/v1alpha1',
  kind: 'Application',
  metadata: {
    name: $.params.name,
    namespace: 'argocd',
    finalizers: [
      'resources-finalizer.argocd.argoproj.io',
    ],
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
      chart: $.params.chart,
    } + if $.params.values != '' then {
      helm: {
        values: $.params.values,
      },
    } else {
    },
  },
}
