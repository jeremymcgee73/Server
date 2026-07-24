{{/* Render one TAK Server component PodDisruptionBudget. */}}
{{- define "takserver.pdb" -}}
{{- $root := .root -}}
{{- $roleName := .component -}}
{{- $workload := index $root.Values.workloads $roleName -}}
{{- if $workload.pdb.enabled }}
apiVersion: policy/v1
kind: PodDisruptionBudget
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
{{- if ne (toString $workload.pdb.maxUnavailable) "" }}
  maxUnavailable: {{ $workload.pdb.maxUnavailable }}
{{- else }}
  minAvailable: {{ $workload.pdb.minAvailable }}
{{- end }}
  unhealthyPodEvictionPolicy: {{ $workload.pdb.unhealthyPodEvictionPolicy }}
  selector:
    matchLabels:
      {{- include "takserver.selectorLabels" $root | nindent 6 }}
      app.kubernetes.io/component: {{ $roleName }}
{{- end }}
{{- end }}
