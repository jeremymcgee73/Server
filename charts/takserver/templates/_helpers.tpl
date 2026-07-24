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
app.kubernetes.io/managed-by: {{ .Release.Service }}
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
{{- default (printf "%s-core-config" (include "takserver.fullname" .)) .Values.config.existing.core }}
{{- end }}

{{- define "takserver.igniteConfigName" -}}
{{- default (printf "%s-ignite-config" (include "takserver.fullname" .)) .Values.config.existing.ignite }}
{{- end }}

{{- define "takserver.certificateSecretName" -}}
{{- default (printf "%s-certificates" (include "takserver.fullname" .)) .Values.config.existing.certificates }}
{{- end }}
