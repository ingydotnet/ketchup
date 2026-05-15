# Ketchup Website

Source for the Ketchup site published at
https://ingydotnet.github.io/ketchup/.

The reports themselves live in `../report/YYYYMMDD.md` and are written by the
ketchup pipeline.
A MkDocs hook (`hooks/build_reports.py`) copies them into `docs/reports/` at
build time, so the source markdown stays untouched.

## Local Development

From the repo root:

```bash
make serve-www
```

Or from this directory:

```bash
make serve
```

This auto-installs Python via Makes, creates a venv, installs MkDocs +
Material, and starts a livereload server at http://localhost:8000.
The root URL redirects to the most recent report.

## Building

```bash
make build
```

Output goes in `site/`.

## Publishing

From the repo root:

```bash
make publish-www
```

Force-pushes the built `site/` to the `gh-pages` branch.
GitHub Pages serves from that branch (Settings -> Pages -> Source: Deploy
from a branch -> gh-pages / (root)).

The daily GitHub Actions workflow runs the same `make publish-www` after
each ketchup report run, so this only needs to be invoked manually for
out-of-band updates or first-time bootstrap.
