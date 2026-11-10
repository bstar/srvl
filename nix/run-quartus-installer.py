"""Run the legacy static installer and handle its observed post-completion hang.

Quartus 17.0's BitRock installer finishes writing its log then can hang in static
libc/NSS teardown with a modern FHS runtime. Never treat a timeout or merely
existing output files as success: require its explicit completion record. The
package also validates the installed paths; version/compile checks follow.
"""
import os
from pathlib import Path
import subprocess
import sys
import time

log = Path(os.environ["TMPDIR"]) / "bitrock_installer.log"
log.unlink(missing_ok=True)
process = subprocess.Popen(["unstick", *sys.argv[1:]])
deadline = time.monotonic() + 900
completed = False
while True:
    text = log.read_text(errors="replace") if log.exists() else ""
    completed = "Installation completed" in text and "Log finished" in text
    code = process.poll()
    if code is not None:
        if code != 0 or not completed:
            print(text[-12000:], flush=True)
            raise SystemExit(f"Installer failed or did not confirm completion (exit {code})")
        break
    if completed:
        # Give normal teardown a chance; only terminate after the completed log.
        try:
            code = process.wait(timeout=3)
            if code != 0:
                raise SystemExit(f"Installer exited with {code} after completion")
        except subprocess.TimeoutExpired:
            print("Installer confirmed completion; terminating hung legacy teardown.", flush=True)
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        break
    if time.monotonic() >= deadline:
        process.kill()
        process.wait()
        print(text[-12000:], flush=True)
        raise SystemExit("Installer timed out without a completion record")
    time.sleep(0.25)
print(text[-2500:], flush=True)
