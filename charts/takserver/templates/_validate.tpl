{{/* Validate combinations that JSON Schema cannot express. */}}
{{- define "takserver.validateValues" -}}
{{- if and .Values.database.migration.enabled .Values.database.migration.hook (or (ne .Values.database.mode "external") (not .Values.database.auth.existingSecret)) -}}
{{- fail "database.migration.hook=true requires database.mode=external and database.auth.existingSecret because pre-install hooks run before chart-managed database resources" -}}
{{- end -}}
{{- if and .Values.config.existing.core .Values.config.existing.coreSecret -}}
{{- fail "config.existing.core and config.existing.coreSecret are mutually exclusive" -}}
{{- end -}}
{{- if and .Values.database.auth.existingSecret .Values.config.generated (not .Values.config.core) (not .Values.config.existing.core) (not .Values.config.existing.coreSecret) -}}
{{- fail "config.generated cannot read database credentials from database.auth.existingSecret; provide config.existing.coreSecret (recommended) or config.core" -}}
{{- end -}}
{{- if and .Values.traefikRoutes.enabled (not .Values.traefik.enabled) -}}
{{- fail "traefikRoutes.enabled=true requires traefik.enabled=true" -}}
{{- end -}}
{{- if and .Values.database.migration.enabled (not .Values.database.migration.hook) (not .Values.serviceAccount.automount) -}}
{{- fail "serviceAccount.automount must be true when workloads wait for a release-managed migration Job" -}}
{{- end -}}
{{- if and .Values.gateway.enabled (not (.Capabilities.APIVersions.Has "gateway.networking.k8s.io/v1")) -}}
{{- fail "gateway.enabled=true requires Gateway API v1 CRDs to be installed before this chart" -}}
{{- end -}}

{{- range $key := list "helm.sh/chart" "app.kubernetes.io/name" "app.kubernetes.io/instance" "app.kubernetes.io/version" "app.kubernetes.io/part-of" "app.kubernetes.io/managed-by" -}}
{{- if hasKey $.Values.commonLabels $key -}}
{{- fail (printf "commonLabels must not override chart-managed label %s" $key) -}}
{{- end -}}
{{- end -}}
{{- range $key := list "app.kubernetes.io/name" "app.kubernetes.io/instance" "app.kubernetes.io/component" -}}
{{- if hasKey $.Values.podLabels $key -}}
{{- fail (printf "podLabels must not override selector label %s" $key) -}}
{{- end -}}
{{- end -}}

{{- range $roleName := list "api" "messaging" -}}
{{- $workload := index $.Values.workloads $roleName -}}
{{- if and $workload.autoscaling.enabled (gt (int $workload.autoscaling.minReplicas) (int $workload.autoscaling.maxReplicas)) -}}
{{- fail (printf "workloads.%s.autoscaling.maxReplicas must be greater than or equal to minReplicas" $roleName) -}}
{{- end -}}
{{- if $workload.autoscaling.enabled -}}
{{- range $metric := $workload.autoscaling.metrics -}}
{{- if and (eq $metric.type "Resource") (eq $metric.resource.name "cpu") (eq $metric.resource.target.type "Utilization") (not (dig "requests" "cpu" "" $workload.resources)) -}}
{{- fail (printf "workloads.%s.resources.requests.cpu is required for a CPU utilization HPA" $roleName) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- if and $workload.pdb.enabled (ne (toString $workload.pdb.maxUnavailable) "") (ne (toString $workload.pdb.minAvailable) "") -}}
{{- fail (printf "workloads.%s.pdb must set only one of minAvailable or maxUnavailable" $roleName) -}}
{{- end -}}
{{- if and $workload.pdb.enabled (eq (toString $workload.pdb.maxUnavailable) "") (eq (toString $workload.pdb.minAvailable) "") -}}
{{- fail (printf "workloads.%s.pdb must set minAvailable or maxUnavailable" $roleName) -}}
{{- end -}}
{{- end -}}

{{- range $roleName := list "api" "config" "messaging" "plugins" -}}
{{- $workload := index $.Values.workloads $roleName -}}
{{- range $key := list "app.kubernetes.io/name" "app.kubernetes.io/instance" "app.kubernetes.io/component" -}}
{{- if hasKey $workload.podLabels $key -}}
{{- fail (printf "workloads.%s.podLabels must not override selector label %s" $roleName $key) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
