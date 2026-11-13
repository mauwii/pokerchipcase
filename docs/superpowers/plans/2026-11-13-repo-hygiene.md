# Repo Hygiene Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** License name, issue forms, `.editorconfig` and a pre-commit setup that CI enforces.

**Architecture:** Config files only, plus one CI job `lint` on ubuntu that runs pre-commit with pipx. The hook config lands in one commit; fixes for what the hooks report land in a second.

**Tech Stack:** GitHub issue forms, EditorConfig, pre-commit 4.6.2, markdownlint-cli2, typos, actionlint, zizmor, shellcheck, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-11-13-repo-hygiene.md`

## Global Constraints

- No Swift code changes.
- Every action and hook `rev` is pinned by commit SHA with a version comment.
- Code, comments, docs and commits in English; Conventional Commits.
- The `test` and `App build` jobs in `ci.yml` stay unchanged.

## Review Focus

- A zizmor or actionlint finding in the existing `ci.yml` or `rerun.yml`: fix it in Task 3, or add an inline ignore with a reason only if the fix would change CI behavior.
- `end-of-file-fixer` or `trailing-whitespace` touching a binary: the PNGs in `docs/images/` must stay byte-identical (`git diff --stat docs/images` is empty).
- typos flagging a real identifier (e.g. a poker term or a Swift API name): add it to a `_typos.toml` `extend-words` entry instead of renaming code.
- markdownlint on `docs/superpowers/` history files: fix them like other docs; they are not excluded.
- A Dependabot PR for the `pre-commit` ecosystem must keep the `# frozen:` comment format; nothing to test here, the config just has to use that format.

---

### Task 1: License name and issue forms

**Files:**

- Modify: `LICENSE:3`
- Create: `.github/ISSUE_TEMPLATE/bug_report.yml`
- Create: `.github/ISSUE_TEMPLATE/feature_request.yml`

**Interfaces:**

- Produces: nothing later tasks use.

- [ ] **Step 1: LICENSE line 3 becomes exactly** `Copyright (c) 2026 mauwii (Matthias Wild)`.

- [ ] **Step 2: Write `bug_report.yml`**

Top level: `name: Bug report`, `description: Something in the app or a library does not work as expected`, `labels: [bug]`. Body fields, in this order:

| `id` | type | label | required | notes |
|---|---|---|---|---|
| `description` | textarea | Description | yes | description: "What happened, and what did you expect?" |
| `steps` | textarea | Steps to reproduce | no | |
| `role` | dropdown | Role | yes | options: `Host`, `Guest`, `Offline (no network)` |
| `devices-count` | input | Number of devices at the table | no | |
| `devices` | textarea | Devices | yes | description: "Model and iOS version of every device involved, one per line." |
| `version` | input | App version or commit | no | description: "The version from Settings, or the commit SHA you built." |

- [ ] **Step 3: Write `feature_request.yml`**

`name: Feature request`, `description: An idea for the app or the libraries`, `labels: [enhancement]`. Textareas `problem` (label Problem, required, description "What is missing or hard today?"), `proposal` (label Proposal, required), `alternatives` (label Alternatives, optional).

- [ ] **Step 4: Verify the YAML parses**

Run: `for f in .github/ISSUE_TEMPLATE/*.yml; do ruby -ryaml -e 'YAML.load_file(ARGV[0])' "$f" && echo "ok $f"; done`
Expected: `ok` for both files.

- [ ] **Step 5: Commit**

```bash
git add LICENSE .github/ISSUE_TEMPLATE
git commit -m "chore: add issue forms, add real name to the license"
```

### Task 2: EditorConfig, pre-commit config and CI job

**Files:**

- Create: `.editorconfig`, `.pre-commit-config.yaml`, `.markdownlint.yaml`
- Modify: `.github/dependabot.yml`, `.github/workflows/ci.yml`, `AGENTS.md` (Commands), `CONTRIBUTING.md` (Checks)

**Interfaces:**

- Produces: the hook set Task 3 runs; the CI job id `lint`.

- [ ] **Step 1: `.editorconfig`**

```ini
# Ignore .editorconfig files above this directory
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
indent_style = space
indent_size = 4
trim_trailing_whitespace = true

[*.{yml,yaml}]
indent_size = 2
```

- [ ] **Step 2: `.pre-commit-config.yaml`** with these repos and revs (already used and current in another project of the maintainer):

