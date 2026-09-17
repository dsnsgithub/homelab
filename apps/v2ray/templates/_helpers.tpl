{{- /* Fixed resource names preserve DNS: v2ray-service referenced by web-proxy ExternalName. */ -}}
{{- define "v2ray.labels" -}}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: v2ray
{{- end -}}
