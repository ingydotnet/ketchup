---
name: ketchup
description:
  Generate today's daily catch-up report on activity across the
  configured set of projects.
  Writes and commits the report as `report/YYYYMMDD.md`.
  Pushes only when running under GitHub Actions.
---

# Ketchup Report Generator

You are generating today's "ketchup" report.
It is a daily catch-up on activity across a configured set of
open source projects.
The output is a markdown file with checkbox-formatted to-do items
that the reader can tick off directly on GitHub.

## Step 1: Read configuration

Read `ketchup.yaml` from the repo root.
The top-level keys are:

- `default model`: the model name subagents should use unless
  overridden per entry.
- `lookback days`: how many days back to scan a project the FIRST
  time it is encountered (no prior report mentions it).
  Once a project is known (its URL appears in any earlier report),
  it switches to the steady-state window described below.
- `dedup days`: two purposes.
  First, the rolling window of prior reports used to dedup items
  already reported.
  Second, the steady-state scan window used for any project that
  is already known.
- `project repos`: a list of project repositories to monitor.
  This is the only interest category supported today; more
  categories may be added later as additional top-level keys.

Each entry in `project repos` is either:

- A scalar URL string pointing to the project (e.g.
  `https://github.com/owner/repo`).
- A mapping with the following optional keys (all four letters
  except for `model`):
  - `repo`: the project URL (required when using mapping form).
  - `note`: free-form context or formatting guidance for the
    subagent.
    Treat this as a soft hint, not a filter.
  - `skip`: a constraint describing items the subagent should
    drop from its output.
    Treat this as a hard filter.
  - `model`: per-repo model override.

Repo URLs are not assumed to be on GitHub.
The host is part of the identifier so that other forges (GitLab,
Codeberg, Sourcehut, etc.) can be supported.
GitHub is the well-tested path today; see Step 3 for how to
handle other hosts.

## Step 2: Read prior reports for dedup and known-set

List the files matching `report/*.md`.
This step produces two pieces of state.

**Known-set.**
Scan every file in `report/*.md` (no date filter) and collect
every project URL that appears anywhere in any of them, whether
in a `## {project}` section's item links or in the
`## No updates` list.
This is the set of "known" projects.
A project not in this set will be treated as a first encounter
and scanned over the full `lookback days` window in Step 3.

**Dedup map.**
For reports whose date (parsed from the filename) falls within
the last `dedup days` days, extract the items previously
reported, keyed by `{repo}#{number}` together with their
`updated_at` timestamps.
This map is passed to each subagent in Step 3 so it can skip
items that have not changed.

If `report/` does not exist yet, both the known-set and the
dedup map are empty.
That is fine on a first run; every project will be treated as
new.

## Step 3: Fetch activity per repo (in parallel)

The project list is expected to churn: entries get added,
removed, and have their `note` / `skip` constraints changed
between runs.
The skill must stay correct as the set changes.
Removed projects simply stop appearing; previously removed
projects that get re-added stay "known" via the known-set, so
they do not trigger a fresh cold-start scan.

For each entry in `project repos`, spawn a subagent using the
`Agent` tool with `subagent_type: general-purpose` and
`run_in_background: true`.
Compute the effective scan window for each entry first:
if the entry's repo URL is in the known-set from Step 2, use
`dedup days`; otherwise use `lookback days`.
Brief each subagent with:

- The repo URL.
- The effective scan window, expressed as an absolute ISO date.
- The entry's `note` value, if any.
- The entry's `skip` constraint, if any.
- The list of items already reported in the dedup window, with
  their last seen `updated_at`, so unchanged items can be
  skipped.
- The model to use (the entry's `model` if set, otherwise
  `default model`).

The subagent dispatches on the URL host:

- `github.com`: use the `gh` CLI.
  Useful endpoints include:

  ```
  gh api 'repos/{owner}/{repo}/issues?state=open&sort=updated&direction=desc&since=<ISO>&per_page=100'
  gh api 'repos/{owner}/{repo}/pulls?state=all&sort=updated&direction=desc&per_page=50'
  gh api 'repos/{owner}/{repo}/discussions?per_page=30' || true
  gh api 'repos/{owner}/{repo}/releases?per_page=5'
  ```

  The issues endpoint includes PRs.
  Filter them out with `select(.pull_request == null)` if you
  pipe through `jq`.

