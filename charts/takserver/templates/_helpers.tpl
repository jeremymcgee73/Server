{{/* Expand the chart name. */}}
{{- define "takserver.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Create a release-scoped name. */}}
{{- define "takserver.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name (include "takserver.name" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{- define "takserver.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "takserver.labels" -}}
helm.sh/chart: {{ include "takserver.chart" . }}
app.kubernetes.io/name: {{ include "takserver.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/part-of: takserver
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{- define "takserver.selectorLabels" -}}
app.kubernetes.io/name: {{ include "takserver.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "takserver.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "takserver.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "takserver.databaseHost" -}}
{{- if eq .Values.database.mode "embedded" }}
{{- printf "%s-postgres" (include "takserver.fullname" .) }}
{{- else }}
{{- .Values.database.external.host }}
{{- end }}
{{- end }}

{{- define "takserver.databasePort" -}}
{{- if eq .Values.database.mode "embedded" }}5432{{ else }}{{ .Values.database.external.port }}{{ end }}
{{- end }}

{{- define "takserver.databaseSecretName" -}}
{{- default (printf "%s-database" (include "takserver.fullname" .)) .Values.database.auth.existingSecret }}
{{- end }}

{{- define "takserver.coreConfigName" -}}
{{- if .Values.config.existing.coreSecret }}
{{- .Values.config.existing.coreSecret }}
{{- else }}
{{- default (printf "%s-core-config" (include "takserver.fullname" .)) .Values.config.existing.core }}
{{- end }}
{{- end }}

{{- define "takserver.igniteConfigName" -}}
{{- default (printf "%s-ignite-config" (include "takserver.fullname" .)) .Values.config.existing.ignite }}
{{- end }}

{{- define "takserver.certificateSecretName" -}}
{{- if .Values.config.existing.certificates }}
{{- .Values.config.existing.certificates }}
{{- else }}
{{- default (printf "%s-certificates" (include "takserver.fullname" .)) .Values.certificates.bootstrap.secretName }}
{{- end }}
{{- end }}

{{- define "takserver.certificateBootstrapServiceAccountName" -}}
{{- printf "%s-certificate-bootstrap" (include "takserver.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "takserver.image" -}}
{{- if .image.digest -}}
{{- printf "%s@%s" .image.repository .image.digest -}}
{{- else -}}
{{- printf "%s:%s" .image.repository .image.tag -}}
{{- end -}}
{{- end }}

{{- define "takserver.imagePullPolicy" -}}
{{- default .root.Values.imagePullPolicy .image.pullPolicy -}}
{{- end }}

{{- define "takserver.databaseMigrationJobName" -}}
{{- $base := printf "%s-database-migration" (include "takserver.fullname" .) -}}
{{- if .Values.database.migration.hook -}}
{{- $base | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $hashInput := dict "image" .Values.images.databaseSetup "databaseMode" .Values.database.mode "external" .Values.database.external "auth" .Values.database.auth "migration" .Values.database.migration -}}
{{- $hash := toJson $hashInput | sha256sum | trunc 8 -}}
{{- printf "%s-%s" ($base | trunc 54 | trimSuffix "-") $hash -}}
{{- end -}}
{{- end }}

{{- define "takserver.databaseImage" -}}
{{- $repository := printf "%s/%s" .registry .repository -}}
{{- if .digest -}}
{{- printf "%s@%s" $repository .digest -}}
{{- else -}}
{{- printf "%s:%s" $repository .tag -}}
{{- end -}}
{{- end }}
