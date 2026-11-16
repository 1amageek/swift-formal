#!/usr/bin/env python3
"""Prepare pinned formal tools locally; never called by generation or checking."""
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
store = Path(os.environ.get('FORMAL_TOOLS_ROOT', root / '.tools')).resolve()
store.mkdir(exist_ok=True)
lock = json.loads((root / 'Tools/toolchain-artifacts.lock.json').read_text())

def digest(path):
    with path.open('rb') as handle:
        return hashlib.file_digest(handle, 'sha256').hexdigest()

def fetch(metadata, path):
    if path.is_file() and digest(path) == metadata['sha256']:
        return
    pending = path.with_suffix(path.suffix + '.download')
    subprocess.run(['/usr/bin/curl', '-fLsS', '--retry', '2', '--max-time', '300',
                    metadata['url'], '-o', str(pending)], check=True, timeout=320)
    if digest(pending) != metadata['sha256']:
        pending.unlink()
        raise RuntimeError('Formal tool archive checksum mismatch.')
    os.replace(pending, path)

lean_root = store / 'lean-4.35.0-darwin_aarch64'
if not (lean_root / 'bin/lean').is_file():
    archive = store / 'lean-4.35.0-darwin_aarch64.zip'
    fetch(lock['lean'], archive)
    listing = subprocess.run(['tar', '-tvf', str(archive)], capture_output=True,
                             text=True, check=True, timeout=90).stdout
    unpacked_bytes = 0
    for line in listing.splitlines():
        parts = line.split()
        if len(parts) >= 9 and (parts[-1].startswith('lean-4.35.0-darwin_aarch64/lib/') or
                               parts[-1].startswith('lean-4.35.0-darwin_aarch64/bin/')):
            unpacked_bytes += int(parts[4])
    if shutil.disk_usage(store).free < unpacked_bytes + 268435456:
        raise RuntimeError('Insufficient free space for verified Lean extraction and temporary files.')
    with tempfile.TemporaryDirectory(prefix='prepare-', dir=store) as temporary:
        subprocess.run(['tar', '-xf', str(archive), '-C', temporary,
                        'lean-4.35.0-darwin_aarch64/bin/lean',
                        'lean-4.35.0-darwin_aarch64/bin/leanchecker',
                        'lean-4.35.0-darwin_aarch64/bin/lake',
                        'lean-4.35.0-darwin_aarch64/lib',
                        'lean-4.35.0-darwin_aarch64/LICENSE',
                        'lean-4.35.0-darwin_aarch64/LICENSES'], check=True, timeout=180)
        extracted = Path(temporary) / lean_root.name
        if lean_root.exists():
            raise RuntimeError('Incomplete Lean installation exists; inspect it before replacement.')
        os.replace(extracted, lean_root)
fetch(lock['tla'], store / 'tla2tools.jar')
subprocess.run([str(lean_root / 'bin/lean'), '--version'], check=True, timeout=15)
print('Pinned formal tools are prepared under .tools; no system installation was performed.')
