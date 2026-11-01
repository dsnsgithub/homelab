#!/usr/bin/env bash
# Refresh Argo CD Applications and wait until each is Synced and Healthy at a commit.
#
#   wait-argocd.sh --sha SHA (--project NAME | --apps a,b,c) [--appset NAME] [--timeout SECONDS]
#
# --project waits for every Application in that project (re-listed each poll, so
# Applications the root app creates mid-deploy are picked up). --apps waits for
# Applications that may not exist yet, such as previews an ApplicationSet creates.
# Writes a Markdown status table to $REPORT (default: $GITHUB_STEP_SUMMARY).
set -uo pipefail

ns=argocd
repo=https://github.com/dsnsgithub/homelab.git
timeout=900
degraded_grace=60
sha="" project="" apps="" appset=""
while [ $# -gt 0 ]; do
  case $1 in
    --sha) sha=$2; shift 2 ;;
    --project) project=$2; shift 2 ;;
    --apps) apps=$2; shift 2 ;;
    --appset) appset=$2; shift 2 ;;
    --timeout) timeout=$2; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
report=${REPORT:-${GITHUB_STEP_SUMMARY:-/dev/null}}

if [ -n "$appset" ]; then
  kubectl -n "$ns" annotate applicationset "$appset" \
    argocd.argoproj.io/application-set-refresh=true --overwrite >/dev/null
fi

targets() {
  if [ -n "$project" ]; then
    kubectl -n "$ns" get applications -o json \
      | jq -r --arg p "$project" '.items[] | select(.spec.project == $p) | .metadata.name'
  else
    tr ',' '\n' <<<"$apps"
  fi
}

# One JSON object per target: name, sync, health, revision, phase, message, ready.
status() {
  local all
  all=$(kubectl -n "$ns" get applications -o json)
  targets | while IFS= read -r app; do
    jq -c --arg app "$app" --arg sha "$sha" --arg repo "$repo" '
      (.items[] | select(.metadata.name == $app)) as $a
      | if $a == null then {name: $app, sync: "Missing", health: "-", revision: "-", phase: "-", ready: false}
        else
          ([$a.spec.source // empty] + ($a.spec.sources // [])) as $srcs
          | ([$srcs[] | .repoURL] | index($repo)) as $git
          | ([$a.status.sync.revision // empty] + ($a.status.sync.revisions // [])) as $revs
          | {
              name: $app,
              sync: ($a.status.sync.status // "Unknown"),
              health: ($a.status.health.status // "Unknown"),
              revision: (if $git == null then "chart" else ([$revs[] | select(test("^[0-9a-f]{40}$"))][0] // "-")[0:7] end),
              phase: ($a.status.operationState.phase // "-"),
              opRevision: (($a.status.operationState.syncResult.revision // "") + " " + (($a.status.operationState.syncResult.revisions // []) | join(" "))),
              message: ($a.status.operationState.message // ""),
              atSha: ($git == null or ($revs | index($sha)) != null)
            }
            | .ready = (.atSha and .sync == "Synced" and .health == "Healthy" and .phase != "Running")
        end' <<<"$all"
  done
}

table() {
  echo "| App | Sync | Health | Commit | Last sync |"
  echo "|---|---|---|---|---|"
  jq -r '"| \(.name) | \(.sync) | \(.health) | `\(.revision)` | \(.phase) |"' <<<"$1"
}

explain() {
  local app=$1
  echo "::group::Why $app isn't ready"
  kubectl -n "$ns" get application "$app" -o json | jq -r '
    (.status.conditions // [] | .[] | "condition \(.type): \(.message)"),
    ("sync operation: \(.status.operationState.phase // "-") \(.status.operationState.message // "")"),
    (.status.resources // [] | .[] | select(.health != null and .health.status != "Healthy")
      | "\(.kind)/\(.namespace // "-")/\(.name): \(.health.status) \(.health.message // "")"),
    (.status.resources // [] | .[] | select(.status != "Synced")
      | "\(.kind)/\(.namespace // "-")/\(.name): \(.status)")'
  echo "::endgroup::"
}

if [ -n "$project" ]; then
  for app in $(targets); do
    kubectl -n "$ns" annotate application "$app" argocd.argoproj.io/refresh=normal --overwrite >/dev/null
  done
fi

start=$(date +%s)
declare -A degraded_since
last=""
while true; do
  now=$(date +%s)
  current=$(status)
  if [ "$current" != "$last" ]; then
    echo "[$(date -u +%H:%M:%S)] $(jq -s 'map(select(.ready)) | length' <<<"$current")/$(jq -s length <<<"$current") ready"
    jq -r '"  \(.name): \(.sync) / \(.health) @ \(.revision) (sync \(.phase))"' <<<"$current"
    last=$current
  fi

  if [ -n "$current" ] && jq -s -e 'all(.ready)' <<<"$current" >/dev/null; then
    table "$current" >>"$report"
    echo "All applications are Synced and Healthy at ${sha:0:7}."
    exit 0
  fi

  failed=()
  while IFS= read -r app; do
    [ -z "$app" ] && continue
    failed+=("$app")
  done < <(jq -r --arg sha "$sha" 'select((.phase == "Failed" or .phase == "Error") and (.opRevision | contains($sha))) | .name' <<<"$current")
  while IFS= read -r app; do
    [ -z "$app" ] && continue
    degraded_since[$app]=${degraded_since[$app]:-$now}
    [ $((now - degraded_since[$app])) -ge $degraded_grace ] && failed+=("$app")
  done < <(jq -r 'select(.atSha and .health == "Degraded") | .name' <<<"$current")
  for app in "${!degraded_since[@]}"; do
    jq -e --arg a "$app" 'select(.name == $a and .health == "Degraded")' <<<"$current" >/dev/null || unset "degraded_since[$app]"
  done

  if [ "${#failed[@]}" -gt 0 ] || [ $((now - start)) -ge "$timeout" ]; then
    table "$current" >>"$report"
    if [ "${#failed[@]}" -gt 0 ]; then
      echo "::error::Failed: ${failed[*]}"
    else
      echo "::error::Timed out after ${timeout}s waiting for Argo CD."
      mapfile -t failed < <(jq -r 'select(.ready | not) | .name' <<<"$current")
    fi
    for app in "${failed[@]}"; do
      kubectl -n "$ns" get application "$app" >/dev/null 2>&1 && explain "$app"
    done
    exit 1
  fi
  sleep 5
done