- Other hosts: use the forge's public REST API or feeds.
  Aim to produce the same structured output as the GitHub
  branch.
  Examples: GitLab's `/api/v4/projects/...`, Codeberg's Gitea
  API at `/api/v1/repos/...`, Sourcehut's GraphQL or RSS.

- Unsupported host: return a single placeholder item that says
  the host is not yet supported, with the project URL.
  This surfaces the gap in the report instead of failing
  silently.

Each subagent should return a structured list of activity items.
Each item should include: type (issue, PR, discussion, release),
number or identifier, title, URL, `updated_at`, and a brief
context note.
A subagent that finds no qualifying items returns an empty
list; that signals the project belongs in the No updates
section in Step 4.

## Step 4: Aggregate, partition, and order

Collect the results from every subagent.

**Partition.**
Split the per-project results into two buckets:

- **has-updates**: the subagent returned at least one item that
  survived its own filtering.
- **no-updates**: the subagent returned an empty list (the
  project is quiet for this window, or every candidate was
  filtered out by `skip` / dedup).

Every entry in `project repos` must end up in exactly one
bucket.

**Dynamic ordering** (has-updates only).
Order the repo sections in the report by significance of
activity, with the most important first.
Significance is a judgment call: weight security issues, popular
or stalled PRs, breaking changes, and high-impact releases above
quiet maintenance.
The no-updates bucket is rendered as a single flat list at the
bottom and does not need internal ordering.

**Selection.**
Do not include everything.
Filter to the items that actually matter, especially on early
runs where `lookback days` is large.
Quality beats completeness.
A project whose only candidate items get dropped during
selection moves into the no-updates bucket.

## Step 5: Format and write the report

Write the report to `report/YYYYMMDD.md` using today's UTC date.
Create the `report/` directory if it does not exist.

Use this structure:

```markdown
# Ketchup Report - YYYY-MM-DD

## {project}

- [ ] [#NNN Title](https://example.com/owner/repo/issues/NNN)
  One short paragraph explaining what this is and why it matters.
  (updated: YYYY-MM-DDTHH:MM:SSZ)

## No updates

- https://example.com/owner/project-a
- https://example.com/owner/project-b
```

Rules:

- Checkbox syntax (`- [ ]`) so items render as interactive
  to-dos on GitHub.
- Every item entry must have at least one URL pointing to the
  item.
- Each item gets a short summary explaining the context.
- Always include `(updated: <ISO>)` so future runs can dedup
  precisely.
- For the section heading, use the project's short name (last
  path segment of the URL) rather than the full URL.
- The `## No updates` section is always present, even if empty.
  Each project in the no-updates bucket becomes exactly one
  bullet line containing only the full project URL.
  No display name, no parenthetical, no date.
  Future runs grep these URLs to build the known-set, so the
  format must stay stable.

## Step 6: Dedup rules

- Skip an item already reported within `dedup days` if its
  `updated_at` has not changed.
- Re-include an item whose `updated_at` has advanced since the
  last report.
- A project with no qualifying items (everything filtered or
  deduped out) goes into the No updates section instead of
  getting its own `## {project}` section.

## Step 7: Commit and (conditionally) push

Once the report file has been written:

```sh
git add report/<YYYYMMDD>.md
git commit -m "Ketchup report YYYY-MM-DD"
```

Then check the environment.
If `$GITHUB_ACTIONS` is non-empty (i.e. running inside a GitHub
Actions workflow), also run `git push`.
Otherwise skip the push so local runs do not pollute the remote.

## Step 8: Verify

Before finishing, confirm:

- The report file exists at `report/YYYYMMDD.md`.
- Every entry has at least one URL.
- Every checkbox uses `- [ ]` syntax.
- Repo sections are ordered by significance, not alphabetically.
- Every project in `ketchup.yaml` appears in the report exactly
  once, either as a `## {project}` section or as a bullet under
  `## No updates`.
- A commit was created with the expected message.
- The push happened only when `$GITHUB_ACTIONS` was set.
