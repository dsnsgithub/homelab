#!/usr/bin/env bash
# Configures ArgoCD's GitHub webhook receiver so pushes refresh apps
# immediately instead of waiting for the ~3 minute poll interval.
# Pull-based sync stays exactly as-is — this only speeds up refresh.
#
# Prereq: github.com must reach https://<ARGOCD_HOST>/api/webhook
# (router port-forward to the argocd-server-lb 10.3.3.9:443, or a tunnel).
# With ArgoCD's default self-signed TLS, check "Disable SSL verification"
# in the GitHub webhook settings (or terminate with a real cert).
#
# Usage: ARGOCD_HOST=argocd.example.com [GITHUB_WEBHOOK_SECRET=...] ./configure-github-webhook.sh
# If the secret is unset, a random one is generated and printed — paste it
# into the GitHub webhook settings. Re-running with the same secret is safe.
set -euo pipefail

: "${ARGOCD_HOST:?set ARGOCD_HOST to the hostname github.com dials (e.g. argocd.example.com)}"
SECRET="${GITHUB_WEBHOOK_SECRET:-$(head -c 32 /dev/urandom | base64 | tr -d '/+=' | head -c 32)}"

echo "== storing webhook secret in argocd-secret (key: webhook.github.secret) =="
kubectl -n argocd patch secret argocd-secret --type merge \
  -p "{\"stringData\":{\"webhook.github.secret\":\"$SECRET\"}}"
# The server reads the secret at startup — restart to pick it up.
kubectl -n argocd rollout restart deploy/argocd-server
kubectl -n argocd rollout status deploy/argocd-server --timeout=5m

cat <<EOF

== now configure the GitHub side (repo Settings -> Webhooks -> Add webhook) ==
Payload URL:    https://$ARGOCD_HOST/api/webhook
Content type:   application/json
Secret:         $SECRET
SSL:            disable verification unless ARGOCD_HOST has a real cert
Events:         "Just the push event" (ArgoCD ignores everything else)

Verify: push a commit, then check GitHub webhook "Recent Deliveries" (green
200s) and watch the app refresh instantly:
  kubectl -n argocd get applications -w
EOF
