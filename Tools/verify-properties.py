#!/usr/bin/env python3
"""Check quantified claims with the actual portable CLI, Lean kernel and TLA tools."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser()
parser.add_argument('--formal', type=Path, required=True)
parser.add_argument('--output', type=Path)
parser.add_argument('--only', help='Comma-separated property names for focused verification')
args = parser.parse_args()
formal = args.formal.resolve()
work = args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix='formal-properties-'))
if args.output:
    work.mkdir()
measurements = []
selection = set(args.only.split(',')) if args.only else None
executed = []

def run(command, expected=0, cwd=None, env=None, timeout=180):
    start = time.monotonic()
    result = subprocess.run(list(map(str, command)), cwd=cwd, env=env, capture_output=True, text=True, timeout=timeout)
    measurements.append({'command': str(command[1]) if len(command) > 1 else str(command[0]), 'seconds': round(time.monotonic() - start, 3), 'exit': result.returncode})
    if result.returncode != expected:
        try:
            report = json.loads(result.stdout)
            directory = Path(report['runDirectory'])
            for path in sorted(directory.rglob('*')):
                if path.suffix in ['.stdout', '.stderr'] and path.stat().st_size:
                    print(path.name, path.read_text()[:10000])
        except (ValueError, KeyError):
            pass
        raise AssertionError((command, result.returncode, result.stdout, result.stderr))
    return result

def check(name, language, source, views, result_view, ensures, requires='true', expected='PROVED', exit_code=0):
    if selection is not None and name not in selection:
        return None, None
    executed.append(name)
    directory = work / name
    directory.mkdir()
    (directory / 'source').write_text(source)
    properties = {'schemaVersion': 1, 'properties': [{'name': name, 'entry': 'calculate', 'inputViews': views,
        'resultView': result_view, 'requires': requires, 'ensures': ensures}]}
    specification = directory / 'properties.json'
    specification.write_text(json.dumps(properties, indent=2))
    report = json.loads(run([formal, 'check', '--language', language, '--source', directory / 'source',
                            '--properties', specification, '--output', directory / 'Checked'], expected=exit_code).stdout)
    (directory / 'result.json').write_text(json.dumps(report, indent=2))
    assert report['scope'] == 'ALL_INPUTS_UNDER_PRECONDITIONS' and report['translation'] == 'UNVALIDATED'
    property = report['properties'][0]
    assert property['status'] == expected, report
    assert property['tla'] == 'SPECIFICATION_GENERATED', report
    if expected == 'PROVED':
        assert property['lean'] == 'PROVED' and property['executionBound'] > 0
        assert set(property['leanAxioms']) <= set(report['toolchain']['allowedLeanAxioms'])
        proof = next((Path(report['runDirectory']) / 'lean').glob('Property*.lean')).read_text()
        assert 'theorem checkedProperty' in proof and 'obligation' in proof and 'evaluate Generated.program' in proof
        assert not property.get('counterexample')
    if expected == 'COUNTEREXAMPLE':
        assert property['lean'] == 'COUNTEREXAMPLE_PROVED' and property['counterexampleTLC'] == 'COUNTEREXAMPLE'
        assert property['counterexample']
    print('PASS', name, expected, flush=True)
    return report, directory

try:
    sources = {
        'swift': ('func calculate(_ a: Int64) -> Int64 { return a - a }', 'signed'),
        'rust': ('fn calculate(a: i64) -> i64 { return a - a; }', 'signed'),
        'c': ('#include <stdint.h>\nint64_t calculate(int64_t a) { return a - a; }', 'signed'),
        'cpp': ('#include <cstdint>\nstd::int64_t calculate(std::int64_t a) { return a - a; }', 'signed'),
        'go': ('package main\nfunc calculate(a int64) int64 { return a - a }', 'signed'),
        'typescript': ('function calculate(a: bigint): bigint { return a - a; }', 'integer'),
        'javascript': ('function calculate(a) { return a - a; }', 'integer'),
        'python': ('def calculate(a: int) -> int:\n    return a - a\n', 'integer'),
    }
    for language, (source, view) in sources.items():
        check(language + '_all_inputs', language, source, [view], view, 'result == 0')
    addition, addition_directory = check('unbounded_addition', 'python', 'def calculate(a: int, b: int) -> int:\n    return a + b\n',
        ['integer', 'integer'], 'integer', 'result == arg1 + arg0')
    check('integer_precondition', 'python', 'def calculate(a: int, b: int) -> int:\n    return a + b\n',
        ['integer', 'integer'], 'integer', 'result >= arg0', 'arg1 >= 0')
    check('branch_minimum', 'python', 'def calculate(a: int, b: int) -> int:\n    if a < b:\n        return a\n    else:\n        return b\n',
        ['integer', 'integer'], 'integer', 'result <= arg0 && result <= arg1 && (result == arg0 || result == arg1)')
    check('direct_call', 'python', 'def helper(a: int, b: int) -> int:\n    return a + b\ndef calculate(a: int, b: int) -> int:\n    return helper(b, a)\n',
        ['integer', 'integer'], 'integer', 'result == arg0 + arg1')
    check('signed_precondition', 'swift', 'func calculate(_ a: Int64, _ b: Int64) -> Int64 { return a + b }',
        ['signed', 'signed'], 'signed', 'result == arg0 + arg1', 'arg0 >= 0 && arg1 >= 0 && arg0 + arg1 <= 9223372036854775807')
    check('unsigned_wrap', 'go', 'package main\nfunc calculate(a uint64) uint64 { return a + 1 }',
        ['unsigned'], 'unsigned', '(arg0 < 18446744073709551615 && result == arg0 + 1) || (arg0 == 18446744073709551615 && result == 0)')
    check('boolean_not', 'python', 'def calculate(a: bool) -> bool:\n    return not a\n', ['boolean'], 'boolean', 'result == !arg0')
    check('integer_comparison', 'python', 'def calculate(a: int, b: int) -> bool:\n    return a < b\n', ['integer', 'integer'], 'boolean', 'result == (arg0 < arg1)')
    check('constant_no_arguments', 'python', 'def calculate() -> int:\n    return 42\n', [], 'integer', 'result == 42')
    rare, _ = check('signed_boundary_counterexample', 'swift', 'func calculate(_ a: Int64) -> Int64 { return a + 1 }',
        ['signed'], 'signed', 'result > arg0', expected='COUNTEREXAMPLE', exit_code=5)
    if rare is not None:
        assert rare['properties'][0]['counterexample'] == ['9223372036854775807']
    check('large_integer_counterexample', 'python', 'def calculate(a: int) -> int:\n    return a\n',
        ['integer'], 'integer', 'result != 10000000000000000000000000000000000000001', expected='COUNTEREXAMPLE', exit_code=5)
    check('recursion_unknown', 'python', 'def calculate(a: int) -> int:\n    return calculate(a)\n',
        ['integer'], 'integer', 'result == arg0', expected='UNKNOWN', exit_code=6)
    check('no_witness_is_not_a_proof', 'python', 'def calculate(a: int, b: int, c: int) -> int:\n    return a\n',
        ['integer', 'integer', 'integer'], 'integer', 'result == 0',
        'arg0 == 7 && arg1 == 11 && arg2 == 13', expected='UNPROVED', exit_code=6)
    if addition is not None:
        # Recompile a mutated actual program, then reuse the unchanged quantified theorem.
        proof_root = work / 'Mutation'
        shutil.copytree(Path(addition['runDirectory']) / 'lean', proof_root)
        program_path = proof_root / 'Generated/Program.lean'
        original = program_path.read_text()
        assert '.add ' in original
        program_path.write_text(original.replace('.add ', '.subtract '))
        tools = formal.parent / 'toolchain'
        environment = {'PATH': '/usr/bin:/bin', 'LEAN_PATH': str(proof_root)}
        run([tools / 'lean/bin/lean', '-M', '1024', '-o', 'Generated/Program.olean', 'Generated/Program.lean'], cwd=proof_root, env=environment)
        mutation = run([tools / 'lean/bin/lean', '-M', '1024', 'Property0.lean'], expected=1, cwd=proof_root, env=environment)
        assert 'error:' in mutation.stdout and 'sorryAx' in mutation.stdout
        print('PASS actual_program_mutation_rejected', flush=True)
        combined_path = work / 'combined.json'
        combined_path.write_text(json.dumps({'schemaVersion': 1, 'properties': [
            {'name': 'commutative', 'entry': 'calculate', 'inputViews': ['integer', 'integer'],
             'resultView': 'integer', 'requires': 'true', 'ensures': 'result == arg1 + arg0'},
            {'name': 'wrong', 'entry': 'calculate', 'inputViews': ['integer', 'integer'],
             'resultView': 'integer', 'requires': 'true', 'ensures': 'result == arg0'}]}))
        # A new snapshot rechecks the original artifact and preserves earlier evidence.
        combined = json.loads(run([formal, 'check', '--artifact', addition_directory / 'Checked',
                                   '--properties', combined_path], expected=5).stdout)
        assert [p['status'] for p in combined['properties']] == ['PROVED', 'COUNTEREXAMPLE']
        assert Path(addition['runDirectory']).exists() and combined['runDirectory'] != addition['runDirectory']
        print('PASS mixed_property_recheck', flush=True)
        # Both spec options together must fail before toolchain probing or output publication.
        rejected_output = work / 'Rejected'
        rejected = run([formal, 'check', '--language', 'python', '--source', addition_directory / 'source',
            '--properties', addition_directory / 'properties.json', '--scenario', addition_directory / 'properties.json', '--output', rejected_output], expected=2)
        assert not rejected_output.exists()
        invalid = work / 'invalid.json'; invalid.write_text('{"schemaVersion":1,"properties":[]}')
        run([formal, 'check', '--language', 'python', '--source', addition_directory / 'source',
             '--properties', invalid, '--output', rejected_output], expected=2)
        assert not rejected_output.exists()
    assert executed and (selection is None or selection <= set(executed)), 'Unknown or empty property selection'
    summary = {'status': 'PASSED', 'properties': executed, 'measurements': measurements}
    (work / 'summary.json').write_text(json.dumps(summary, indent=2))
    print(json.dumps(summary, indent=2))
finally:
    if not args.output:
        shutil.rmtree(work)
