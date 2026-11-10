# ci-actions

Shared GitHub Actions code for the org: the `ssh-deploy` composite action and the reusable `zizmor` workflow. Interfaces and the release flow are in `README.md`.

- **Public repo, no secrets.** Callers' `GITHUB_TOKEN` cannot read a private repo, and zizmor's online audits (`impostor-commit`, `known-vulnerable-actions`) look up every pinned action through the API. Keep hosts, paths and credentials out of this repo.
- **Branch:** `main` only; changes through PRs. Callers pin a release commit by full SHA with a `# vX.Y.Z` comment, so a change reaches them only after a tag and a Dependabot bump.
- **Tests:** `tests/sshd-up.sh` + `tests/test-ssh-deploy.sh`, and `tests/test-remote-lib.sh` (all need Docker). CI runs them in `test.yml`, plus the action itself against the same sshd. The ssh-config test runs only in CI, because ssh reads the config from the passwd home.
- **zizmor version and hashes** live only in the `Install zizmor` step of `.github/workflows/zizmor.yml`. A bump updates every wheel hash there; `workspace:scripts/zizmor-all.sh` reads the same block.
- **Interface changes** to `ssh-deploy` inputs or the `zizmor` workflow are cross-repo contracts (`workspace:agent_docs/contracts.md#ci-actions`). Additive changes only within a major version.
- **Workflow rules** (pinning, zizmor-clean) are in `workspace:agent_docs/git-and-deploy.md`.
