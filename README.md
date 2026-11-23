# ci-actions

Shared GitHub Actions code for the Minds-Models org.

## `ssh-deploy` (composite action)

Asks the deploy gate on a remote host to deploy one commit. The host binds the key to a forced command (`command="… <repo>"` in `authorized_keys`), so the key cannot run anything else. The gate decides what a deploy does; this action only names the environment and the commit, and hands over the variables the gate expects.

```yaml
- name: Deploy
  uses: Minds-Models/ci-actions/ssh-deploy@<sha> # v2.0.0
  env:
    APP_PASSWORD: ${{ secrets.APP_PASSWORD }}
  with:
    host: ${{ secrets.SSH_HOST }}
    user: ${{ secrets.SSH_USER }}
    key: ${{ secrets.DEPLOY_GATE_KEY }}
    host-key: ${{ vars.SSH_HOST_KEY }}
    environment: production
    sha: ${{ github.sha }}
    envs: APP_PASSWORD
```

| Input | Required | Meaning |
|---|---|---|
| `host` | yes | Remote hostname or IP |
| `port` | no (`22`) | Remote SSH port |
| `user` | yes | Remote user |
| `key` | yes | Private key, bound on the host to the gate |
| `host-key` | yes | Host public key `"<type> <base64>"`, e.g. the first two fields of `/etc/ssh/ssh_host_ed25519_key.pub`. A mismatch fails the step. |
| `environment` | yes | Environment name, `^[a-z][a-z0-9-]*$` |
| `sha` | yes | Full 40-character lowercase commit sha |
| `envs` | no | Names of step `env:` variables sent to the gate, separated by commas or newlines. `SSH_DEPLOY_*` and `_sd_*` names are refused. |

- The SSH command is `"<environment> <sha>"`; the host reads it from `SSH_ORIGINAL_COMMAND`.
- The variables travel as one JSON object on stdin, built by `jq` from the environment, so no value appears in argv on either host. `GITHUB_ACTOR`, `GITHUB_RUN_ID` and `GITHUB_REPOSITORY` are added for the gate's audit log.
- The step fails with the gate's exit code. A name in `envs` that is not set on the step fails before connecting, as do a `host`, `user`, `port`, `environment` or `sha` that is not a plain value, and a `host-key` that is not one `<type> <base64>` line.
- ssh runs with `-F /dev/null`: no ssh config on the runner can change the host key, proxy or identity.
- Set `timeout-minutes` on the calling job. The action sets only a 30 s connect timeout.

## `zizmor` (reusable workflow)

Audits the calling repo's workflows, actions and Dependabot config with [zizmor](https://docs.zizmor.sh/), online audits included. It pins the zizmor version for the whole org. Caller:

```yaml
name: zizmor

on:
  pull_request:
    paths: [".github/**"]
  push:
    branches: [main]
    paths: [".github/**"]
  workflow_dispatch:

permissions: {}

jobs:
  zizmor:
    permissions:
      contents: read
    uses: Minds-Models/ci-actions/.github/workflows/zizmor.yml@<sha> # v1.0.0
```

## Releasing

1. Merge to `main` through a PR. `test` and `zizmor` must be green.
2. Tag `vX.Y.Z` on the merge commit and publish a GitHub release. Dependabot in the caller repos proposes the new SHA when a release appears.

## Tests

```bash
keys=$(mktemp -d)
tests/sshd-up.sh "$keys"          # throwaway sshd container on 127.0.0.1:2222 (needs Docker)
tests/test-ssh-deploy.sh "$keys"  # needs jq
docker rm -f ssh-deploy-test
```
