local k = import '../vendor/1.28/main.libsonnet';

local pvc = k.core.v1.persistentVolumeClaim;

local cm = k.core.v1.configMap;

{
  mariadb: {
    apiVersion: 'mariadb.mmontes.io/v1alpha1',
    kind: 'MariaDB',
    metadata: {
      namespace: 'default',
      name: 'mariadb',
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
      image: 'mariadb:11.0.3',
      imagePullPolicy: 'IfNotPresent',
      port: 3306,
      volumeClaimTemplate: {
        resources: {
          requests: {
            storage: '1Gi',
          },
        },
        accessModes: [
          'ReadWriteOnce',
        ],
      },
      volumes: [
        {
          name: 'mariabackup',
          persistentVolumeClaim: {
            claimName: 'mariabackup',
          },
        },
      ],
      volumeMounts: [
        {
          name: 'mariabackup',
          mountPath: '/var/mariadb/backup/',
        },
      ],
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
          cpu: '300m',
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
  backup: pvc.new('mariabackup') + pvc.spec.withAccessModes(['ReadWriteOnce']) + pvc.spec.resources.withRequests({ storage: '1Gi' }),
  config_map: cm.new('mariadb', {
    UMASK: '0660',
    UMASK_DIR: '0750',
  }),
}