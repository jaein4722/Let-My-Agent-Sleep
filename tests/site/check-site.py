#!/usr/bin/env python3
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlparse
import sys
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[2]
SITE = ROOT / "site"
DOCS = SITE / "docs"
BASE_URL = "https://jaein4722.github.io/Let-My-Agent-Sleep/"
SITEMAP_NS = {"sm": "http://www.sitemaps.org/schemas/sitemap/0.9"}


class LinkParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []
        self.title = None
        self._in_title = False
        self.description = None
        self.canonical = None

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "title":
            self._in_title = True
        if tag == "meta" and attrs.get("name") == "description":
            self.description = attrs.get("content")
        if tag == "link" and attrs.get("rel") == "canonical":
            self.canonical = attrs.get("href")
        for key in ("href", "src"):
            value = attrs.get(key)
            if value:
                self.links.append(value)

    def handle_endtag(self, tag):
        if tag == "title":
            self._in_title = False

    def handle_data(self, data):
        if self._in_title:
            text = data.strip()
            if text:
                self.title = text


def page_url(path: Path) -> str:
    rel = path.relative_to(SITE).as_posix()
    if rel == "index.html":
        return BASE_URL
    if rel == "docs/index.html":
        return BASE_URL + "docs/"
    return BASE_URL + rel


def local_target(path: Path, link: str) -> Path | None:
    if link.startswith(("#", "mailto:", "http://", "https://")):
        return None
    parsed = urlparse(link)
    if not parsed.path:
        return None
    return (path.parent / parsed.path).resolve()


def main() -> int:
    errors = []
    html_files = sorted([SITE / "index.html", *DOCS.glob("*.html")])

    for path in html_files:
        parser = LinkParser()
        parser.feed(path.read_text(encoding="utf-8"))

        if not parser.title:
            errors.append(f"{path}: missing <title>")
        if not parser.description:
            errors.append(f"{path}: missing meta description")
        if parser.canonical != page_url(path):
            errors.append(f"{path}: canonical {parser.canonical!r} != {page_url(path)!r}")

        for link in parser.links:
            target = local_target(path, link)
            if target is not None and not target.exists():
                errors.append(f"{path}: missing local link {link} -> {target}")

    sitemap = SITE / "sitemap.xml"
    try:
        tree = ET.parse(sitemap)
    except ET.ParseError as exc:
        errors.append(f"{sitemap}: invalid XML: {exc}")
        tree = None

    if tree is not None:
        urls = {
            loc.text
            for loc in tree.findall(".//sm:loc", SITEMAP_NS)
            if loc.text
        }
        expected = {page_url(path) for path in html_files}
        missing = sorted(expected - urls)
        extra = sorted(urls - expected)
        for url in missing:
            errors.append(f"{sitemap}: missing URL {url}")
        for url in extra:
            errors.append(f"{sitemap}: unexpected URL {url}")

    demo = SITE / "demo.gif"
    if not demo.exists():
        errors.append(f"{demo}: missing README demo GIF")
    elif demo.stat().st_size < 10_000:
        errors.append(f"{demo}: unexpectedly small demo GIF ({demo.stat().st_size} bytes)")

    social = SITE / "social-card.svg"
    if not social.exists():
        errors.append(f"{social}: missing social card")

    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1

    print(f"ok site checks: {len(html_files)} html pages")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
