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

## Step 2: Read prior reports

List the files matching `report/*.md`, sorted by filename
(which is YYYYMMDD, so this is chronological).
This step builds five pieces of state from those files.

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

**Suppress-set.**
Walk `report/*.md` from newest to oldest.
For each item URL, record the tick state of its most recent
occurrence: a line starting with `- [x]` means the user has
marked the item as done / ignored, so the URL goes into the
suppress-set; a line starting with `- [ ]` means it is not
suppressed.
Only the latest mention wins, so the user can un-suppress an
item by un-ticking the checkbox in the most recent prior
report that mentions it.

**Appearance count map.**
For each item URL, count how many distinct `report/*.md` files
contain it.
The new report being written will add one more, so the
appearance number shown for an item in today's report is
`prior count + 1`.

**Outstanding map.**
For each URL that has ever been reported and is NOT in the
suppress-set, record the date (from the report filename) of
its most recent appearance.
Restrict to URLs whose project is still listed in
`ketchup.yaml`; outstanding entries for removed projects are
dropped.
This map drives the re-surface logic in Step 3.

If `report/` does not exist yet, all five structures are
empty.
That is fine on a first run; every project will be treated as
new and no items will be suppressed or re-surfaced.

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
- The suppress-set URLs that belong to this project.
  Any candidate item whose URL appears in this set is a hard
  drop: the subagent must not return it under any
  circumstance.
- The re-surface candidate URLs for this project: outstanding
  URLs whose last appearance was more than `dedup days` ago.
  For each, the subagent fetches the item's current state via
  the forge API and includes it in its return list if it is
  still open.
  Closed items are dropped silently.
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
Re-surface items returned from the candidate list look just
like fresh items in the return shape; the parent agent
distinguishes them by URL membership in the outstanding map
when formatting the appearance counter in Step 5.

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

[← YYYY-MM-DD](20260511.md) | next →

## {project}

- [ ] [#NNN Title](https://example.com/owner/repo/issues/NNN)
  One short paragraph explaining what this is and why it matters.
  (updated: YYYY-MM-DDTHH:MM:SSZ, appearance #N)

## No updates

- https://example.com/owner/project-a
- https://example.com/owner/project-b

[← YYYY-MM-DD](20260511.md) | next →
```

Rules:

- Checkbox syntax (`- [ ]`) so items render as interactive
  to-dos on GitHub.
- Every item entry must have at least one URL pointing to the
  item.
- Each item gets a short summary explaining the context.
- Always include `(updated: <ISO>, appearance #N)`, where N is
  `prior appearance count + 1`.
  The `updated` ISO lets future runs dedup precisely, and N
  shows the reader how often this item has surfaced before.
- For the section heading, use the project's short name (last
  path segment of the URL) rather than the full URL.
- The `## No updates` section is always present, even if empty.
  Each project in the no-updates bucket becomes exactly one
  bullet line containing only the full project URL.
  No display name, no parenthetical, no date.
  Future runs grep these URLs to build the known-set, so the
  format must stay stable.

**Navigation links.**
A single line just below the H1 and again just above EOF
carries previous / next pointers:

- `[← YYYY-MM-DD](20260511.md) | next →` when a prior report
  exists.
  Use the prior report's date as the link label.
- `← prev | next →` (both halves placeholder) when no prior
  report exists (first-ever run).
- The `next →` half is rendered as the literal text
  `next →` (no link target) on the newly written report.
  The next day's run back-edits it to a real link.

**Back-edit the prior report.**
After writing today's report, if any prior report exists in
`report/`, edit that file (the chronologically previous one) to
turn its `next →` placeholder into a real link to today's
filename: `[YYYY-MM-DD →](20260512.md)`.
Update both the top and the bottom occurrences.
If the prior report predates this feature and has no nav line,
insert one in both positions; leave its `← prev` half
pointing to whatever came before it, or use a `← prev`
placeholder if it was the first report.

## Step 6: Filter and dedup rules

Applied in this order:

1. **Suppress-set check.**
   Drop any candidate item whose URL is in the suppress-set
   (i.e. its most recent occurrence in any prior report was
   `- [x]`).
   This filter wins over everything else and applies to fresh
   candidates and re-surface candidates alike.
2. **Re-surface check.**
   An outstanding URL (not suppressed) whose last appearance
   was more than `dedup days` ago is re-fetched.
   If still open, it is included in the new report as an item;
   its appearance counter is `prior count + 1`.
   If closed upstream, it is dropped silently.
3. **Updated-at dedup.**
   Skip a fresh item already reported within `dedup days` if
   its `updated_at` has not changed.
   Re-include a fresh item whose `updated_at` has advanced
   since the last report.

A project with no qualifying items (everything suppressed,
filtered, or deduped out) goes into the No updates section
instead of getting its own `## {project}` section.

## Step 7: Commit and (conditionally) push

Once the report file has been written and the prior report (if
any) has been back-edited for navigation:

```sh
git add report/<YYYYMMDD>.md report/<prior-YYYYMMDD>.md
git commit -m "Ketchup report YYYY-MM-DD"
```

The prior report path is only added if a back-edit actually
happened.
On a first-ever run with no prior report, stage today's file
alone.

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
- Every item entry's metadata line includes
  `(updated: ISO, appearance #N)`, and N equals the number of
  prior `report/*.md` files containing that URL plus one.
- No URL in the suppress-set appears as an item in the new
  report.
- The new report has a nav line (`[← prev](...) | next →`) just
  below the H1 and just above EOF.
- If a prior report exists, its `next →` half now points to
  today's filename in both the top and bottom positions.
- A commit was created with the expected message, staging both
  the new report and (if back-edited) the prior report.
- The push happened only when `$GITHUB_ACTIONS` was set.
