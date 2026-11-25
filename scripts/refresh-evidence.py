"""Re-record source and media hashes in the current evidence snapshots.

Run only after `nix flake check` passes on the same tree: a hash says the
recorded results were reproduced with that file's present contents. Historical
snapshots listed in docs/site/navigation.json are never touched. With --check,
report stale entries and change nothing.
"""

import hashlib
import json
from pathlib import Path
import sys

root = Path(__file__).resolve().parent.parent
config = json.loads((root / "docs/site/navigation.json").read_text())
current = [config["audit_evidence"], config["integration_evidence"], *config["design_evidence"]]
check_only = "--check" in sys.argv[1:]
stale = []
for relative in current:
    path = root / relative
    proof = json.loads(path.read_text())
    changed = False
    for key in ("source_sha256", "media_sha256"):
        for source, digest in proof.get(key, {}).items():
            actual = hashlib.sha256((root / source).read_bytes()).hexdigest()
            if actual != digest:
                stale.append(f"{relative}: {source}")
                proof[key][source] = actual
                changed = True
    if changed and not check_only:
        path.write_text(json.dumps(proof, indent=2) + "\n")
print("\n".join(stale) if stale else "All current evidence hashes match")
if check_only and stale:
    sys.exit(1)
