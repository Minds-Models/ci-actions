#!/usr/bin/env bash
# Tests for ssh-deploy/remote-lib.sh against throwaway local containers (needs Docker).
set -uo pipefail

# shellcheck source-path=SCRIPTDIR source=../ssh-deploy/remote-lib.sh
. "$(cd "$(dirname "$0")/.." && pwd)/ssh-deploy/remote-lib.sh"

image='ubuntu:24.04@sha256:fe81560990fae86dc4743202b2cb4d3df98d0bcf949173cecef15ce1127ef852'
prefix=ssh-deploy-rl
failures=0

cleanup() { docker rm -f "$prefix-healthy" "$prefix-nohc" "$prefix-crash" "$prefix-unhealthy" >/dev/null 2>&1; }
trap cleanup EXIT
cleanup

docker run -d --name "$prefix-healthy" --health-cmd true --health-interval 1s "$image" sleep 300 >/dev/null
docker run -d --name "$prefix-nohc" "$image" sleep 300 >/dev/null
# Fails its healthcheck and dies after 2 s, like a worker that cannot reach its broker.
docker run -d --name "$prefix-crash" --restart always --health-cmd false --health-interval 1s "$image" sh -c 'echo boom; sleep 2; exit 1' >/dev/null
docker run -d --name "$prefix-unhealthy" --health-cmd false --health-interval 1s --health-retries 1 "$image" sleep 300 >/dev/null

check() {
  local name="$1" want_rc="$2" want_text="$3" container="$4" timeout="$5" out rc
  out="$(wait_healthy "$container" "$timeout" 2>&1)"
  rc=$?
  if [[ "$rc" == "$want_rc" && "$out" == *"$want_text"* ]]; then
    echo "ok    $name"
  else
    echo "FAIL  $name (rc=$rc)"
    printf '%s\n' "$out" | sed 's/^/      /'
    failures=$((failures + 1))
  fi
}

check "healthy container passes" 0 "is healthy" "$prefix-healthy" 30
check "container without healthcheck fails" 1 "has no healthcheck" "$prefix-nohc" 30
check "crash-looping container fails and shows logs" 1 "boom" "$prefix-crash" 60
check "unhealthy container fails at the timeout" 1 "not healthy after 6s" "$prefix-unhealthy" 6

if ((failures)); then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
