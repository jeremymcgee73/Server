{{/* Render one TAK Server component Deployment. */}}
{{- define "takserver.deployment" -}}
{{- $root := .root -}}
{{- $role := .role -}}
{{- $hasCore := or $root.Values.config.generated $root.Values.config.existing.core $root.Values.config.existing.coreSecret $root.Values.config.core -}}
{{- $coreUsesSecret := or $root.Values.config.existing.coreSecret (and (not $root.Values.config.existing.core) (or $root.Values.config.generated $root.Values.config.core)) -}}
{{- $hasIgnite := or $root.Values.config.generated $root.Values.config.existing.ignite $root.Values.config.ignite -}}
{{- $bootstrapCertificates := and $root.Values.certificates.bootstrap.enabled (not $root.Values.config.existing.certificates) (eq (len $root.Values.config.certificates) 0) -}}
{{- $hasCertificates := or $root.Values.config.existing.certificates (gt (len $root.Values.config.certificates) 0) $bootstrapCertificates -}}
{{- $workload := index $root.Values.workloads $role.name }}
{{- $image := index $root.Values.images $role.name }}
{{- $autoscaling := default dict $workload.autoscaling }}
{{- $autoscalingSupported := or (eq $role.name "api") (eq $role.name "messaging") }}
{{- $autoscalingEnabled := and $autoscalingSupported (default false $autoscaling.enabled) }}
{{- $hasEnv := or $role.postgres (eq $role.name "messaging") (eq $role.name "plugins") (gt (len $workload.extraEnv) 0) }}
{{- $hasMounts := or $hasCertificates (and $role.core $hasCore) (and $role.ignite $hasIgnite) (gt (len $root.Values.extraVolumeMounts) 0) (gt (len $workload.extraVolumeMounts) 0) }}
{{- $hasVolumes := or $hasCertificates (and $role.core $hasCore) (and $role.ignite $hasIgnite) (gt (len $root.Values.extraVolumes) 0) (gt (len $workload.extraVolumes) 0) }}
{{- $waitForMigration := and $role.postgres $root.Values.database.migration.enabled (not $root.Values.database.migration.hook) -}}
{{- $hasInitContainers := or $bootstrapCertificates $waitForMigration -}}
{{- if or (ne $role.name "plugins") $workload.enabled }}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "takserver.fullname" $root }}-{{ $role.name }}
  labels:
    {{- include "takserver.labels" $root | nindent 4 }}
    app.kubernetes.io/component: {{ $role.name }}
{{- with $root.Values.commonAnnotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
{{- end }}
spec:
  revisionHistoryLimit: {{ $root.Values.revisionHistoryLimit }}
  minReadySeconds: {{ $root.Values.minReadySeconds }}
{{- with $root.Values.deploymentStrategy }}
  strategy:
    {{- toYaml . | nindent 4 }}
{{- end }}
{{- if not $autoscalingEnabled }}
  replicas: {{ $workload.replicaCount }}
{{- end }}
  selector:
    matchLabels:
      {{- include "takserver.selectorLabels" $root | nindent 6 }}
      app.kubernetes.io/component: {{ $role.name }}
  template:
    metadata:
      labels:
        {{- include "takserver.labels" $root | nindent 8 }}
        app.kubernetes.io/component: {{ $role.name }}
{{- with $root.Values.podLabels }}
        {{- toYaml . | nindent 8 }}
{{- end }}
{{- with $workload.podLabels }}
        {{- toYaml . | nindent 8 }}
{{- end }}
      annotations:
        checksum/config: {{ include "takserver.configChecksum" $root }}
{{- with $root.Values.podAnnotations }}
        {{- toYaml . | nindent 8 }}
{{- end }}
{{- with $workload.podAnnotations }}
        {{- toYaml . | nindent 8 }}
{{- end }}
    spec:
      serviceAccountName: {{ include "takserver.serviceAccountName" $root }}
      automountServiceAccountToken: {{ $root.Values.serviceAccount.automount }}
      terminationGracePeriodSeconds: {{ $root.Values.terminationGracePeriodSeconds }}
{{- with $root.Values.priorityClassName }}
      priorityClassName: {{ . | quote }}
{{- end }}
{{- with $root.Values.runtimeClassName }}
      runtimeClassName: {{ . | quote }}
{{- end }}
{{- with $root.Values.schedulerName }}
      schedulerName: {{ . | quote }}
{{- end }}
{{- with $root.Values.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
{{- end }}
{{- with $root.Values.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
{{- end }}
{{- with $root.Values.affinity }}
      affinity:
        {{- toYaml . | nindent 8 }}
{{- end }}
{{- with $root.Values.topologySpreadConstraints }}
      topologySpreadConstraints:
        {{- toYaml . | nindent 8 }}
{{- end }}
{{- with $root.Values.podSecurityContext }}
      securityContext:
        {{- toYaml . | nindent 8 }}
{{- end }}
{{- if $hasInitContainers }}
      initContainers:
{{- if $bootstrapCertificates }}
        - name: wait-for-certificate-secret
          image: {{ include "takserver.image" (dict "image" $root.Values.certificates.bootstrap.publisherImage) | quote }}
          imagePullPolicy: {{ $root.Values.certificates.bootstrap.publisherImage.pullPolicy }}
          command: ["/bin/sh", "-ec"]
          args:
            - |
              deadline=$(( $(date +%s) + {{ $root.Values.certificates.bootstrap.waitTimeoutSeconds }} ))
              while [ "$(date +%s)" -lt "$deadline" ]; do
                if [ -s /certificate-secret/takserver.jks ] && \
                   [ -s /certificate-secret/truststore-root.jks ] && \
                   [ -s /certificate-secret/fed-truststore.jks ]; then
                  exit 0
                fi
                sleep 2
              done
              echo "Timed out waiting for certificate Secret {{ include "takserver.certificateSecretName" $root }}" >&2
              exit 1
          resources:
            {{- toYaml $root.Values.certificates.bootstrap.publisherResources | nindent 12 }}
{{- with $root.Values.securityContext }}
          securityContext:
            {{- toYaml . | nindent 12 }}
{{- end }}
          volumeMounts:
            - name: certificates
              mountPath: /certificate-secret
              readOnly: true
{{- end }}
{{- if $waitForMigration }}
        - name: wait-for-database-migration
          image: {{ include "takserver.image" (dict "image" $root.Values.database.migration.waiterImage) | quote }}
          imagePullPolicy: {{ $root.Values.database.migration.waiterImage.pullPolicy }}
          command: ["/bin/sh", "-ec"]
          args:
            - |
              api="https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT_HTTPS}"
              token_file=/var/run/secrets/kubernetes.io/serviceaccount/token
              ca_file=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
              auth="Authorization: Bearer $(cat "$token_file")"
              job_url="${api}/apis/batch/v1/namespaces/{{ $root.Release.Namespace }}/jobs/{{ include "takserver.databaseMigrationJobName" $root }}"
              deadline=$(( $(date +%s) + {{ $root.Values.database.migration.waitTimeoutSeconds }} ))
              while [ "$(date +%s)" -lt "$deadline" ]; do
                body=$(curl --silent --show-error --cacert "$ca_file" --header "$auth" "$job_url" || true)
                if echo "$body" | grep -Eq '"succeeded"[[:space:]]*:[[:space:]]*[1-9][0-9]*'; then
                  exit 0
                fi
                if echo "$body" | grep -Eq '"type"[[:space:]]*:[[:space:]]*"Failed"' && \
                   echo "$body" | grep -Eq '"status"[[:space:]]*:[[:space:]]*"True"'; then
                  echo "Database migration Job failed." >&2
                  exit 1
                fi
                sleep 2
              done
              echo "Timed out waiting for database migration Job {{ include "takserver.databaseMigrationJobName" $root }}" >&2
              exit 1
          resources:
            {{- toYaml $root.Values.database.migration.waiterResources | nindent 12 }}
{{- with $root.Values.securityContext }}
          securityContext:
            {{- toYaml . | nindent 12 }}
{{- end }}
{{- end }}
{{- end }}
      containers:
        - name: takserver-{{ $role.name }}
          image: {{ include "takserver.image" (dict "image" $image) | quote }}
          imagePullPolicy: {{ $image.pullPolicy }}
          command:
            {{- toYaml $role.command | nindent 12 }}
{{- if $hasEnv }}
          env:
{{- if $role.postgres }}
            - name: POSTGRES_HOST
              value: {{ include "takserver.databaseHost" $root | quote }}
            - name: POSTGRES_PORT
              value: {{ include "takserver.databasePort" $root | quote }}
{{- end }}
{{- if eq $role.name "messaging" }}
            - name: spring_profiles_active
              value: k8cluster
{{- end }}
{{- if eq $role.name "plugins" }}
            - name: spring_profiles_active
              value: k8cluster
{{- end }}
{{- with $workload.extraEnv }}
{{ toYaml . | nindent 12 }}
{{- end }}
{{- end }}
{{- with $root.Values.securityContext }}
          securityContext:
            {{- toYaml . | nindent 12 }}
{{- end }}
          resources:
            {{- toYaml $workload.resources | nindent 12 }}
{{- if $role.ports }}
          ports:
{{- range $port := $role.ports }}
            - name: {{ $port.name }}
              containerPort: {{ $port.containerPort }}
              protocol: TCP
{{- end }}
{{- end }}
          readinessProbe:
            tcpSocket:
              port: {{ $role.healthPort }}
            initialDelaySeconds: 10
            periodSeconds: 10
            failureThreshold: 12
          startupProbe:
            tcpSocket:
              port: {{ $role.healthPort }}
            periodSeconds: 10
            failureThreshold: 30
          livenessProbe:
            tcpSocket:
              port: {{ $role.healthPort }}
            periodSeconds: 30
            failureThreshold: 6
{{- if $hasMounts }}
          volumeMounts:
{{- if $hasCertificates }}
            - name: certificates
              mountPath: /certs-configmap
              readOnly: true
{{- end }}
{{- if and $role.core $hasCore }}
            - name: core-config
              mountPath: /CoreConfig.xml
              subPath: CoreConfig.xml
              readOnly: true
{{- end }}
{{- if and $role.ignite $hasIgnite }}
            - name: ignite-config
              mountPath: /TAKIgniteConfig.xml
              subPath: TAKIgniteConfig.xml
              readOnly: true
{{- end }}
{{- with $root.Values.extraVolumeMounts }}
{{ toYaml . | nindent 12 }}
{{- end }}
{{- with $workload.extraVolumeMounts }}
{{ toYaml . | nindent 12 }}
{{- end }}
{{- end }}
{{- if $hasVolumes }}
      volumes:
{{- if $hasCertificates }}
        - name: certificates
          secret:
            secretName: {{ include "takserver.certificateSecretName" $root }}
{{- if $bootstrapCertificates }}
            optional: true
{{- end }}
{{- end }}
{{- if and $role.core $hasCore }}
        - name: core-config
{{- if $coreUsesSecret }}
          secret:
            secretName: {{ include "takserver.coreConfigName" $root }}
            items:
              - key: {{ $root.Values.config.existing.coreSecretKey | quote }}
                path: CoreConfig.xml
{{- else }}
          configMap:
            name: {{ include "takserver.coreConfigName" $root }}
{{- end }}
{{- end }}
{{- if and $role.ignite $hasIgnite }}
        - name: ignite-config
          configMap:
            name: {{ include "takserver.igniteConfigName" $root }}
{{- end }}
{{- with $root.Values.extraVolumes }}
{{ toYaml . | nindent 8 }}
{{- end }}
{{- with $workload.extraVolumes }}
{{ toYaml . | nindent 8 }}
{{- end }}
{{- end }}
{{- with $root.Values.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
{{- end }}
{{- end }}
{{- end }}
