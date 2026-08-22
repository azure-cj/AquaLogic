"""Check relative Markdown links in the repository documentation."""

from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import unquote


LINK_PATTERN = re.compile(r"\[[^\]]+\]\(([^)]+)\)")


def markdown_files(repository_root: Path) -> list[Path]:
    files = [repository_root / "README.md"]
    files.extend((repository_root / "docs").rglob("*.md"))
    return sorted(path for path in files if path.is_file())


def relative_target(target: str) -> str | None:
    target = target.strip()
    if not target or target.startswith(("#", "http://", "https://", "mailto:")):
        return None
    if target.startswith("<") and ">" in target:
        target = target[1 : target.index(">")]
    return unquote(target.split("#", 1)[0].strip()) or None


def missing_links(repository_root: Path) -> list[str]:
    missing: list[str] = []
    for document in markdown_files(repository_root):
        text = document.read_text(encoding="utf-8")
        for match in LINK_PATTERN.finditer(text):
            target = relative_target(match.group(1))
            if target is None:
                continue
            resolved = (document.parent / target).resolve()
            if not resolved.exists():
                missing.append(f"{document.relative_to(repository_root)}: {target}")
    return missing


def main() -> int:
    repository_root = Path(__file__).resolve().parents[1]
    missing = missing_links(repository_root)
    print(f"Checked {len(markdown_files(repository_root))} Markdown files")
    if missing:
        print("Missing relative Markdown links:")
        print("\n".join(f"- {item}" for item in missing))
        return 1
    print("Markdown relative-link check: passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
