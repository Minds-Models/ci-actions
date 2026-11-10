#!/usr/bin/env bash
# Runs SSH_DEPLOY_SCRIPT on the remote host. Inputs arrive as SSH_DEPLOY_* env
# variables from action.yml; each name listed in SSH_DEPLOY_ENVS is exported remotely.
set -euo pipefail

fail() {
  echo "::error::ssh-deploy: $*" >&2
  exit 1
}

for input in SSH_DEPLOY_HOST SSH_DEPLOY_PORT SSH_DEPLOY_USER SSH_DEPLOY_KEY SSH_DEPLOY_HOST_KEY SSH_DEPLOY_SCRIPT; do
  [[ -n "${!input:-}" ]] || fail "$input is empty"
done

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

(umask 077 && printf '%s\n' "$SSH_DEPLOY_KEY" >"$workdir/key")

known_host="$SSH_DEPLOY_HOST"
[[ "$SSH_DEPLOY_PORT" == 22 ]] || known_host="[$SSH_DEPLOY_HOST]:$SSH_DEPLOY_PORT"
printf '%s %s\n' "$known_host" "$SSH_DEPLOY_HOST_KEY" >"$workdir/known_hosts"

# Values travel inside the script on stdin, so they never reach argv on either host.
payload=""
IFS=',' read -ra names <<<"$SSH_DEPLOY_ENVS"
for name in "${names[@]}"; do
  name="${name//[[:space:]]/}"
  [[ -n "$name" ]] || continue
  [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || fail "invalid env name '$name'"
  [[ -v "$name" ]] || fail "env '$name' is listed in envs but not set on the step"
  payload+="$(printf 'export %s=%q' "$name" "${!name}")"$'\n'
done

# bash parses the whole group before running it. Commands that read stdin then
# get /dev/null and cannot consume the rest of the script.
payload+=$'{\n'"$SSH_DEPLOY_SCRIPT"$'\n} </dev/null\n'

printf '%s' "$payload" | ssh \
  -i "$workdir/key" \
  -p "$SSH_DEPLOY_PORT" \
  -o UserKnownHostsFile="$workdir/known_hosts" \
  -o GlobalKnownHostsFile=/dev/null \
  -o StrictHostKeyChecking=yes \
  -o BatchMode=yes \
  -o IdentitiesOnly=yes \
  -o ServerAliveInterval=30 \
  "$SSH_DEPLOY_USER@$SSH_DEPLOY_HOST" 'bash -se'
