"""Check an offline HTML build's links, anchors, evidence and source coverage."""

import argparse
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET
from urllib.parse import unquote, urlsplit


class Page(HTMLParser):
    def __init__(self, path):
        super().__init__()
        self.path = path
        self.ids = set()
        self.links = []
        self.resources = {}
        self.errors = []
        self.main_count = 0
        self.h1_count = 0
        self.lang = ""
        self.in_title = False
        self.title = ""

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if "id" in attrs:
            if attrs["id"] in self.ids:
                self.errors.append(f"duplicate id: {attrs['id']}")
            self.ids.add(attrs["id"])
        if tag == "html":
            self.lang = attrs.get("lang", "")
        if tag == "main":
            self.main_count += 1
        if tag == "h1":
            self.h1_count += 1
        if tag == "title":
            self.in_title = True
        for key in ["href", "src"]:
            if key in attrs:
                self.links.append(attrs[key])
        if "data-resource" in attrs:
            self.resources[attrs["data-resource"]] = {
                "used": int(attrs["data-used"]), "available": int(attrs["data-available"])
            }

    def handle_endtag(self, tag):
        if tag == "title":
            self.in_title = False

    def handle_data(self, text):
        if self.in_title:
            self.title += text


def check(root, source):
    errors = []
    pages = {}
    for path in sorted(root.rglob("*.html")):
        page = Page(path)
        page.feed(path.read_text())
        pages[path] = page
        errors.extend(f"{path.relative_to(root)}: {error}" for error in page.errors)
        if not page.title or page.lang != "en":
            errors.append(f"{path.relative_to(root)}: missing title or language")
        if path.parent == root and (page.main_count != 1 or page.h1_count != 1):
            errors.append(f"{path.name}: expected one main landmark and one h1")
    for path, page in pages.items():
        for target in page.links:
            parsed = urlsplit(target)
            if parsed.scheme or parsed.netloc:
                if parsed.scheme in {"javascript", "data"}:
                    errors.append(f"{path.name}: unexpected executable link {target}")
                continue
            dest = (path.parent / unquote(parsed.path)).resolve() if parsed.path else path
            if not dest.is_relative_to(root) or not dest.exists():
                errors.append(f"{path.relative_to(root)}: missing local target {target}")
            elif parsed.fragment and dest in pages and unquote(parsed.fragment) not in pages[dest].ids:
                errors.append(f"{path.relative_to(root)}: missing anchor {target}")
    manifest = json.loads((root / "manifest.json").read_text())
    search_js = (root / "assets/search-index.js").read_text()
    prefix = "window.CHIPBUILDER_SEARCH = "
    if not search_js.startswith(prefix):
        errors.append("Missing bundled search index")
        search = []
    else:
        search = json.loads(search_js.removeprefix(prefix).strip().removesuffix(";"))
    expected = {"README.md", "hardware/README.md", "sim/README.md"} | {p.relative_to(source).as_posix() for p in (source / "docs").rglob("*.md")}
    indexed = {doc["source"] for doc in search}
    manifested = {doc["source"] for doc in manifest["documents"]}
    if indexed != expected or manifested != expected or len(search) != len(expected):
        errors.append(f"Document coverage differs: missing={expected - indexed}, extra={indexed - expected}")
    for doc in search:
        if root / doc["url"] not in pages or not doc["text"].strip():
            errors.append(f"Missing searchable page/body: {doc['source']}")
        if re.match(r"\d{4}-", Path(doc["source"]).name):
            text = (source / doc["source"]).read_text()
            match = re.search(r"^Status: (Accepted|Proposed|Superseded)$", text, re.M)
            if not match or match.group(1) != doc["state"]:
                errors.append(f"Decision state does not match source: {doc['source']}")
    config = json.loads((source / "docs/site/navigation.json").read_text())
    evidence = json.loads((source / config["audit_evidence"]).read_text())
    if manifest["evidence"] != evidence:
        errors.append("Bundled evidence differs from checked-in audit")
    integration = json.loads((source / config["integration_evidence"]).read_text())
    if manifest.get("integration_evidence") != integration:
        errors.append("Bundled integration evidence differs from the current snapshot")
    designs = [json.loads((source / path).read_text()) for path in config.get("design_evidence", [])]
    if manifest.get("design_evidence", []) != designs:
        errors.append("Bundled chip-design evidence differs from the current snapshots")
    for proof in [integration, *designs]:
        for relative, digest in {**proof["source_sha256"], **proof.get("media_sha256", {})}.items():
            path = (source / relative).resolve()
            if not path.is_relative_to(source) or not path.is_file():
                errors.append(f"Current evidence references a missing/outside source: {relative}")
            elif hashlib.sha256(path.read_bytes()).hexdigest() != digest:
                errors.append(f"Current evidence is stale for {relative}; rerun affected checks and record their snapshot")
    # Every checked-in snapshot is either current (hash-checked above) or
    # declared historical; nothing sits in the directory unclassified.
    current = {config["audit_evidence"], config["integration_evidence"], *config.get("design_evidence", [])}
    historical = set(config.get("historical_evidence", []))
    present = {p.relative_to(source).as_posix() for p in (source / "docs/research/evidence").glob("*.json")}
    if current & historical or current | historical != present:
        errors.append(f"Evidence classification differs from the directory: {sorted((current | historical) ^ present)} / both: {sorted(current & historical)}")
    home = pages.get(root / "index.html")
    if not home:
        errors.append("No home page")
    else:
        for key, value in evidence["post_route_with_test_harness"].items():
            if home.resources.get(key) != {"used": value["used"], "available": value["available"]}:
                errors.append(f"Dashboard {key} figures differ from audit")
    for doc in manifest["documents"]:
        raw = root / "sources" / doc["source"]
        if not raw.exists() or raw.read_bytes() != (source / doc["source"]).read_bytes():
            errors.append(f"Raw source missing or changed: {doc['source']}")
    chip_prefix = "window.CHIPBUILDER_CHIPS = "
    chip_data = json.loads((root / "assets/chip-design-data.js").read_text().removeprefix(chip_prefix).strip().removesuffix(";"))
    exports = {path.stem: path for path in (root / "assets/chips").glob("*.svg")}
    if set(exports) != set(chip_data):
        errors.append("SVG exports and chip inspector coverage differ")
    for key, path in exports.items():
        svg = ET.parse(path).getroot()
        ids = [element.attrib["id"] for element in svg.iter() if "id" in element.attrib]
        if len(ids) != len(set(ids)):
            errors.append(f"{path.name}: duplicate SVG id")
        for reference in re.findall(r"url\(#([^)]+)\)", path.read_text()):
            if reference not in ids:
                errors.append(f"{path.name}: missing SVG reference {reference}")
        nodes = {element.attrib["data-chip-node"] for element in svg.iter() if "data-chip-node" in element.attrib}
        if nodes != set(chip_data.get(key, {}).get("nodes", {})):
            errors.append(f"{path.name}: SVG blocks and inspector contracts differ")
        if not svg.attrib.get("viewBox"):
            errors.append(f"{path.name}: SVG lacks a scalable viewBox")
    if errors:
        raise SystemExit("\n".join(errors))
    print(f"Documentation passed: {len(expected)} searchable source documents, {len(pages)} HTML files, {len(exports)} SVG diagrams, local links/anchors, ADR states and evidence metrics")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("site", type=Path)
    parser.add_argument("source", type=Path)
    args = parser.parse_args()
    check(args.site.resolve(), args.source.resolve())
