{{- define "kube-vip.labels" -}}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/name: kube-vip-ds
app.kubernetes.io/version: {{ .Values.image.tag }}
{{- end -}}
