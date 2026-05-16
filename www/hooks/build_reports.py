"""MkDocs hook: stage ../report/*.md into docs/reports/ at build time.

Idempotent: only writes destination files whose content differs from the
source, so livereload doesn't see spurious changes and loop.
"""

import json
import shutil
from pathlib import Path


def _write_if_changed(path: Path, content: bytes) -> None:
    if path.exists() and path.read_bytes() == content:
        return
    path.write_bytes(content)


def on_config(config, **kwargs):
    docs_dir = Path(config['docs_dir'])
    repo_root = docs_dir.parent.parent
    src_reports = repo_root / 'report'
    dst_reports = docs_dir / 'reports'
    dst_reports.mkdir(parents=True, exist_ok=True)

    sources = sorted(s for s in src_reports.glob('????????.md') if s.stem.isdigit())
    expected = {s.name for s in sources}
    expected.add('.pages')

    for stale in dst_reports.iterdir():
        if stale.name not in expected:
            stale.unlink()

    for src in sources:
        dst = dst_reports / src.name
        content = src.read_bytes()
        if not dst.exists() or dst.read_bytes() != content:
            shutil.copy2(src, dst)

    dates = sorted((s.stem for s in sources), reverse=True)

    def _pretty(d: str) -> str:
        return f'{d[0:4]}-{d[4:6]}-{d[6:8]}'

    pages = (
        'nav:\n'
        + ''.join(f"- '{_pretty(d)}': {d}.md\n" for d in dates)
    ).encode('utf-8')
    _write_if_changed(dst_reports / '.pages', pages)

    dates_json = (json.dumps(dates) + '\n').encode('utf-8')
    _write_if_changed(docs_dir / 'dates.json', dates_json)

    return config
