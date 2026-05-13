# ketchup

Daily catch-up reports on activity across a configured set of
open source projects.

A headless [Claude Code](https://github.com/anthropics/claude-code)
agent reads a list of projects from `ketchup.yaml`, fetches recent
issues, pull requests, discussions, and releases for each one,
and writes a markdown report as `report/YYYYMMDD.md`.
Each item in the report is a GitHub-style checkbox so the report
itself doubles as a to-do list you can tick through directly on
the GitHub web UI.

You can run ketchup locally on your own machine, or wire it up to
a GitHub Action that posts a fresh report to your repo every day.

## What it tracks

Project URLs in `ketchup.yaml` can point at any forge.
Today the well-tested path is GitHub: the skill uses the `gh`
CLI to fetch issues, PRs, discussions, and releases.
For non-GitHub URLs (GitLab, Codeberg, Sourcehut, etc.) the
skill falls back to that forge's public API and best-effort
formats the same kinds of items.
If a host is not yet supported, the project will still appear in
the report as a placeholder so the gap is visible.

## Configure

Edit `ketchup.yaml` at the repo root.
Minimal example:

```yaml
default model: sonnet
lookback days: 30
dedup days: 7

project repos:
- https://github.com/owner/project-a
- https://github.com/owner/project-b
- repo: https://github.com/owner/project-c
  note: focus on protocol changes and breaking API edits
  skip: items unrelated to the public API
```

Top-level keys:

- `default model`: the Claude model name used by the per-repo
  subagents.
- `lookback days`: how many days back to scan a project the
  first time it shows up.
  Once a project has appeared in any prior report, it is
  considered "known" and the daily steady-state scan reuses
  `dedup days` instead.
  Start `lookback days` large (60-90) for cold runs; the
  first-encounter cost only applies to genuinely new entries.
- `dedup days`: two roles.
  It is the rolling window used to suppress items already
  reported recently, and it is also the steady-state scan
  window for any project that is already known.
- `project repos`: the list of projects to monitor.
  This is the only interest category supported today; more may
  be added later as additional top-level keys.

`ketchup.yaml` is intended to be edited often.
Adding projects, removing projects, and adjusting `note` /
`skip` constraints is the normal operating mode, not an
exception.
Every project listed appears in each daily report, either with
fresh items in its own section or as a URL line under a final
`## No updates` section.
That No updates list is also how the skill knows on later runs
which projects are "known" and can skip the cold-start scan.

A `project repos` entry is either a scalar URL string or a
mapping with these optional keys:

- `repo`: the project URL (required in mapping form).
- `note`: free-form context or formatting guidance for the
  subagent.
  Soft hint, not a filter.
- `skip`: a constraint describing items to drop from the
  report.
  Hard filter.
- `model`: override `default model` for this entry only.

## Run locally

```sh
make token        # one-time: gh auth login, save token locally
make ketchup      # generate today's report
```

`make token` runs `gh auth login` and writes the resulting token
to `./github-token` (gitignored).
`make ketchup` runs the headless Claude pipeline.
When it finishes, a fresh `report/YYYYMMDD.md` is written and
committed to the current branch.
Local runs **do not push** to the remote; you can review the
commit and push it yourself if you want, or just leave it
local.

## Run as a GitHub Action

The workflow at `.github/workflows/ketchup.yaml` runs the same
pipeline on a cron schedule, commits the report, and pushes it
back to the repo.

Required secrets on the repo:

- `CLAUDE_CREDENTIALS`: the JSON contents of your local Claude
  credentials file (the one Claude Code maintains under
  `$CLAUDE_CONFIG_DIR`, defaulting to `~/.claude/.credentials.json`).
  The Action writes this JSON to the runner each time and points
  Claude at it, so the run authenticates against your Claude Max
  subscription instead of metered API usage.
- `KETCHUP_TOKEN`: a fine-grained GitHub PAT with read access to
  every repo listed in `ketchup.yaml` and write access to the
  `contents` of this repo (so the workflow can push the report).

`make publish-secrets` pushes both `CLAUDE_CREDENTIALS` and
`KETCHUP_TOKEN` from local files in one shot.
If a report ever appears with a top-of-file banner about
rotated credentials, log in to Claude locally and re-run
`make publish-secrets` to refresh the stored secret.

You can trigger the workflow manually from the Actions tab via
`workflow_dispatch`, or wait for the next scheduled run.

## Reading the report

Each daily report is a markdown file with one section per
project that had activity, plus a `## No updates` section
listing the URLs of quiet projects.
Every active item is a GitHub-style task list checkbox, so
the report doubles as an interactive to-do list when viewed
in the GitHub web UI.

**Ticking an item** marks it as handled.
Once an item is ticked in its most recent appearance in any
prior report, future ketchup runs treat it as suppressed and
do not surface it again, even if upstream activity continues.
If you change your mind, un-tick the box in the latest report
that still mentions the item; the next run picks the change
up and may re-include the item.

**Appearance counter.**
Each item shows `(updated: ISO, appearance #N)` on its
metadata line, where N is how many reports have contained
this item so far.
A first-time item is `#1`; an item that has been nagging for
weeks accumulates higher numbers.

**Re-surfacing quiet-but-open items.**
If you neither tick nor close an item, ketchup brings it back
into a future report once its last appearance is older than
`dedup days`.
The appearance counter increments each time, so persistent
items become visually loud over time.
Tick the box (or have the underlying issue closed upstream)
to stop the cycle.

**Navigation.**
Every report has `← prev | next →` links at the top and at
the bottom pointing to neighboring report files.
The most recent report's `next →` placeholder is empty until
the following day's run fills it in.

## Repo layout

- `ketchup.yaml`: the config you edit.
- `.claude/skills/ketchup/SKILL.md`: the prompt that drives
  report generation.
- `.github/workflows/ketchup.yaml`: the scheduled GitHub Action.
- `Makefile`: uses [Makes](https://github.com/makeplus/makes) to
  install dependencies and run the pipeline.
- `report/`: where the daily report files live.
  Created on first run.

## Copyright and License

Copyright (c) 2026 Ingy döt Net.

This project is released under the MIT License.
See the [License](License) file for the full text.
