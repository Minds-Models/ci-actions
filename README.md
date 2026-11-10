# ci-actions

Shared GitHub Actions code for the Minds-Models org.

## `ssh-deploy` (composite action)

Runs a bash script on a remote host over SSH. Server deploys use it to run their remote deploy script on the VPS.

```yaml
- name: Deploy
  uses: Minds-Models/ci-actions/ssh-deploy@<sha> # v1.0.0
  env:
    APP_PASSWORD: ${{ secrets.APP_PASSWORD }}
    DEPLOY_SHA: ${{ github.sha }}
  with:
    host: ${{ secrets.SSH_HOST }}
    user: ${{ secrets.SSH_USER }}
    key: ${{ secrets.SSH_PRIVATE_KEY }}
    host-key: ${{ vars.SSH_HOST_KEY }}
    envs: APP_PASSWORD,DEPLOY_SHA
    script: |
      cd /srv/app
      git checkout "$DEPLOY_SHA"
```

| Input | Required | Meaning |
|---|---|---|
| `host` | yes | Remote hostname or IP |
| `port` | no (`22`) | Remote SSH port |
| `user` | yes | Remote user |
| `key` | yes | Private key |
| `host-key` | yes | Host public key `"<type> <base64>"`, e.g. the first two fields of `/etc/ssh/ssh_host_ed25519_key.pub`. A mismatch fails the step. |
| `envs` | no | Comma-separated names of step `env:` variables exported into the remote script |
| `script` | yes | Bash script; runs under `set -e` with stdin from `/dev/null` |

- The script runs as `bash -se` on the remote host. Values listed in `envs` are sent inside the script on stdin, so they never appear in a process list.
- Write `"$VAR"`, never `${{ … }}`, inside `script`. Expressions there are template injection.
- A name in `envs` that is not set on the step fails before connecting.

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
tests/test-ssh-deploy.sh "$keys"
docker rm -f ssh-deploy-test
```
