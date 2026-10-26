local secrets = import 'secrets.json';

(import '../lib/main.libsonnet')(secrets)
