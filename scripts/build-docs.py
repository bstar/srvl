"""Build a portable, offline HTML review area from repository documentation."""

import argparse
import html
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import shutil
from urllib.parse import quote, unquote, urlsplit

import markdown
from chip_diagrams import build_chip_diagrams, diagram_figure


def esc(value):
    return html.escape(str(value), quote=True)


def state_class(state):
    return re.sub(r"[^a-z0-9]+", "-", state.lower()).strip("-")


def page_name(source):
    if source == "README.md":
        return "project-readme.html"
    if source == "docs/project-status.md":
        return "index.html"
    if source == "docs/documentation.md":
        return "documentation.html"
    if source.startswith("docs/"):
        source = source[5:]
    return source.removesuffix(".md").replace("/", "-").lower() + ".html"


def title_of(text):
    match = re.search(r"^# (.+)$", text, re.M)
    if not match:
        raise ValueError("Document has no top-level title")
    return match.group(1).strip()


def document_state(source, text):
    if "/decisions/" in source and source.endswith(".md"):
        match = re.search(r"^Status: (Accepted|Proposed|Superseded)$", text, re.M)
        if match:
            return match.group(1)
    return "Reference"


class PlainText(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts = []

    def handle_data(self, data):
        self.parts.append(data)


class LocalLinks(HTMLParser):
    """Rewrite rendered links, collecting just the referenced local source assets."""

    def __init__(self, root, source, routes, assets):
        super().__init__(convert_charrefs=False)
        self.root, self.source, self.routes, self.assets = root, source, routes, assets
        self.parts = []

    def target(self, value):
        parsed = urlsplit(value)
        if parsed.scheme or parsed.netloc or not parsed.path:
            return value
        dest = (self.root / self.source).parent / unquote(parsed.path)
        dest = dest.resolve()
        if not dest.is_relative_to(self.root):
            raise ValueError(f"{self.source}: link leaves repository: {value}")
        rel = dest.relative_to(self.root).as_posix()
        if rel in self.routes:
            result = self.routes[rel]
        else:
            if not dest.exists():
                raise ValueError(f"{self.source}: missing local link: {value}")
            if any(part in {"vendor", "build", ".cache", ".git"} for part in Path(rel).parts):
                raise ValueError(f"{self.source}: cannot bundle generated/private tree: {value}")
            self.assets.add(rel)
            result = "sources/" + quote(rel, safe="/")
            if dest.is_dir():
                result += "/index.html"
        if parsed.query:
            result += "?" + parsed.query
        if parsed.fragment:
            result += "#" + parsed.fragment
        return result

    def handle_starttag(self, tag, attrs):
        if tag == "table":
            self.parts.append('<div class="table-wrap" tabindex="0" role="region" aria-label="Scrollable reference table">')
        rewritten = []
        for key, value in attrs:
            if value is not None and key in {"href", "src"}:
                value = self.target(value)
            rewritten.append(" " + key if value is None else f' {key}="{esc(value)}"')
        self.parts.append("<" + tag + "".join(rewritten) + ">")

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)

    def handle_endtag(self, tag):
        self.parts.append(f"</{tag}>")
        if tag == "table":
            self.parts.append("</div>")

    def handle_data(self, data):
        self.parts.append(data)

    def handle_entityref(self, name):
        self.parts.append(f"&{name};")

    def handle_charref(self, name):
        self.parts.append(f"&#{name};")


