{{- /*
Shared labels for minecraft chart. Resource names are fixed (no Release.Name
prefix) to preserve in-cluster DNS: limbo-service:25565 is referenced by
velocity.toml, and mc-proxy-service is the public entrypoint.
*/ -}}
{{- define "minecraft.labels" -}}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: minecraft
{{- end -}}
