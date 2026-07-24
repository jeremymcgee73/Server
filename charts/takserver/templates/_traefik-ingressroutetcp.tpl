{{/* Render one Traefik TCP route for a TAK Server port. */}}
{{- define "takserver.traefikIngressRouteTCP" -}}
{{- $root := .root -}}
{{- $route := .route -}}
{{- if and $root.Values.traefik.enabled $root.Values.traefikRoutes.enabled }}
{{- $fullname := include "takserver.fullname" $root -}}
apiVersion: traefik.io/v1alpha1
kind: IngressRouteTCP
metadata:
  name: {{ $fullname }}-{{ $route.name }}
  labels:
    {{- include "takserver.labels" $root | nindent 4 }}
{{- with $root.Values.commonAnnotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
{{- end }}
spec:
  entryPoints:
    - {{ $route.entryPoint }}
  routes:
    - match: HostSNI(`*`)
      services:
        - name: {{ $route.service }}
          port: {{ $route.port }}
  tls:
    passthrough: true
{{- end }}
{{- end }}