def home_dashboard(evidence, routes):
    def link(source):
        return routes[source]

    bars = []
    for key, label in [("LUT4", "Logic sites"), ("DFF", "Registers"), ("BSRAM", "Block RAM")]:
        item = evidence["post_route_with_test_harness"][key]
        percent = item["used"] / item["available"] * 100
        bars.append(f'''<div class="resource" data-resource="{key}" data-used="{item['used']}" data-available="{item['available']}">
          <div class="resource-name"><span>{label}</span><b>{percent:.1f}%</b></div>
          <div class="resource-track" role="meter" aria-label="{label} used by registered core probe" aria-valuemin="0" aria-valuemax="{item['available']}" aria-valuenow="{item['used']}"><div class="resource-fill" style="width:{percent:.3f}%"></div></div>
          <div class="resource-count">{item['used']:,} / {item['available']:,} · {item['remaining']:,} remain</div></div>''')
    achieved = evidence["clock_mhz"]["achieved"]
    return f'''
      <div class="target-strip" aria-label="Console targets">
        <div class="target-cell"><span class="target-label">Native canvas</span><div class="target-value">320 × 204</div><span class="target-sub">60 fps workload goal</span></div>
        <div class="target-cell"><span class="target-label">Legacy image</span><div class="target-value">Exact 2×</div><span class="target-sub">160 × 102 original pixels</span></div>
        <div class="target-cell"><span class="target-label">CPU location</span><div class="target-value">In FPGA</div><span class="target-sub">External CPU deferred</span></div>
        <div class="target-cell"><span class="target-label">Prototype board</span><div class="target-value">Tang 20K</div><span class="target-sub">Board port in progress</span></div>
      </div>
      <div class="section-label"><h2>Where we stand</h2><span>THREE DISTINCT WORKSTREAMS</span></div>
      <div class="status-grid">
        <section class="status-card"><span class="step">01 / ORIGINAL SYSTEM</span><span class="badge software-verified">Software verified</span><h2>A working game &amp; machine</h2><p>Circuit Courier runs on an HDL CPU with custom graphics, timers, controls and sound.</p><a href="{link('docs/architecture/software-prototype.md')}">Explore the prototype ↗</a></section>
        <section class="status-card"><span class="step">02 / LEGACY FEASIBILITY</span><span class="badge scoped-evidence">Scoped core evidence</span><h2>The Lynx core fits</h2><p>The registered console probe fits. Its 64 MHz timing report has partial model coverage and excludes board services.</p><a href="{link('docs/research/lynx-tang20k-compatibility.md')}">Review the evidence ↗</a></section>
        <section class="status-card"><span class="step">03 / BOARD INTEGRATION</span><span class="badge in-progress">In progress</span><h2>A playable Tang port</h2><p>Memory, loading, display, audio, clocks and controls must become one verified board build.</p><a href="{link('docs/roadmap.md')}">See the next gates ↗</a></section>
      </div>
      <div class="section-label"><h2>Measured FPGA baseline</h2><span>REGISTERED CORE PROBE ONLY</span></div>
      <section class="resource-panel" aria-label="Audited core resources"><p>Final routed figures from the checked-in Lynx feasibility audit. Real board peripherals still need headroom.</p><div class="resource-grid">{''.join(bars)}</div>
        <p class="resource-note"><strong>{achieved:.3f} MHz</strong> historical tool estimate with partial timing models · <strong>0</strong> commercial games tested · <strong>0</strong> physical Tang runs. <a href="{link('docs/milestones/tang-board-build.md')}">New board build and timing coverage ↗</a></p>
      </section>
      <div class="read-next"><a href="{link('docs/tradeoffs.md')}"><b>What still needs a decision →</b><small>Panel, enhanced budget, storage, audio and cost</small></a><a href="{link('docs/architecture/provenance.md')}"><b>What is original, and what is reused →</b><small>CPUs, Lynx logic, custom engines and tooling</small></a></div>
    '''


