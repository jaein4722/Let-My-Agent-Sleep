#!/usr/bin/env python3
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlparse
import json
import sys
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[2]
SITE = ROOT / "site"
DOCS = SITE / "docs"
BASE_URL = "https://jaein4722.github.io/Let-My-Agent-Sleep/"
INSTALL_COMMAND = "npx let-my-agent-sleep install"
NPM_URL = "https://www.npmjs.com/package/let-my-agent-sleep"
GITHUB_URL = "https://github.com/jaein4722/Let-My-Agent-Sleep"
SITEMAP_NS = {"sm": "http://www.sitemaps.org/schemas/sitemap/0.9"}


class LinkParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []
        self.title = None
        self._in_title = False
        self.description = None
        self.canonical = None
        self.meta = {}
        self.scripts = []
        self._script_type = None
        self._script_chunks = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "title":
            self._in_title = True
        if tag == "meta" and attrs.get("name") == "description":
            self.description = attrs.get("content")
        if tag == "meta":
            key = attrs.get("property") or attrs.get("name")
            if key:
                self.meta[key] = attrs.get("content")
        if tag == "link" and attrs.get("rel") == "canonical":
            self.canonical = attrs.get("href")
        if tag == "script":
            self._script_type = attrs.get("type")
            self._script_chunks = []
        for key in ("href", "src"):
            value = attrs.get(key)
            if value:
                self.links.append(value)

    def handle_endtag(self, tag):
        if tag == "title":
            self._in_title = False
        if tag == "script":
            if self._script_type:
                self.scripts.append((self._script_type, "".join(self._script_chunks)))
            self._script_type = None
            self._script_chunks = []

    def handle_data(self, data):
        if self._in_title:
            text = data.strip()
            if text:
                self.title = text
        if self._script_type:
            self._script_chunks.append(data)


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


def png_dimensions(path: Path) -> tuple[int, int] | None:
    data = path.read_bytes()[:24]
    if len(data) < 24 or data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        return None
    width = int.from_bytes(data[16:20], "big")
    height = int.from_bytes(data[20:24], "big")
    return width, height


def main() -> int:
    errors = []
    html_files = sorted([SITE / "index.html", *DOCS.glob("*.html")])

    for path in html_files:
        content = path.read_text(encoding="utf-8")
        parser = LinkParser()
        parser.feed(content)

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

        if path == SITE / "index.html":
            if content.count(INSTALL_COMMAND) < 3:
                errors.append(f"{path}: install command CTA drifted from {INSTALL_COMMAND!r}")
            if NPM_URL not in parser.links:
                errors.append(f"{path}: missing npm package link {NPM_URL}")
            if GITHUB_URL not in parser.links:
                errors.append(f"{path}: missing GitHub repository link {GITHUB_URL}")

            expected_image = BASE_URL + "social-card.png"
            expected_meta = {
                "og:type": "website",
                "og:url": BASE_URL,
                "og:title": parser.title,
                "og:image": expected_image,
                "twitter:card": "summary_large_image",
                "twitter:image": expected_image,
            }
            for key, expected in expected_meta.items():
                if parser.meta.get(key) != expected:
                    errors.append(f"{path}: {key} {parser.meta.get(key)!r} != {expected!r}")

            json_ld = [
                body
                for script_type, body in parser.scripts
                if script_type == "application/ld+json"
            ]
            if not json_ld:
                errors.append(f"{path}: missing application/ld+json")
            else:
                try:
                    schema = json.loads(json_ld[0])
                except json.JSONDecodeError as exc:
                    errors.append(f"{path}: invalid JSON-LD: {exc}")
                else:
                    expected_schema = {
                        "@type": "SoftwareApplication",
                        "name": "Let My Agent Sleep",
                        "url": BASE_URL,
                        "downloadUrl": NPM_URL,
                    }
                    for key, expected in expected_schema.items():
                        if schema.get(key) != expected:
                            errors.append(f"{path}: JSON-LD {key} {schema.get(key)!r} != {expected!r}")

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

    social = SITE / "social-card.svg"
    if not social.exists():
        errors.append(f"{social}: missing SVG social card source")

    social_png = SITE / "social-card.png"
    if not social_png.exists():
        errors.append(f"{social_png}: missing PNG social card")
    else:
        dimensions = png_dimensions(social_png)
        if dimensions != (1200, 630):
            errors.append(f"{social_png}: expected 1200x630 PNG, got {dimensions!r}")
        if social_png.stat().st_size < 10_000:
            errors.append(f"{social_png}: unexpectedly small PNG ({social_png.stat().st_size} bytes)")

    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1

    print(f"ok site checks: {len(html_files)} html pages")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
