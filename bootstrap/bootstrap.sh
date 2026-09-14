#!/usr/bin/env bash
# Day-1 platform, run once from the repo root after `talosctl kubeconfig`
# works. Idempotent — safe to re-run after bumping versions in
# bootstrap/versions.env.
#
# Layer map:
#   Talos (extraManifests) -> ArgoCD
#   this script             -> sealed-secrets controller + root app
#   ArgoCD root app         -> everything else in git
set -euo pipefail
cd "$(dirname "$0")/.." # repo root
source bootstrap/versions.env

echo "== ArgoCD v${ARGOCD_VERSION} (idempotent, heals drift from any channel) =="
kubectl apply -n argocd --server-side --force-conflicts \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/v${ARGOCD_VERSION}/manifests/install.yaml"

echo "== sealed-secrets controller v${SEALED_SECRETS_VERSION} =="
kubectl apply -f "https://github.com/bitnami/sealed-secrets/releases/download/v${SEALED_SECRETS_VERSION}/controller.yaml"

echo "== waiting for ArgoCD server =="
kubectl -n argocd rollout status deploy/argocd-server --timeout=10m

echo "== root app: ArgoCD takes it from here =="
kubectl apply -f argocd/root-app.yaml
kubectl -n argocd get applications
echo "done. Create the github-token + notifications PAT secrets next (see README: Staging environments / GitHub sync statuses)."
