"""Copy a prototype to MiSTer's temporary RAM filesystem, optionally load it."""
import argparse
import hashlib
from pathlib import Path
import re
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--host", required=True, help="SSH destination, e.g. root@192.168.1.10")
parser.add_argument("--rbf", type=Path, default=Path("build/mister/SRVL.rbf"))
parser.add_argument("--load", action="store_true", help="Replace the running core using MiSTer's command FIFO")
args = parser.parse_args()
if not re.fullmatch(r"[A-Za-z0-9_.@:-]+", args.host) or args.host.startswith("-"):
    parser.error("Use a hostname, IPv4 address, or SSH host alias, optionally prefixed by user@")
if not args.rbf.is_file() or args.rbf.suffix.lower() != ".rbf":
    parser.error(f"RBF not found: {args.rbf}; first build .#prototype -o build/mister")
data = args.rbf.read_bytes()
if not data:
    parser.error("RBF is empty")
digest = hashlib.sha256(data).hexdigest()
remote = f"/tmp/SRVL-{digest}.rbf"
ssh = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", args.host]
subprocess.run(ssh + [f"test -e /dev/MiSTer_cmd && cat > {remote}"], input=data, check=True, timeout=60)
verified = subprocess.check_output(ssh + [f"sha256sum {remote}"], timeout=20).decode().split()[0]
if verified != digest:
    raise SystemExit("Remote RBF checksum mismatch; core was not loaded")
print(f"Verified {digest}: {remote}", flush=True)
if args.load:
    subprocess.run(ssh + [f"printf '%s\\n' 'load_core {remote}' > /dev/MiSTer_cmd"], check=True, timeout=20)
    print("MiSTer accepted the load command. Verify image, controls and sound on the device.")
else:
    print("Copied only. Pass --load to switch cores. No SD-card files were changed.")
