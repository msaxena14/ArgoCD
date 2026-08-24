{{- define "hello-world.name" -}}
{{- .Chart.Name -}}
{{- end -}}

{{- define "hello-world.labels" -}}
app.kubernetes.io/name: {{ include "hello-world.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
