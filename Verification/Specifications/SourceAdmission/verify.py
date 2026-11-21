#!/usr/bin/env python3
"""Check the independent source-admission contract and its falsification controls."""
import argparse
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--toolchain', required=True, type=Path)
args = parser.parse_args()
tools = args.toolchain.resolve(strict=True)
root = Path(__file__).resolve().parent
model = (root / 'SourceAdmission.tla').read_text()
config = (root / 'SourceAdmission.cfg').read_text()


def check(name, source, configuration, violation=None):
    with tempfile.TemporaryDirectory(prefix='formal-source-admission-') as directory:
        work = Path(directory)
        (work / 'SourceAdmission.tla').write_text(source)
        (work / 'SourceAdmission.cfg').write_text(configuration)
        command = [str(tools / 'java/Contents/Home/bin/java'), '-Xmx512m',
                   '-Djava.io.tmpdir=' + directory, '-cp', str(tools / 'tla2tools.jar'),
                   'tlc2.TLC', '-workers', '1', '-config', 'SourceAdmission.cfg',
                   '-metadir', str(work / 'states'), 'SourceAdmission.tla']
        result = subprocess.run(command, cwd=work, capture_output=True, text=True, timeout=30)
        output = result.stdout + result.stderr
        (root / (name + '.log')).write_text(output)
        if violation:
            assert result.returncode != 0 and 'Invariant ' + violation + ' is violated' in output, output
        else:
            assert result.returncode == 0 and 'Model checking completed. No error has been found.' in output, output
            assert '0 states left on queue.' in output, output


check('TLC', model, config)
wrong_code = model.replace('kind = "outsideProfile" -> 3', 'kind = "outsideProfile" -> 4')
assert wrong_code != model
check('misclassified-unsupported', wrong_code, config, 'CorrectClassification')
wrong_artifact = model.replace('/\\ UNCHANGED <<kind, artifact, translation>>',
                               '/\\ artifact\' = TRUE /\\ UNCHANGED <<kind, translation>>')
assert wrong_artifact != model
check('rejected-artifact', wrong_artifact, config, 'NoRejectedArtifact')
check('draft-reachable', model, config + '\nINVARIANT DraftReachable\n', 'DraftReachable')
lean = subprocess.run([str(tools / 'lean/bin/lean'), '-DwarningAsError=true', 'SourceAdmission.lean'],
                      cwd=root, capture_output=True, text=True, timeout=30)
output = lean.stdout + lean.stderr
(root / 'Lean.log').write_text(output)
assert lean.returncode == 0, output
assert output.count('does not depend on any axioms') == 2, output
assert output.count('depends on axioms: [propext]') == 2, output
assert 'sorryAx' not in output, output
print('Three admission invariants, four Lean theorems and three controls checked.')
