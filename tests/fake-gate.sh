#!/usr/bin/env bash
# Stands in for the host's deploy gate in the sshd test container. It echoes
# what arrived and exits with the payload's EXIT_CODE, so tests can assert both.
payload="$(cat)"
printf 'CMD=%s\nPAYLOAD=%s\n' "$SSH_ORIGINAL_COMMAND" "$payload"
# The action-wiring step in test.yml deploys to "wiring" and must deliver GREETING.
if [[ "$SSH_ORIGINAL_COMMAND" == "wiring "* && "$payload" != *'"GREETING":"hello from the runner"'* ]]; then
  exit 9
fi
code="$(sed -n 's/.*"EXIT_CODE":"\([0-9]*\)".*/\1/p' <<<"$payload")"
exit "${code:-0}"