def architecture_panel():
    components = [
        ("cpu", "Lynx CPU", "Original instruction & bus behavior"),
        ("graphics", "Suzy + Mikey", "Graphics, math, audio, timers & DMA"),
        ("ram", "64 KiB work RAM", "Local memory; audited RAM adapter"),
    ]
    internal = "".join(f'<button class="component" data-component="{key}" aria-pressed="false"><span>{label}</span><small>{desc}</small></button>' for key, label, desc in components)
    return f'''<section class="architecture" aria-label="Inspectable console architecture">
      <h2>Follow the hardware boundaries</h2><p class="architecture-intro">Select a configuration, then a block to inspect its role, origin and current status.</p>
      <div class="mode-tabs" role="group" aria-label="Architecture configuration" hidden><button data-mode="legacy" aria-pressed="true">Tang legacy port</button><button data-mode="native" aria-pressed="false">Working native prototype</button><button data-mode="enhanced" aria-pressed="false">Enhanced target</button></div>
      <div class="diagram-grid"><div class="logic-boundary"><div class="boundary-label" id="boundary-label">PORTABLE FPGA LOGIC · SOFTWARE DIAGNOSTICS PASS</div>{internal}</div>
        <div class="diagram-arrow" aria-hidden="true">↔</div><button class="component external-chip" data-component="memory" aria-pressed="false"><span>8 MiB ×32 SDRAM</span><small>Cartridge & RGB presentation storage</small></button>
        <div class="diagram-arrow" aria-hidden="true">→</div><button class="component external-chip" data-component="display" aria-pressed="false"><span>Display + audio output</span><small>HDMI first; handheld panel unresolved</small></button>
        <div class="diagram-arrow" aria-hidden="true">←</div><button class="component external-chip" data-component="input" aria-pressed="false"><span>Loading + controls</span><small>USB UART bench interface</small></button>
      </div><div class="diagram-detail" id="diagram-detail" aria-live="polite"><strong>Original console and portable services pass software checks.</strong>The pinned CPU/Suzy/Mikey now run through the actual loader, SDRAM, buffered RGB and stereo I2S. Clock/pin wrappers, video serialization, physical audio and full board timing remain open. Each block is described below.</div>
      <div class="diagram-caption" id="diagram-caption">Logical integration is verified for original diagnostics; this is not a completed board bitstream or commercial-game certification.</div>
    </section>'''


GATE_STATES = {"Done": ("done", "Software verified"), "Active": ("active", "Active"), "Pending": ("", "Pending")}


def gate_panel(md, source):
    """Gate strip driven by the roadmap: each numbered section states `Gate: label · state`."""
    declared = re.findall(r"^## (\d+)\. [^\n]+\n\nGate: ([^·\n]+) · (\w+)$", source, re.M)
    tokens = [token for token in md.toc_tokens if re.match(r"\d+\.", token["name"])]
    if len(declared) != len(tokens):
        raise ValueError("docs/roadmap.md: every numbered gate needs a 'Gate: label · Done|Active|Pending' line")
    items = []
    for token, (number, label, state) in zip(tokens, declared):
        if state not in GATE_STATES or not token["name"].startswith(number + "."):
            raise ValueError(f"docs/roadmap.md: invalid gate line for section {number}")
        css, status = GATE_STATES[state]
        items.append(f'<a class="{css}" href="#{esc(token["id"])}"><small>{int(number):02d} / {status}</small>{esc(label.strip())}</a>')
    return '<nav class="gate-strip" aria-label="Work gates">' + "".join(items) + "</nav>"


def decisions_panel(documents):
    cards = []
    for doc in reversed(documents):
        if not re.match(r"\d{4}-", Path(doc["source"]).name):
            continue
        number, title = doc["title"].split(":", 1)
        state = doc["state"]
        cards.append(f'<a class="record-card" data-state="{esc(state)}" href="{doc["url"]}"><div class="record-top"><span>ADR {esc(number)}</span><span class="badge {state_class(state)}">{esc(state)}</span></div><h2>{esc(title.strip())}</h2></a>')
    return '<div class="record-tools" role="group" aria-label="Filter decision records" hidden>' + "".join(f'<button data-filter="{state}" aria-pressed="{"true" if state == "All" else "false"}">{state}</button>' for state in ["All", "Accepted", "Superseded", "Proposed"]) + '</div><p id="record-count" class="sr-only" role="status"></p><div class="record-grid">' + "".join(cards) + "</div>"


def chip_handbook_panel(routes, diagrams):
    chapters = sum(source.startswith("docs/chip-design/") for source in routes)
    return f'<div class="chip-handbook-intro"><div><strong>{chapters}</strong><span>DESIGN CHAPTERS</span></div><div><strong>{len(diagrams)}</strong><span>INSPECTABLE SVG DIAGRAMS</span></div><div><strong>Explicit</strong><span>INTERFACES + ACCEPTANCE</span></div></div>'


