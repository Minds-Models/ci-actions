#!/usr/bin/env bash
# Runs SSH_DEPLOY_SCRIPT on the remote host. Inputs arrive as SSH_DEPLOY_* env
# variables from action.yml; each name listed in SSH_DEPLOY_ENVS is exported remotely.
# Internal variables carry the _sd_ prefix, and env names may not use it, so a
# listed name always resolves to the caller's value.
set -euo pipefail

_sd_fail() {
  echo "::error::ssh-deploy: $*" >&2
  exit 1
}

for _sd_input in SSH_DEPLOY_HOST SSH_DEPLOY_PORT SSH_DEPLOY_USER SSH_DEPLOY_KEY SSH_DEPLOY_HOST_KEY SSH_DEPLOY_SCRIPT; do
  [[ -n "${!_sd_input:-}" ]] || _sd_fail "$_sd_input is empty"
done

# These reach ssh's argv and known_hosts, so only plain values pass.
[[ "$SSH_DEPLOY_HOST" =~ ^[A-Za-z0-9][A-Za-z0-9.:-]*$ ]] || _sd_fail "invalid host"
[[ "$SSH_DEPLOY_USER" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]] || _sd_fail "invalid user"
[[ "$SSH_DEPLOY_PORT" =~ ^[0-9]{1,5}$ ]] || _sd_fail "invalid port '$SSH_DEPLOY_PORT'"
_sd_port=$((10#$SSH_DEPLOY_PORT))
((_sd_port >= 1 && _sd_port <= 65535)) || _sd_fail "invalid port '$SSH_DEPLOY_PORT'"
[[ "$SSH_DEPLOY_HOST_KEY" =~ ^[a-z0-9@.-]+\ [A-Za-z0-9+/]+=*$ ]] ||
  _sd_fail "host-key must be one line '<type> <base64>'"

_sd_workdir="$(mktemp -d)"
trap 'rm -rf "$_sd_workdir"' EXIT

(umask 077 && printf '%s\n' "$SSH_DEPLOY_KEY" >"$_sd_workdir/key")

_sd_known_host="$SSH_DEPLOY_HOST"
((_sd_port == 22)) || _sd_known_host="[$SSH_DEPLOY_HOST]:$_sd_port"
printf '%s %s\n' "$_sd_known_host" "$SSH_DEPLOY_HOST_KEY" >"$_sd_workdir/known_hosts"

# Values travel inside the script on stdin, so they never reach argv on either host.
_sd_payload="$(cat "$(dirname "${BASH_SOURCE[0]}")/remote-lib.sh")"$'\n'
while IFS= read -r _sd_name; do
  _sd_name="${_sd_name#"${_sd_name%%[![:space:]]*}"}"
  _sd_name="${_sd_name%"${_sd_name##*[![:space:]]}"}"
  [[ -n "$_sd_name" ]] || continue
  [[ "$_sd_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || _sd_fail "invalid env name '$_sd_name'"
  [[ "$_sd_name" != SSH_DEPLOY_* && "$_sd_name" != _sd_* ]] || _sd_fail "reserved env name '$_sd_name'"
  [[ -v "$_sd_name" ]] || _sd_fail "env '$_sd_name' is listed in envs but not set on the step"
  _sd_payload+="$(printf 'export %s=%q' "$_sd_name" "${!_sd_name}")"$'\n'
done < <(tr ',' '\n' <<<"$SSH_DEPLOY_ENVS")

# bash parses the whole group before running it. Commands that read stdin then
# get /dev/null and cannot consume the rest of the script.
_sd_payload+=$'{\n'"$SSH_DEPLOY_SCRIPT"$'\n} </dev/null\n'

# -F /dev/null: no ssh_config file may add host keys, proxies or Match exec hooks.
printf '%s' "$_sd_payload" | ssh \
  -F /dev/null \
  -i "$_sd_workdir/key" \
  -p "$_sd_port" \
  -o UserKnownHostsFile="$_sd_workdir/known_hosts" \
  -o GlobalKnownHostsFile=/dev/null \
  -o StrictHostKeyChecking=yes \
  -o UpdateHostKeys=no \
  -o BatchMode=yes \
  -o IdentitiesOnly=yes \
  -o ConnectTimeout=30 \
  -o ServerAliveInterval=30 \
  -l "$SSH_DEPLOY_USER" \
  -- "$SSH_DEPLOY_HOST" 'bash -se'
