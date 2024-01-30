local k = import '../vendor/1.28/main.libsonnet';

local pvc = k.core.v1.persistentVolumeClaim;

local cm = k.core.v1.configMap;

local secret = k.core.v1.secret;

{
  params:: {
    name: 'mariadb',
    namespace: error 'namespace is required',
    version: '11.0.3',
    storage: '1Gi',
    backup_storage: '1Gi',
    storage_class_name: 'standard',
  },
  mariadb: {
    apiVersion: 'mariadb.mmontes.io/v1alpha1',
    kind: 'MariaDB',
    metadata: {
      namespace: $.params.namespace,
      name: $.params.name,
    },
    spec: {
      rootPasswordSecretKeyRef: {
        name: 'mariadb',
        key: 'root-password',
      },
      database: 'mariadb',
      username: 'mariadb',
      passwordSecretKeyRef: {
        name: 'mariadb',
        key: 'password',
      },
      image: 'mariadb:' + $.params.version,
      imagePullPolicy: 'IfNotPresent',
      port: 3306,
      volumeClaimTemplate: {
        resources: {
          requests: {
            storage: $.params.storage,
          },
        },
        accessModes: [
          'ReadWriteOnce',
        ],
        storageClassName: $.params.storage_class_name,
      },
      //volumes: [
      //  {
      //    name: 'mariabackup',
      //    persistentVolumeClaim: {
      //      claimName: 'mariabackup',
      //    },
      //  },
      //],
      //volumeMounts: [
      //  {
      //    name: 'mariabackup',
      //    mountPath: '/var/mariadb/backup/',
      //  },
      //],
      bootstrapFrom: {
        backupRef: {
          name: $.params.name,
        },
        targetRecoveryTime: '2024-01-30T20:28:18Z',
      },
      myCnf: |||
        [mariadb]
        bind-address=*
        default_storage_engine=InnoDB
        binlog_format=row
        innodb_autoinc_lock_mode=2
        max_allowed_packet=256M
      |||,
      resources: {
        requests: {
          cpu: '100m',
          memory: '128Mi',
        },
        limits: {
          memory: '512Mi',
        },
      },
      env: [
        {
          name: 'TZ',
          value: 'SYSTEM',
        },
      ],
      envFrom: [
        {
          configMapRef: {
            name: 'mariadb',
          },
        },
      ],
      podSecurityContext: {
        runAsUser: 0,
      },
      securityContext: {
        allowPrivilegeEscalation: false,
      },
      livenessProbe: {
        exec: {
          command: [
            'bash',
            '-c',
            'mariadb -u root -p"${MARIADB_ROOT_PASSWORD}" -e "SELECT 1;"',
          ],
        },
        initialDelaySeconds: 20,
        periodSeconds: 10,
        timeoutSeconds: 5,
      },
      readinessProbe: {
        exec: {
          command: [
            'bash',
            '-c',
            'mariadb -u root -p"${MARIADB_ROOT_PASSWORD}" -e "SELECT 1;"',
          ],
        },
        initialDelaySeconds: 20,
        periodSeconds: 10,
        timeoutSeconds: 5,
      },
      podDisruptionBudget: {
        maxUnavailable: '50%',
      },
      updateStrategy: {
        type: 'RollingUpdate',
      },
      service: {
        type: 'ClusterIP',
      },
    },
  },
  backup: pvc.new('mariabackup') +
          pvc.metadata.withNamespace($.params.namespace) +
          pvc.spec.withAccessModes(['ReadWriteOnce']) +
          pvc.spec.resources.withRequests({ storage: $.params.backup_storage }) +
          pvc.spec.withStorageClassName($.params.storage_class_name),
  config_map: cm.new('mariadb', {
    UMASK: '0660',
    UMASK_DIR: '0750',
  }) + cm.metadata.withNamespace($.params.namespace),
  secret: secret.new('mariadb', {
    'root-password': std.base64('password'),
    password: std.base64('password'),
  }) + secret.metadata.withNamespace($.params.namespace),
}