```yaml
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: 3e8a8703264a2f4a69428a0aa4dcb512790b2c8c  # frozen: v6.0.0
    hooks:
      - id: check-added-large-files
      - id: check-merge-conflict
      - id: check-yaml
      - id: end-of-file-fixer
      - id: mixed-line-ending
        args: [--fix=lf]
      - id: trailing-whitespace
  - repo: https://github.com/shellcheck-py/shellcheck-py
    rev: 745eface02aef23e168a8afb6b5737818efbea95  # frozen: v0.11.0.1
    hooks:
      - id: shellcheck
  - repo: https://github.com/DavidAnson/markdownlint-cli2
    rev: 341e2a331ba578029e66c2e01183e7a6b5ca9ab4  # frozen: v0.24.0
    hooks:
      - id: markdownlint-cli2
  - repo: https://github.com/crate-ci/typos
    rev: v1.51.1
    hooks:
      - id: typos
  - repo: https://github.com/rhysd/actionlint
    rev: 914e7df21a07ef503a81201c76d2b11c789d3fca  # frozen: v1.7.12
    hooks:
      - id: actionlint
  - repo: https://github.com/zizmorcore/zizmor-pre-commit
    rev: c92afdf2c6ca336aaa8f39e2bd8d48f62dbd8e1f  # frozen: v1.31.1
    hooks:
      - id: zizmor
```

Keep a comment above the typos entry: it uses a tag because Dependabot matched the `frozen` comment against the tags of the other crates in that repo.

- [ ] **Step 3: `.markdownlint.yaml`**

```yaml
# The docs are not wrapped.
MD013: false
# The tables use compact |---| separator rows.
MD060: false
```

- [ ] **Step 4: `.github/dependabot.yml`** gets a second entry after `github-actions`: `package-ecosystem: pre-commit`, `directory: /`, `schedule.interval: weekly`, `cooldown.default-days: 7`, `groups.pre-commit.patterns: ["*"]`.

- [ ] **Step 5: CI job `lint`** in `.github/workflows/ci.yml`, first in `jobs`:

```yaml
  lint:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      # the hook environments, pinned to commit SHAs in the config
      - uses: actions/cache@<SHA of the newest actions/cache release at least two weeks old> # v<x.y.z>
        with:
          path: ~/.cache/pre-commit
          key: pre-commit-${{ runner.os }}-${{ hashFiles('.pre-commit-config.yaml') }}
      - run: pipx run pre-commit==4.6.2 run --all-files --show-diff-on-failure
```

Look up the `actions/cache` SHA with `gh api repos/actions/cache/releases --jq '.[] | [.tag_name, .published_at] | @tsv'` and `gh api repos/actions/cache/commits/<tag> --jq .sha`.

- [ ] **Step 6: Docs**

- `AGENTS.md`, Commands: the intro becomes "Run these from the repo root before opening a PR; CI runs the same three." Add a bullet: "Lint (`brew install pre-commit`): `pre-commit run --all-files`. CI runs it in the `lint` job."
- `CONTRIBUTING.md`, Checks: same change of "two" to "three", and add `pre-commit run --all-files` to the code block. After it: "Install the hooks once with `brew install pre-commit && pre-commit install` to run them on every commit. That is optional; CI runs them anyway."

- [ ] **Step 7: Verify the config loads**

Run: `pre-commit validate-config .pre-commit-config.yaml && pre-commit run check-yaml --all-files`
Expected: `check yaml...Passed`. Other hooks may still fail; Task 3 fixes them.

- [ ] **Step 8: Commit**

```bash
git add .editorconfig .pre-commit-config.yaml .markdownlint.yaml .github AGENTS.md CONTRIBUTING.md
git commit -m "ci: add pre-commit hooks, editorconfig and a lint job"
```

### Task 3: Fix what the hooks report

**Files:**

- Modify: whatever `pre-commit run --all-files` reports. Possibly create `_typos.toml`.

**Interfaces:**

- Consumes: the hook set from Task 2.

- [ ] **Step 1: Run all hooks**

Run: `pre-commit run --all-files`
Note every failing hook and its findings.

- [ ] **Step 2: Fix the findings**

- Auto-fixers (end-of-file, whitespace, line endings) already changed the files; keep those changes.
- markdownlint: fix the Markdown. Do not turn off more rules without a reason written as a comment in `.markdownlint.yaml`.
- typos: fix real typos; for a correct word it flags, add `_typos.toml` with `[default.extend-words]`.
- actionlint and zizmor: fix the workflow. If a fix would change CI behavior, add an inline `# zizmor: ignore[<rule>]` with the reason instead.
- shellcheck: fix `device.sh`.

- [ ] **Step 3: Verify**

Run: `pre-commit run --all-files && git diff --stat docs/images && swift test 2>&1 | tail -1`
Expected: every hook `Passed`, no change under `docs/images`, test summary passes.

- [ ] **Step 4: Commit**

```bash
# -u, not -A: .claude/worktrees/ is untracked and stays out
git add -u && git add _typos.toml 2>/dev/null
git commit -m "style: fix pre-commit findings"
```

- [ ] **Step 5: Push and open the PR**

The PR body links the spec and this plan. CI: `lint`, `test` and `App build` green.
