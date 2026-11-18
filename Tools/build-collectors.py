#!/usr/bin/env python3
"""Rebuild the pinned SANY bridge; no download or runtime installation is performed."""
import argparse
import hashlib
import json
import os
import subprocess
import tempfile
from pathlib import Path


def sha256(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--javac', type=Path, required=True)
    parser.add_argument('--jar', type=Path, required=True)
    parser.add_argument('--write', action='store_true', help='Replace the checked SDK class after rebuilding')
    options = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    collector = root / 'Sources/FormalValidation/Inspection/Collectors'
    policy = json.loads((root / 'Sources/FormalValidation/Toolchain/toolchain-artifacts.lock.json').read_text())
    compiler, jar = options.javac.resolve(strict=True), options.jar.resolve(strict=True)
    if sha256(jar) != policy['tla']['sha256']:
        raise RuntimeError('Collector classpath differs from the SDK-pinned tla2tools artifact.')
    with tempfile.TemporaryDirectory(prefix='formal-collector-build-') as temporary:
        environment = {'PATH': '/usr/bin:/bin', 'HOME': temporary, 'LANG': 'C', 'LC_ALL': 'C'}
        version = subprocess.run([str(compiler), '-version'], env=environment,
                                 capture_output=True, text=True, check=True, timeout=10).stdout.strip()
        if not version.startswith('javac 24'):
            raise RuntimeError('The checked collector build profile requires JDK 24 targeting Java 21: ' + version)
        subprocess.run([str(compiler), '--release', '21', '-encoding', 'UTF-8', '-cp', str(jar),
                        '-d', temporary, str(collector / 'FormalSANY.java')],
                       env=environment, check=True, timeout=30)
        generated = Path(temporary) / 'FormalSANY.class'
        target = collector / 'FormalSANY.class'
        generated_digest = sha256(generated)
        if options.write:
            pending = target.with_suffix('.class.pending')
            with pending.open('wb') as stream:
                stream.write(generated.read_bytes())
                stream.flush()
                os.fsync(stream.fileno())
            pending.replace(target)
        elif sha256(target) != generated_digest:
            raise RuntimeError('Bundled collector differs from its source/build profile; review and rebuild explicitly.')
        print(json.dumps({'compiler': version, 'release': 21, 'jarSHA256': sha256(jar),
                          'classSHA256': generated_digest, 'mode': 'write' if options.write else 'check'}, sort_keys=True))


if __name__ == '__main__':
    main()
