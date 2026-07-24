{{/* Render one TAK Server component HorizontalPodAutoscaler. */}}
{{- define "takserver.hpa" -}}
{{- $root := .root -}}
{{- $roleName := .component -}}
{{- $workload := index $root.Values.workloads $roleName }}
{{- if $workload.autoscaling.enabled }}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ include "takserver.fullname" $root }}-{{ $roleName }}
  labels:
    {{- include "takserver.labels" $root | nindent 4 }}
    app.kubernetes.io/component: {{ $roleName }}
{{- with $root.Values.commonAnnotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
{{- end }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ include "takserver.fullname" $root }}-{{ $roleName }}
  minReplicas: {{ $workload.autoscaling.minReplicas }}
  maxReplicas: {{ $workload.autoscaling.maxReplicas }}
{{- with $workload.autoscaling.metrics }}
  metrics:
    {{- toYaml . | nindent 4 }}
{{- end }}
{{- with $workload.autoscaling.behavior }}
  behavior:
    {{- toYaml . | nindent 4 }}
{{- end }}
{{- end }}
{{- end }}
