#!/usr/bin/env bash
# End-to-end tests for ssh-deploy.sh against the sshd from tests/sshd-up.sh,
# whose key runs tests/fake-gate.sh. Needs jq.
# Usage: tests/test-ssh-deploy.sh <keydir>
set -uo pipefail

keydir="${1:?usage: test-ssh-deploy.sh <keydir>}"
deploy="$(cd "$(dirname "$0")/.." && pwd)/ssh-deploy/ssh-deploy.sh"

export SSH_DEPLOY_HOST=127.0.0.1
export SSH_DEPLOY_PORT=2222
export SSH_DEPLOY_USER=deploy
SSH_DEPLOY_KEY="$(cat "$keydir/client")"
export SSH_DEPLOY_KEY
SSH_DEPLOY_HOST_KEY="$(cut -d' ' -f1,2 "$keydir/host.pub")"
export SSH_DEPLOY_HOST_KEY
export SSH_DEPLOY_ENVIRONMENT=production
export SSH_DEPLOY_SHA=0123456789abcdef0123456789abcdef01234567
export SSH_DEPLOY_ENVS=""
unset GITHUB_ACTOR GITHUB_RUN_ID GITHUB_REPOSITORY

failures=0
out=""
rc=0

run() {
  out="$("$deploy" 2>&1)"
  rc=$?
}

# The JSON the fake gate received.
payload() {
  sed -n 's/^PAYLOAD=//p' <<<"$out"
}

check() {
  local name="$1"
  shift
  if "$@"; then
    echo "ok    $name"
  else
    echo "FAIL  $name (rc=$rc)"
    printf '%s\n' "$out" | sed 's/^/      /'
    failures=$((failures + 1))
  fi
}

run
check "the gate gets '<environment> <sha>' as the command" grep -qx "CMD=production $SSH_DEPLOY_SHA" <<<"$out"
check "no envs sends an empty object" test "$rc" = 0 -a "$(payload)" = "{}"

# Quotes, expansions, backslashes and newlines must arrive byte-for-byte.
export TRICKY=$'it\'s "quoted" $HOME `id` $(id) \\ ; & | *\nsecond line\t tab'
export EMPTY=""
SSH_DEPLOY_ENVS=" TRICKY , EMPTY " run
check "env values round-trip exactly as JSON" test "$rc" = 0 -a "$(payload | jq -r .TRICKY)" = "$TRICKY"
check "empty values are sent" test "$(payload | jq -c .)" = "$(jq -cn --arg t "$TRICKY" '{TRICKY: $t, EMPTY: ""}')"

GITHUB_ACTOR=octocat GITHUB_RUN_ID=42 run
check "GitHub metadata rides along for the audit log" test "$(payload | jq -r '.GITHUB_ACTOR + "/" + .GITHUB_RUN_ID')" = "octocat/42"

export EXIT_CODE=7
SSH_DEPLOY_ENVS="EXIT_CODE" run
check "the gate's exit code propagates" test "$rc" = 7

# `envs: |` in YAML yields one name per line.
export LINE_A=a LINE_B=b LINE_C=c
SSH_DEPLOY_ENVS=$'LINE_A,LINE_B\nLINE_C\n' run
check "multi-line envs sends every name" test "$rc" = 0 -a "$(payload | jq -r '.LINE_A + .LINE_B + .LINE_C')" = "abc"

wrong_key="$(ssh-keygen -q -t ed25519 -N '' -f "$keydir/wrong" <<<y >/dev/null 2>&1; cut -d' ' -f1,2 "$keydir/wrong.pub")"
SSH_DEPLOY_HOST_KEY="$wrong_key" run
check "wrong host key is refused" test "$rc" != 0 -a "${out/CMD=/}" = "$out"

unset NOT_SET
SSH_DEPLOY_ENVS="NOT_SET" run
check "unset env name fails before connecting" grep -q "NOT_SET' is listed in envs but not set" <<<"$out"

SSH_DEPLOY_ENVS="BAD-NAME" run
check "invalid env name is rejected" grep -q "invalid env name 'BAD-NAME'" <<<"$out"

SSH_DEPLOY_ENVS="LINE_A, LINE B" run
check "env name with inner whitespace is rejected" grep -q "invalid env name 'LINE B'" <<<"$out"

SSH_DEPLOY_ENVS="SSH_DEPLOY_KEY" run
check "SSH_DEPLOY_* names are refused" grep -q "reserved env name 'SSH_DEPLOY_KEY'" <<<"$out"

SSH_DEPLOY_HOST_KEY="" run
check "empty input is rejected" grep -q "SSH_DEPLOY_HOST_KEY is empty" <<<"$out"

for bad in "Production" "prod;id" "-x" "prod uction"; do
  SSH_DEPLOY_ENVIRONMENT="$bad" run
  check "environment '$bad' is rejected" grep -q "invalid environment" <<<"$out"
done

for bad in "0123456" "0123456789ABCDEF0123456789ABCDEF01234567" "0123456789abcdef0123456789abcdef01234567 x"; do
  SSH_DEPLOY_SHA="$bad" run
  check "sha '$bad' is rejected" grep -q "sha must be 40 lowercase hex characters" <<<"$out"
done

SSH_DEPLOY_HOST_KEY="$wrong_key"$'\n'"* $SSH_DEPLOY_HOST_KEY" run
check "multi-line host-key is rejected" grep -q "host-key must be one line" <<<"$out"

SSH_DEPLOY_PORT="22a" run
check "non-numeric port is rejected" grep -q "invalid port '22a'" <<<"$out"

SSH_DEPLOY_PORT="02222" run
check "zero-padded port is normalised" test "$rc" = 0

SSH_DEPLOY_USER="-oProxyCommand=id" run
check "user starting with '-' is rejected" grep -q "invalid user" <<<"$out"

SSH_DEPLOY_HOST="-oProxyCommand=id" run
check "host starting with '-' is rejected" grep -q "invalid host" <<<"$out"

# A user-level ssh config must not be able to supply its own host key. ssh reads
# the config from the passwd home, so this runs only on a throwaway CI runner.
if [[ "${CI:-}" == true ]]; then
  ssh_config="$(getent passwd "$(id -u)" | cut -d: -f6)/.ssh/config"
  [[ ! -e "$ssh_config" ]] || { echo "refusing to overwrite $ssh_config"; exit 1; }
  mkdir -p "$(dirname "$ssh_config")"
  printf 'Host *\n  KnownHostsCommand /bin/echo [127.0.0.1]:2222 %s\n' "$SSH_DEPLOY_HOST_KEY" >"$ssh_config"
  SSH_DEPLOY_HOST_KEY="$wrong_key" run
  check "ssh config cannot override the pinned host key" test "$rc" != 0 -a "${out/CMD=/}" = "$out"
  rm -f "$ssh_config"
else
  echo "skip  ssh config cannot override the pinned host key (CI only)"
fi

if ((failures)); then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
