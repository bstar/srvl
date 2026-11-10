"""Check repository-local Markdown links and ADR status metadata; no network."""
from pathlib import Path
import re
import sys
from urllib.parse import unquote

root = Path(sys.argv[1]).resolve()
errors = []
for path in sorted(root.rglob("*.md")):
    if any(part in {".git", ".cache", "vendor", "build"} for part in path.relative_to(root).parts):
        continue
    text = path.read_text()
    for target in re.findall(r"\[[^\]]*\]\(([^)]+)\)", text):
        target = target.strip("<>").split("#", 1)[0]
        if not target or re.match(r"[a-zA-Z][a-zA-Z0-9+.-]*:", target):
            continue
        dest = (path.parent / unquote(target)).resolve()
        if not dest.is_relative_to(root) or not dest.exists():
            errors.append(f"{path.relative_to(root)}: invalid local link {target}")
    if re.match(r"\d{4}-", path.name):
        if not re.search(r"^Status: (Accepted|Proposed|Superseded)$", text, re.M):
            errors.append(f"{path.relative_to(root)}: missing or invalid ADR status")
        for section in ("Context", "Decision", "Consequences", "References"):
            if f"## {section}" not in text:
                errors.append(f"{path.relative_to(root)}: missing {section}")
if errors:
    sys.exit("\n".join(errors))
print("Local documentation links and ADR metadata passed")
