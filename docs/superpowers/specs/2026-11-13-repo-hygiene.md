# Repo hygiene

License name, issue templates, `.editorconfig` and pre-commit. No Swift code changes.

## LICENSE

The copyright line becomes `Copyright (c) 2026 mauwii (Matthias Wild)`.

## Issue templates

Two issue forms in `.github/ISSUE_TEMPLATE/`. No `config.yml`, so blank issues stay allowed. Both labels exist already.

`bug_report.yml`, label `bug`:

| Field | Type | Required |
|---|---|---|
| Description: what happened, what was expected | textarea | yes |
| Steps to reproduce | textarea | no |
| Role: host, guest, or offline (no network) | dropdown | yes |
| Number of devices at the table | input | no |
| Devices: model and iOS version of every device involved | textarea | yes |
| App version or commit SHA | input | no |

`feature_request.yml`, label `enhancement`: Problem (required), Proposal (required), Alternatives (optional), all textareas.

## .editorconfig

- `[*]`: `charset = utf-8`, `end_of_line = lf`, `insert_final_newline = true`, `indent_style = space`, `indent_size = 4`, `trim_trailing_whitespace = true`. The Swift code is indented with 4 spaces today.
- `[*.{yml,yaml}]`: `indent_size = 2`.

## pre-commit

`.pre-commit-config.yaml` with language-agnostic hooks only. No Swift formatter or linter; one can be added later as a local hook.

- `pre-commit/pre-commit-hooks`: `check-added-large-files`, `check-merge-conflict`, `check-yaml`, `end-of-file-fixer`, `mixed-line-ending` with `--fix=lf`, `trailing-whitespace`.
- `DavidAnson/markdownlint-cli2`
- `crate-ci/typos`
- `rhysd/actionlint`
- `zizmorcore/zizmor-pre-commit`
- `shellcheck-py/shellcheck-py`, for `device.sh`.

Every `rev` is a commit SHA with a `# frozen: <tag>` comment, the format `pre-commit autoupdate --freeze` writes and Dependabot keeps up to date. Use the newest release that is at least two weeks old.

`.markdownlint.yaml` turns off `MD013` (line length). The docs are not wrapped, and 40 lines are longer than 120 characters today; rewrapping them would be noise. It also turns off `MD060` (table column style): the tables in the repo use `|---|` separator rows, which the rule flags.

`.github/dependabot.yml` gets a second ecosystem `pre-commit`: directory `/`, weekly, `cooldown.default-days: 7`, all hooks in one group `pre-commit`.

### CI

A new job `lint` in `.github/workflows/ci.yml` on `ubuntu-latest`, timeout 10 minutes:

1. `actions/checkout`, pinned like the other jobs, `persist-credentials: false`.
2. `actions/cache`, pinned by SHA, on `~/.cache/pre-commit`, key `pre-commit-${{ runner.os }}-${{ hashFiles('.pre-commit-config.yaml') }}`.
3. `pipx run pre-commit==<version> run --all-files --show-diff-on-failure`. pipx is preinstalled on the runner, so no setup step and no new dependency file.

The `test` and `app` jobs stay unchanged.

### First run

The hook configuration lands in one commit. Running `pre-commit run --all-files` and fixing what it reports, automatically or by hand, is a separate commit, so the config diff stays readable. zizmor or actionlint findings in the existing workflows are fixed in that commit, not suppressed, unless a fix would change CI behavior; such a finding gets an inline ignore comment with the reason.

## Docs

- `AGENTS.md`, Commands: a third command `pre-commit run --all-files`, with a note that CI runs it in the `lint` job.
- `CONTRIBUTING.md`: optional local setup `brew install pre-commit && pre-commit install`.

## Verification

- `pre-commit run --all-files` passes locally.
- CI on the PR: `lint`, `test` and `app` are green.
- The issue forms are valid YAML (`check-yaml`). GitHub only shows forms from the default branch, so after the merge, open the "New issue" page and check that both forms appear with their fields.
