#!/usr/bin/env python3
"""Check the required reentrant counterexample and non-suspending design."""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--toolchain', required=True, type=Path)
args = parser.parse_args()
tools = args.toolchain.resolve()
root = Path(__file__).resolve().parent
for config, expected in [('Correct.cfg', None), ('Reentrant.cfg', 'Invariant NoOverselling is violated')]:
    with tempfile.TemporaryDirectory(prefix='formal-actor-contract-') as scratch:
        result = subprocess.run([str(tools / 'java/Contents/Home/bin/java'), '-Xmx512m', '-Djava.io.tmpdir=' + scratch,
            '-cp', str(tools / 'tla2tools.jar'), 'tlc2.TLC', '-workers', '1', '-metadir', scratch + '/states',
            '-config', str(root / config), str(root / 'ActorIsolation.tla')], cwd=root, capture_output=True, text=True, timeout=60)
        output = result.stdout + result.stderr
        (root / (config + '.log')).write_text(output)
        if expected:
            assert result.returncode != 0 and expected in output, output
        else:
            assert result.returncode == 0 and '0 states left on queue.' in output, output
        print(output)
result = subprocess.run([str(tools / 'lean/bin/lean'), '-DwarningAsError=true', 'ActorIsolation.lean'], cwd=root, capture_output=True, text=True, timeout=60)
output = result.stdout + result.stderr
(root / 'Lean.log').write_text(output)
assert result.returncode == 0, output
audits = [line for line in output.splitlines() if line.startswith("'ActorIsolation.")]
assert len(audits) == 4 and 'sorryAx' not in output, output
for line in audits:
    if 'does not depend on any axioms' in line:
        continue
    match = re.search(r'depends on axioms: \[(.*)\]$', line)
    assert match and {name.strip() for name in match[1].split(',')} <= {'propext', 'Quot.sound', 'Classical.choice'}, line
print(output)
print('Reentrancy counterexample, atomic safety and four Lean theorems checked.')
