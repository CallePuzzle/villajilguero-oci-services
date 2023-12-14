local k = import '../vendor/1.28/main.libsonnet';

local deployment = k.apps.v1.deployment;
local container = k.core.v1.container;

// Deployment for a nextcloud apache image
{
  local nextcloud_container = container.new('nextcloud', 'nextcloud:latest'),
  deployment: deployment.new(
    'nextcloud', 1, [nextcloud_container], {
      app: 'nextcloud',
    },
  ),
}
