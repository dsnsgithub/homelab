#!/usr/bin/env bash
# Render every Argo CD Application and preview chart the way Argo CD would,
# schema-check the output, and validate the Talos machine configs.
# Needs no cluster access or secrets. Usage: validate.sh [render-dir]
set -uo pipefail

root=$(git rev-parse --show-toplevel)
out=${1:-$(mktemp -d)}
mkdir -p "$out/apps" "$out/previews"
k8s_version=$(yq '.kubernetesVersion' "$root/talos/topf.yaml")
failures=()

fail() {
  failures+=("$1: $2")
  echo "::error file=$1::$2"
}

# helm_args <source-json> <chart-dir-for-relative-values>
# Prints value-file and values-object flags for an Argo CD Helm source.
helm_values() {
  local src=$1 chart_dir=$2 tmp
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    case $f in
      '$homelab/'*) echo "--values=$root/${f#\$homelab/}" ;;
      *) echo "--values=$chart_dir/$f" ;;
    esac
  done < <(jq -r '.helm.valueFiles[]?' <<<"$src")
  if jq -e '.helm.valuesObject' <<<"$src" >/dev/null; then
    tmp=$(mktemp)
    jq '.helm.valuesObject' <<<"$src" | yq -P >"$tmp"
    echo "--values=$tmp"
  fi
}

render_app() {
  local file=$1 name ns sources src dest
  name=$(yq '.metadata.name' "$file")
  ns=$(yq '.spec.destination.namespace' "$file")
  dest="$out/apps/$name.yaml"
  : >"$dest"
  sources=$(yq -o=json -I=0 '(.spec.sources // [.spec.source])[]' "$file")
  while IFS= read -r src; do
    [ -z "$src" ] && continue
    local chart path args=()
    chart=$(jq -r '.chart // empty' <<<"$src")
    path=$(jq -r '.path // empty' <<<"$src")
    if [ -n "$chart" ]; then
      mapfile -t args < <(helm_values "$src" "$root")
      helm template "$name" "$chart" --repo "$(jq -r .repoURL <<<"$src")" \
        --version "$(jq -r .targetRevision <<<"$src")" --namespace "$ns" \
        --kube-version "$k8s_version" --include-crds "${args[@]}" >>"$dest" \
        || fail "$file" "helm template failed for chart $chart"
    elif [ -n "$path" ] && [ -f "$root/$path/Chart.yaml" ]; then
      mapfile -t args < <(helm_values "$src" "$root/$path")
      helm template "$name" "$root/$path" --namespace "$ns" \
        --kube-version "$k8s_version" --include-crds "${args[@]}" >>"$dest" \
        || fail "$file" "helm template failed for $path"
    elif [ -n "$path" ]; then
      for m in "$root/$path"/*.yaml; do printf -- '---\n'; cat "$m"; done >>"$dest"
    fi
  done <<<"$sources"
}

echo "::group::Render Argo CD Applications"
for file in "$root"/argocd/root-app.yaml "$root"/argocd/apps/*.yaml; do
  echo "${file#"$root"/}"
  render_app "$file"
done
echo "::endgroup::"

echo "::group::Render previews"
for values in "$root"/charts/*/values-preview.yaml; do
  chart_dir=$(dirname "$values")
  chart=$(basename "$chart_dir")
  ns="$chart-pr-0"
  dest="$out/previews/$chart.yaml"
  echo "charts/$chart"
  if ! helm template "$ns" "$chart_dir" --namespace "$ns" --kube-version "$k8s_version" \
    --values "$values" --set "namespace=$ns" >"$dest"; then
    fail "${values#"$root"/}" "helm template failed"
    continue
  fi
  # Previews may only create their own namespace and resources inside it.
  stray=$(yq -N "select(. != null) | select(
      (.kind == \"Namespace\" and .metadata.name != \"$ns\") or
      (.kind != \"Namespace\" and .metadata.namespace != \"$ns\")
    ) | .kind + \"/\" + .metadata.name" "$dest")
  [ -n "$stray" ] && fail "${values#"$root"/}" "preview renders resources outside $ns: $(tr '\n' ' ' <<<"$stray")"
  lb=$(yq -N 'select(.kind == "Service" and .spec.type == "LoadBalancer") | .metadata.name' "$dest")
  [ -n "$lb" ] && fail "${values#"$root"/}" "preview would claim a LoadBalancer IP: $lb"
  routes=$(yq -N 'select(.kind == "IngressRoute") | .metadata.name' "$dest")
  [ -n "$routes" ] && fail "${values#"$root"/}" "preview would claim production hostnames: $routes"
done
echo "::endgroup::"

echo "::group::Schema validation"
# Upstream charts ship their own CRDs, and there's no published schema for CRD objects.
if ! kubeconform -strict -summary -output text -skip CustomResourceDefinition \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  "$out/apps" "$out/previews"; then
  fail "argocd/apps" "rendered manifests failed schema validation (see log)"
fi
echo "::endgroup::"

echo "::group::Talos machine configs"
talos_tmp=$(mktemp -d)
cp -r "$root/talos/." "$talos_tmp/"
talosctl gen secrets --force -o "$talos_tmp/secrets.yaml" >/dev/null
if topf --topfconfig "$talos_tmp/topf.yaml" --log-level warn render -o "$talos_tmp/out"; then
  for config in "$talos_tmp"/out/*.yaml; do
    talosctl validate --mode metal --strict -c "$config" \
      || fail "talos" "$(basename "$config" .yaml) machine config is invalid"
  done
else
  fail "talos" "topf render failed"
fi
rm -rf "$talos_tmp"
echo "::endgroup::"

if [ "${#failures[@]}" -gt 0 ]; then
  printf '\n%d problem(s):\n' "${#failures[@]}"
  printf ' - %s\n' "${failures[@]}"
  exit 1
fi
echo "All manifests and machine configs are valid."
