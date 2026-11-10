#!/usr/bin/env bash
# End-to-end tests for ssh-deploy.sh against the sshd from tests/sshd-up.sh.
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
export SSH_DEPLOY_ENVS=""

failures=0
out=""
rc=0

run() {
  out="$(SSH_DEPLOY_SCRIPT="$1" "$deploy" 2>&1)"
  rc=$?
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

# Quotes, expansions, backslashes and newlines must arrive byte-for-byte.
export TRICKY=$'it\'s "quoted" $HOME `id` $(id) \\ ; & | *\nsecond line\t tab'
export EMPTY=""
# shellcheck disable=SC2016 # Expands on the remote host.
SSH_DEPLOY_ENVS=" TRICKY , EMPTY " run 'printf "%s|[%s]" "$TRICKY" "$EMPTY"'
check "env values round-trip exactly" test "$rc" = 0 -a "$out" = "$TRICKY|[]"

# A command that reads stdin must not swallow the rest of the script.
run $'cat\necho after-cat'
check "stdin readers do not consume the script" test "$rc" = 0 -a "$out" = "after-cat"

run $'false\necho unreachable'
check "set -e stops at the first failure" test "$rc" != 0 -a "${out/unreachable/}" = "$out"

run 'exit 7'
check "remote exit code propagates" test "$rc" = 7

run $'cat <<EOF\nheredoc ${SSH_DEPLOY_PORT:-unset}\nEOF'
check "heredocs work and runner-only vars stay local" test "$rc" = 0 -a "$out" = "heredoc unset"

wrong_key="$(ssh-keygen -q -t ed25519 -N '' -f "$keydir/wrong" <<<y >/dev/null 2>&1; cut -d' ' -f1,2 "$keydir/wrong.pub")"
SSH_DEPLOY_HOST_KEY="$wrong_key" run 'echo connected'
check "wrong host key is refused" test "$rc" != 0 -a "${out/connected/}" = "$out"

unset NOT_SET
SSH_DEPLOY_ENVS="NOT_SET" run 'echo connected'
check "unset env name fails before connecting" grep -q "NOT_SET' is listed in envs but not set" <<<"$out"

SSH_DEPLOY_ENVS="BAD-NAME" run 'echo connected'
check "invalid env name is rejected" grep -q "invalid env name 'BAD-NAME'" <<<"$out"

SSH_DEPLOY_HOST_KEY="" run 'echo connected'
check "empty input is rejected" grep -q "SSH_DEPLOY_HOST_KEY is empty" <<<"$out"

if ((failures)); then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
