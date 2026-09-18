{{/*
Emit a literal Go template expression (e.g. {{.path.basename}}) so it is not
interpreted by Helm's template engine. Argo CD evaluates it at generation time:
{{ include "argocd-pr-generator.gotpl" ".path.basename" }} -> {{.path.basename}}
*/}}
{{- define "argocd-pr-generator.gotpl" -}}
{{- printf "{{%s}}" . -}}
{{- end }}