def build(root, out):
    if out == root or root.is_relative_to(out) or out.is_relative_to(root / "docs"):
        raise ValueError("Output must be outside docs/ and must not contain the repository")
    out.mkdir(parents=True, exist_ok=True)
    site = root / "docs/site"
    config = json.loads((site / "navigation.json").read_text())
    evidence = json.loads((root / config["audit_evidence"]).read_text())
    integration_evidence = json.loads((root / config["integration_evidence"]).read_text())
    design_evidence = [json.loads((root / path).read_text()) for path in config.get("design_evidence", [])]
    diagrams = build_chip_diagrams(out, evidence)
    paths = sorted([root / "README.md", root / "hardware/README.md", root / "sim/README.md", *root.joinpath("docs").rglob("*.md")])
    curated = {p["source"]: dict(p, group=g["title"]) for g in config["groups"] for p in g["pages"]}
    routes = {p.relative_to(root).as_posix(): page_name(p.relative_to(root).as_posix()) for p in paths}
    if len(set(routes.values())) != len(routes):
        raise ValueError("Duplicate output page names")
    if set(curated) - set(routes):
        raise ValueError(f"Missing curated documents: {set(curated) - set(routes)}")
    assets = {config["integration_evidence"], *config.get("design_evidence", [])}
    documents = []
    for path in paths:
        source = path.relative_to(root).as_posix()
        text = path.read_text()
        text = re.sub(r"^\{\{chip-diagram:([a-z0-9-]+)\}\}$",
                      lambda m: f'<div data-chip-placeholder="{m.group(1)}"></div>', text, flags=re.M)
        data = curated.get(source, {})
        md = markdown.Markdown(extensions=["tables", "fenced_code", "toc", "sane_lists"], extension_configs={"toc": {"toc_depth": "2-3"}})
        content = md.convert(re.sub(r"^# .+\n", "", text, count=1, flags=re.M))
        parser = LocalLinks(root, source, routes, assets)
        parser.feed(content)
        content = "".join(parser.parts)
        seen_diagrams = set()

        def embed_diagram(match):
            key = match.group(1)
            if key not in diagrams or key in seen_diagrams:
                raise ValueError(f"{source}: missing or repeated chip diagram {key}")
            seen_diagrams.add(key)
            return diagram_figure(diagrams[key])

        content = re.sub(r'<div data-chip-placeholder="([a-z0-9-]+)"></div>', embed_diagram, content)
        plain = PlainText()
        plain.feed(content)
        doc = {
            "source": source, "url": routes[source], "title": title_of(text),
            "label": data.get("label", title_of(text)), "state": data.get("state", document_state(source, text)),
            "group": data.get("group", "Decision history" if "/decisions/" in source else "Reference library"),
            "summary": data.get("summary", "Repository reference: " + source),
            "content": content, "toc": md.toc, "md": md,
            "text": " ".join(" ".join(plain.parts).split()),
        }
        documents.append(doc)
    # Decision ordering must be numeric, independent of directory traversal order.
    decision_docs = sorted(documents, key=lambda d: d["source"])
    for doc in documents:
        navigation = []
        for group in config["groups"]:
            links = []
            for item in group["pages"]:
                current = ' aria-current="page"' if item["source"] == doc["source"] else ""
                links.append(f'<a class="nav-link" href="{routes[item["source"]]}"{current}>{esc(item["label"])}</a>')
            navigation.append(f'<div class="nav-group"><p class="nav-title">{esc(group["title"])}</p>{"".join(links)}</div>')
        navigation.append('<div class="nav-group"><p class="nav-title">Explore everything</p><a class="nav-link" href="library.html">Reference library ↗</a></div>')
        extra = ""
        if doc["source"] == "docs/project-status.md":
            extra = home_dashboard(evidence, routes)
            extra += f'<div class="read-next"><a href="{routes["docs/chip-design/overview.md"]}"><b>Chip design handbook →</b><small>Detailed engine diagrams, interfaces and acceptance</small></a><a href="{routes["docs/chip-design/system.md"]}"><b>System control and boot ROM →</b><small>Circuits, firmware, loading and recovery boundaries</small></a></div>'
        elif doc["source"] == "docs/chip-design/overview.md":
            extra = chip_handbook_panel(routes, diagrams)
        elif doc["source"] == "docs/architecture/tang-prototype.md":
            extra = architecture_panel()
        elif doc["source"] == "docs/roadmap.md":
            extra = gate_panel(doc["md"], (root / doc["source"]).read_text())
        elif doc["source"] == "docs/architecture/decisions/README.md":
            extra = decisions_panel(decision_docs)
        notice = ""
        if doc["state"] in {"Historical", "Superseded"}:
            notice = f'<aside class="notice"><strong>Historical decision or platform assumptions.</strong><p>Preserved for context. Read the <a href="{routes["docs/architecture/tang-prototype.md"]}">current Tang architecture</a> and the linked superseding record before using these figures.</p></aside>'
        elif doc["source"].startswith("docs/research/"):
            notice = '<aside class="notice"><strong>Dated research, with scoped evidence.</strong><p>Use the review date and limitations below. Prices, availability and lifecycle observations are not current quotations.</p></aside>'
        doc.update(extra=extra, notice=notice, navigation="".join(navigation))
    template = (site / "template.html").read_text()

    def write_page(doc):
        context = {
            "TITLE": esc(doc["label"]), "DESCRIPTION": esc(doc["summary"]), "GROUP": esc(doc["group"]),
            "STATE": esc(doc["state"]), "STATE_CLASS": state_class(doc["state"]),
            "REVIEWED": esc(config["reviewed"]), "CONTENT": doc["content"],
            "TOC": doc["toc"], "NAVIGATION": doc["navigation"], "EXTRA": doc["extra"], "NOTICE": doc["notice"],
            "SOURCE_URL": "sources/" + quote(doc["source"], safe="/"), "SOURCE_LABEL": esc(doc["source"]),
        }
        result = re.sub(r"\{\{([A-Z_]+)\}\}", lambda m: context[m.group(1)], template)
        (out / doc["url"]).write_text(result)

    for doc in documents:
        write_page(doc)
        assets.add(doc["source"])
    cards = []
    for doc in documents:
        cards.append(f'<a class="library-card" href="{doc["url"]}"><div class="eyebrow">{esc(doc["group"])}<span class="badge {state_class(doc["state"])}">{esc(doc["state"])}</span></div><h2>{esc(doc["title"])}</h2><p>{esc(doc["source"])}</p></a>')
    library = dict(documents[0], label="Reference library", source="docs/README.md", url="library.html", group="Explore everything", state="Reference", summary=f"All {len(documents)} repository documents, including research, decision history and implementation records.", content='<div class="library-list">' + "".join(cards) + "</div>", toc="", extra="", notice="")
    # The library is not one of the source documents, so it has no active source-page nav item.
    library["navigation"] = re.sub(r' aria-current="page"', "", library["navigation"]).replace('href="library.html"', 'href="library.html" aria-current="page"')
    write_page(library)
    search = [{k: doc[k] for k in ["title", "label", "summary", "group", "state", "url", "source", "text"]} for doc in documents]
    (out / "assets").mkdir(exist_ok=True)
    (out / "assets/search-index.js").write_text("window.CHIPBUILDER_SEARCH = " + json.dumps(search, ensure_ascii=False) + ";\n")
    for name in ["site.css", "site.js", "chip.svg", "chip-design.css", "chip-design.js"]:
        shutil.copyfile(site / name, out / "assets" / name)
    for rel in sorted(assets):
        source, dest = root / rel, out / "sources" / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        if source.is_dir():
            # Directory references currently point to small source fixtures, never vendor/build trees.
            dest.mkdir(parents=True, exist_ok=True)
            for entry in source.rglob("*"):
                bundled = dest / entry.relative_to(source)
                if entry.is_dir():
                    bundled.mkdir(parents=True, exist_ok=True)
                else:
                    bundled.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(entry, bundled)
            entries = [f'<li><a href="{quote(p.name)}">{esc(p.name)}</a></li>' for p in sorted(dest.iterdir()) if p.is_file() and p.name != "index.html"]
            (dest / "index.html").write_text(f'<!doctype html><html lang="en"><meta charset="utf-8"><title>{esc(rel)} · source files</title><h1>{esc(rel)}</h1><ul>{"".join(entries)}</ul></html>')
        else:
            shutil.copyfile(source, dest)
    manifest = {
        "reviewed": config["reviewed"], "documents": [{k: doc[k] for k in ["source", "url", "state"]} for doc in documents],
        "evidence": evidence, "integration_evidence": integration_evidence,
        "design_evidence": design_evidence, "source_assets": sorted(assets),
    }
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Built {len(documents)} documents + library at {out}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    build(args.root.resolve(), args.output.resolve())
