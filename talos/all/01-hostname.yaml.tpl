# Hostname per node, templated from topf.yaml nodes[].host. (.tpl files are
# the only ones rendered through Go templates; plain .yaml patches pass
# through untouched, so $patch directives need no escaping.)
apiVersion: v1alpha1
kind: HostnameConfig
auto: "off"
hostname: {{ .Node.Host }}
