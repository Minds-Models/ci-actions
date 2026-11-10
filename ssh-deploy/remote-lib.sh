# shellcheck shell=bash
# Helpers that ssh-deploy defines in every remote script before it runs.

# wait_healthy <container> [timeout_seconds, default 180]
# Returns once the container's healthcheck reports healthy. Fails on a missing
# healthcheck, a restart, an exited container or the timeout, and prints the
# container's recent logs. A crash-looping container counts as "running"
# between restarts, so only the health status proves the service came up.
wait_healthy() {
  local container="$1" timeout="${2:-180}" start restarts0 info status health restarts reason
  restarts0="$(docker inspect -f '{{.RestartCount}}' "$container")" || return 1
  start=$SECONDS
  while true; do
    info="$(docker inspect -f '{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}|{{.RestartCount}}' "$container")" || return 1
    IFS='|' read -r status health restarts <<<"$info"
    case "$health" in
      healthy)
        echo "✅ $container is healthy"
        return 0
        ;;
      none)
        echo "❌ $container has no healthcheck" >&2
        return 1
        ;;
    esac
    if ((restarts > restarts0)) || [[ "$status" == exited || "$status" == dead ]]; then
      reason="restarted or exited (status=$status, restarts=$restarts)"
    elif ((SECONDS - start >= timeout)); then
      reason="not healthy after ${timeout}s (status=$status, health=$health)"
    else
      sleep 3
      continue
    fi
    echo "❌ $container $reason" >&2
    docker logs --tail 100 "$container" >&2 || true
    return 1
  done
}
