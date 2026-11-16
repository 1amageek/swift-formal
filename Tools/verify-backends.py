#!/usr/bin/env python3
"""Check actual emitted files with pinned external tools; not translation validation."""
import os
import re
import json
import hashlib
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
lean = root / '.tools/lean-4.35.0-darwin_aarch64/bin'
jar = root / '.tools/tla2tools.jar'
tool_lock = json.loads((root / 'Tools/toolchain-artifacts.lock.json').read_text())
with jar.open('rb') as handle:
    assert hashlib.file_digest(handle, 'sha256').hexdigest() == tool_lock['tla']['sha256'], 'TLA tools hash mismatch'

def audit_axioms(output, expected_count):
    declarations = 0
    for line in output.splitlines():
        if 'does not depend on any axioms' in line:
            declarations += 1
        elif 'depends on axioms:' in line:
            declarations += 1
            names = re.search(r'\[(.*)\]', line).group(1)
            dependencies = {name.strip() for name in names.split(',') if name.strip()}
            assert dependencies <= set(tool_lock['allowedLeanAxioms']), line
    assert declarations == expected_count, output
    assert 'sorryAx' not in output and "declaration uses 'sorry'" not in output, output

def run(arguments, cwd=root, timeout=120, environment=None):
    completed = subprocess.run(arguments, cwd=cwd, env=environment, timeout=timeout,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if completed.returncode:
        print(completed.stdout)
        raise AssertionError(f'External command failed ({completed.returncode}): {arguments}')
    return completed.stdout

def bits(value, width=64):
    return '<<' + ', '.join(str((value >> index) & 1) for index in range(width)) + '>>'

def integer(value):
    return f'Aggregate(<<Bits(64, {bits(value)})>>)'

with tempfile.TemporaryDirectory(prefix='formal-backends-') as temporary:
    output = Path(temporary)
    environment = {**os.environ, 'FORMAL_BACKEND_OUTPUT': str(output)}
    run(['swift', 'test', '--filter', 'BackendEmissionTests'], environment=environment, timeout=180)
    environment = {**os.environ, 'PATH': str(lean) + os.pathsep + os.environ['PATH']}
    print(run([str(lean / 'lake'), 'build'], cwd=output / 'lean', environment=environment, timeout=180))
    properties = output / 'lean/FiniteChecks.lean'
    properties.write_text('''import Generated.Program
open SwiftFormal Generated

def int64 (value : Nat) : Value := .aggregate [.bits 64 value]
def result (entry : String) (actual : List Value) : Option Evaluation :=
  (initial program entry actual).map (evaluate program 100)

theorem subtraction : result "$s4Core8subtractys5Int64VAD_ADtF" [int64 9, int64 2] =
  some (.terminal { frames := [], status := .returned (int64 7) }) := by rfl

theorem directCall : result "$s4Core4callys5Int64VAD_ADtF" [int64 9, int64 2] =
  some (.terminal { frames := [], status := .returned (int64 7) }) := by rfl

theorem branch : result "$s4Core6chooseys5Int64VADF" [int64 (2^64 - 7)] =
  some (.terminal { frames := [], status := .returned (int64 7) }) := by rfl

theorem wrapping : result "$s4Core16wrappingSubtractys5Int64VAD_ADtF" [int64 (2^63), int64 1] =
  some (.terminal { frames := [], status := .returned (int64 (2^63 - 1)) }) := by rfl

#print axioms subtraction
#print axioms directCall
#print axioms branch
#print axioms wrapping
''')
    audit = run([str(lean / 'lake'), 'env', 'lean', str(properties)], cwd=output / 'lean', environment=environment)
    audit_axioms(audit, 4)
    print(audit)
    reference_root = root / '.tools/reference'
    (reference_root / 'SwiftFormal').mkdir(parents=True, exist_ok=True)
    reference_env = {**environment, 'LEAN_PATH': str(reference_root)}
    for name in ['Runtime', 'SILDecoder']:
        run([str(lean / 'lean'), '-o', str(reference_root / 'SwiftFormal' / (name + '.olean')),
             str(root / 'Semantics/Lean/SwiftFormal' / (name + '.lean'))], environment=reference_env)
    entries = ['$s4Core8subtractys5Int64VAD_ADtF', '$s4Core16wrappingSubtractys5Int64VAD_ADtF',
               '$s4Core6chooseys5Int64VADF', '$s4Core4callys5Int64VAD_ADtF']
    reference_file = output / 'lean/ReferenceChecks.lean'
    run([str(lean / 'lean'), '--run', str(root / 'Semantics/Lean/ReferenceCheck.lean'),
         str(root / 'Fixtures/SIL/Core.sil'), 'Core', str(reference_file), *entries], environment=reference_env)
    reference_audit = run([str(lean / 'lake'), 'env', 'lean', str(reference_file)], cwd=output / 'lean', environment=environment)
    audit_axioms(reference_audit, 3)
    assert 'does not depend on any axioms' in reference_audit, reference_audit
    print(reference_audit)
    mutated_sil = output / 'Mutated.sil'
    mutated_sil.write_text((root / 'Fixtures/SIL/Core.sil').read_text().replace('ssub_with_overflow_Int64', 'sadd_with_overflow_Int64'))
    mutation_certificate = output / 'lean/MutatedReference.lean'
    run([str(lean / 'lean'), '--run', str(root / 'Semantics/Lean/ReferenceCheck.lean'),
         str(mutated_sil), 'Core', str(mutation_certificate), *entries], environment=reference_env)
    mutation = subprocess.run([str(lean / 'lake'), 'env', 'lean', str(mutation_certificate)], cwd=output / 'lean',
                              env=environment, timeout=120, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    assert mutation.returncode != 0 and 'rfl' in mutation.stdout, mutation.stdout
    print('Independent Lean decoder: data equality and shared-step correspondence checked; arithmetic mutation rejected.')
    for file in ['Program.tla', 'Properties.tla']:
        sany = run(['java', '-Xmx512m', '-cp', str(jar), 'tla2sany.SANY', file], cwd=output / 'tla')
        if 'error' in sany.lower():
            print(sany)
            raise AssertionError('SANY reported errors despite its process exit status.')
    scenarios = [
        ('Subtract', '$s4Core8subtractys5Int64VAD_ADtF', [9, 2], 7, False),
        ('Call', '$s4Core4callys5Int64VAD_ADtF', [9, 2], 7, False),
        ('Branch', '$s4Core6chooseys5Int64VADF', [(1 << 64) - 7], 7, False),
        ('Wrap', '$s4Core16wrappingSubtractys5Int64VAD_ADtF', [1 << 63, 1], (1 << 63) - 1, False),
        ('Trap', '$s4Core8subtractys5Int64VAD_ADtF', [1 << 63, 1], 0, True),
    ]
    for name, symbol, actual, expected, trap in scenarios:
        actual_text = '<<' + ', '.join(integer(value) for value in actual) + '>>'
        check = 'state.status # "returned"' if trap else f'(state.status = "returned" => state.result = {integer(expected)}) /\\ state.status # "trapped"'
        (output / 'tla' / f'{name}.tla').write_text(f'''---- MODULE {name} ----
EXTENDS SwiftFormalRuntime
VARIABLE state
P == INSTANCE Program WITH EntrySymbol <- "{symbol}", EntryArguments <- {actual_text}, state <- state
Init == P!Init
Next == P!Next
Expected == {check}
====
''')
        (output / 'tla' / f'{name}.cfg').write_text('INIT Init\nNEXT Next\nINVARIANT Expected\n')
        tlc = run(['java', '-Xmx512m', '-cp', str(jar), 'tlc2.TLC', '-workers', '1', '-cleanup', name], cwd=output / 'tla')
        assert 'Model checking completed. No error has been found.' in tlc, tlc
        assert 'distinct states found' in tlc and '1 distinct states found' not in tlc, tlc
        print(f'TLC {name}: completed with expected 64-bit result or trap.')
print('External backend checks passed; independent SIL translation validation remains pending.')
