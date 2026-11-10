# ci-actions

Shared GitHub Actions code for the org: the `ssh-deploy` composite action and the reusable `zizmor` workflow. Interfaces and the release flow are in `README.md`.

- **Branch:** `main` only; changes through PRs. Callers pin a release commit by full SHA with a `# vX.Y.Z` comment, so a change reaches them only after a tag and a Dependabot bump.
- **Tests:** `tests/sshd-up.sh` + `tests/test-ssh-deploy.sh` (needs Docker). CI runs them in `test.yml`, plus the action itself against the same sshd.
- **Interface changes** to `ssh-deploy` inputs or the `zizmor` workflow are cross-repo contracts (`workspace:agent_docs/contracts.md#ci-actions`). Additive changes only within a major version.
- **Workflow rules** (pinning, zizmor-clean) are in `workspace:agent_docs/git-and-deploy.md`.
