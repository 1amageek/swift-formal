#!/usr/bin/env python3
"""Run the requirements-derived outcome model and its falsification controls."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--toolchain', required=True, type=Path)
args = parser.parse_args()
tools = args.toolchain.resolve()
root = Path(__file__).resolve().parent
model = (root / 'VerificationOutcome.tla').read_text()
config = (root / 'VerificationOutcome.cfg').read_text()


def run_tlc(name, source, configuration, violation=None):
    with tempfile.TemporaryDirectory(prefix='formal-outcome-') as scratch:
        work = Path(scratch)
        (work / 'VerificationOutcome.tla').write_text(source)
        (work / 'VerificationOutcome.cfg').write_text(configuration)
        command = [
            str(tools / 'java/Contents/Home/bin/java'), '-Xmx512m',
            '-Djava.io.tmpdir=' + scratch, '-cp', str(tools / 'tla2tools.jar'),
            'tlc2.TLC', '-workers', '1', '-metadir', str(work / 'states'),
            '-config', 'VerificationOutcome.cfg', 'VerificationOutcome.tla',
        ]
        result = subprocess.run(command, cwd=work, capture_output=True, text=True, timeout=60)
        output = result.stdout + result.stderr
        (root / (name + '.log')).write_text(output)
        if violation is None:
            assert result.returncode == 0 and 'Model checking completed. No error has been found.' in output, output
            assert '0 states left on queue.' in output, output
        else:
            assert result.returncode != 0 and 'Invariant ' + violation + ' is violated' in output, output
        return output


print(run_tlc('TLC', model, config))
lean = subprocess.run(
    [str(tools / 'lean/bin/lean'), '-DwarningAsError=true', 'VerificationOutcome.lean'],
    cwd=root, capture_output=True, text=True, timeout=60,
)
output = lean.stdout + lean.stderr
(root / 'Lean.log').write_text(output)
assert lean.returncode == 0, output
assert output.count('depends on axioms: [propext]') == 4, output
assert 'sorryAx' not in output, output
print(output)

weak_gate = model.replace(
    'IF sany = "passed" /\\ lean = "passed" /\\ axioms = "passed"',
    'IF sany = "passed" /\\ lean = "passed"',
)
wrong_timeout = model.replace('/\\ result\' = "unknown"', '/\\ result\' = "proved"')
assert weak_gate != model and wrong_timeout != model
controls = [
    ('reachable-success', model, config + 'INVARIANT NeverProved\n', 'NeverProved'),
    ('missing-axiom-audit', weak_gate, config, 'ProofRequiresEvidence'),
    ('timeout-as-success', wrong_timeout,
     'SPECIFICATION Spec\nCHECK_DEADLOCK FALSE\nINVARIANT InterruptedCannotProve\n',
     'InterruptedCannotProve'),
]
records = []
for name, source, configuration, violation in controls:
    run_tlc(name, source, configuration, violation)
    records.append({'probe': name, 'invariant': violation, 'counterexampleConfirmed': True})
(root / 'controls.json').write_text(json.dumps(records, indent=2) + '\n')
print('Five invariants, four Lean theorems and three controls checked.')
