#!/usr/bin/env python3
"""Compare Java/Bun execution with IR/TLC/Lean and check quantified model properties."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--formal', type=Path, required=True)
parser.add_argument('--output', type=Path)
args = parser.parse_args()
formal = args.formal.resolve()
root = Path(__file__).resolve().parents[1]
work = args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix='formal-java-bun-'))
if args.output:
    work.mkdir()
records = []


def run(command, expected=0, cwd=None, timeout=180):
    result = subprocess.run(list(map(str, command)), cwd=cwd, capture_output=True, text=True, timeout=timeout)
    if result.returncode != expected:
        raise AssertionError((command, result.returncode, result.stdout[-8000:], result.stderr[-8000:]))
    return result.stdout


def native(directory, source, language, inputs, width=None, boolean=False, typed=True):
    def literal(value):
        if boolean:
            return value
        return value + ('L' if language == 'java' and width == 64 else 'n' if language == 'bun' else '')
    calls = [', '.join(map(literal, values)) for values in inputs]
    if language == 'java':
        (directory / 'ScalarFixture.java').write_text(source)
        harness = 'class NativeHarness { public static void main(String[] args) { ' + ''.join(
            f'System.out.println(ScalarFixture.calculate({call}));' for call in calls) + ' } }'
        (directory / 'NativeHarness.java').write_text(harness)
        run(['javac', '-d', directory, directory / 'ScalarFixture.java', directory / 'NativeHarness.java'])
        return run(['java', '-cp', directory, 'NativeHarness']).splitlines()
    path = directory / ('native.ts' if typed else 'native.js')
    path.write_text(source + '\n' + '\n'.join(f'console.log(calculate({call}).toString());' for call in calls))
    return run(['bun', 'run', '--no-install', path]).splitlines()


def finite(name, language, source, inputs, **options):
    directory = work / name; directory.mkdir()
    expected = native(directory, source, language, inputs, **options)
    assert len(expected) == len(inputs)
    (directory / 'source').write_text(source)
    scenario = {'schemaVersion': 1, 'fuel': 128, 'cases': [
        {'name': f'case{index}', 'entry': 'calculate', 'arguments': values,
         'expected': {'status': 'returned', 'value': value}}
        for index, (values, value) in enumerate(zip(inputs, expected))]}
    (directory / 'cases.json').write_text(json.dumps(scenario, indent=2))
    report = json.loads(run([formal, 'check', '--language', language, '--source', directory / 'source',
        '--scenario', directory / 'cases.json', '--output', directory / 'Checked'], timeout=300))
    (directory / 'result.json').write_text(json.dumps(report, indent=2))
    assert report['translation'] == 'UNVALIDATED' and report['artifactDataMatchesIR']
    for case in report['cases']:
        assert case['irMatchesExpected'] and case['lean'] == 'PROVED' and case['tlc'] == 'MODEL_CHECKED', report
        assert set(case['leanAxioms']) <= set(report['toolchain']['allowedLeanAxioms'])
    records.append({'name': name, 'scope': 'NATIVE_IR_TLC_LEAN', 'observations': len(inputs)})
    print('PASS', name, 'native/IR/TLC/Lean', flush=True)


def property_check(name, language, source, views, result, ensures, status='PROVED', exit_code=0):
    directory = work / name; directory.mkdir()
    (directory / 'source').write_text(source)
    specification = {'schemaVersion': 1, 'properties': [{'name': name, 'entry': 'calculate',
        'inputViews': views, 'resultView': result, 'requires': 'true', 'ensures': ensures}]}
    (directory / 'properties.json').write_text(json.dumps(specification, indent=2))
    report = json.loads(run([formal, 'check', '--language', language, '--source', directory / 'source',
        '--properties', directory / 'properties.json', '--output', directory / 'Checked', *(['--default-numeric', 'bigint'] if language == 'bun' and 'bigint' not in source and views == ['integer'] else [])], expected=exit_code))
    (directory / 'result.json').write_text(json.dumps(report, indent=2))
    item = report['properties'][0]
    assert report['scope'] == 'ALL_INPUTS_UNDER_PRECONDITIONS' and report['translation'] == 'UNVALIDATED'
    assert item['status'] == status and item['tla'] == 'SPECIFICATION_GENERATED', report
    assert set(item['leanAxioms']) <= set(report['toolchain']['allowedLeanAxioms'])
    if status == 'COUNTEREXAMPLE':
        assert item['lean'] == 'COUNTEREXAMPLE_PROVED' and item['counterexampleTLC'] == 'COUNTEREXAMPLE'
        witness = work / (name + '_native'); witness.mkdir()
        observed = native(witness, source, language, [item['counterexample']], width=32 if language == 'java' else None)
        assert observed == (['-2147483648'] if language == 'java' else ['10000000000000000000000000000000000000001'])
    else:
        assert item['lean'] == 'PROVED'
    records.append({'name': name, 'scope': report['scope'], 'status': status})
    print('PASS', name, status, flush=True)


try:
    versions = {name: run([name, '--version']).strip() for name in ['javac', 'java', 'bun']}
    java = (root / 'Fixtures/Sources/java.source').read_text()
    bun = (root / 'Fixtures/Sources/bun.source').read_text()
    finite('java_long', 'java', java, [['2', '9'], ['9', '2'], ['-3', '4'], [str(-(1 << 63)), '2']], width=64)
    finite('java_int', 'java', java.replace('long', 'int').replace('1L', '1'),
           [['2', '9'], ['9', '2'], [str(-(1 << 31)), '2'], [str((1 << 31) - 1), '0']], width=32)
    for typed in [True, False]:
        source = bun if typed else bun.replace(': bigint', '')
        finite('bun_ts' if typed else 'bun_js', 'bun', source,
               [['2', '9'], ['-3', '4'], [str(10 ** 40), '2']], typed=typed)
    java_bool = 'class ScalarFixture { static boolean calculate(boolean a) { return !a; } }'
    bun_bool = 'function calculate(a: boolean): boolean { return !a; }'
    finite('java_boolean', 'java', java_bool, [['true'], ['false']], boolean=True)
    finite('bun_boolean', 'bun', bun_bool, [['true'], ['false']], boolean=True)
    for width, type in [(32, 'int'), (64, 'long')]:
        property_check(f'java_int{width}_all_inputs', 'java',
            f'class ScalarFixture {{ static {type} calculate({type} a) {{ return a - a; }} }}', ['signed'], 'signed', 'result == 0')
    for typed in [True, False]:
        signature = 'function calculate(a: bigint): bigint' if typed else 'function calculate(a)'
        property_check('bun_ts_all_inputs' if typed else 'bun_js_all_inputs', 'bun',
            signature + ' { return a + 1n; }', ['integer'], 'integer', 'result > arg0')
    property_check('java_boolean_all_inputs', 'java', java_bool, ['boolean'], 'boolean', 'result == !arg0')
    property_check('bun_boolean_all_inputs', 'bun', bun_bool, ['boolean'], 'boolean', 'result == !arg0')
    property_check('java_int_wrap_counterexample', 'java',
        'class ScalarFixture { static int calculate(int a) { return a + 1; } }',
        ['signed'], 'signed', 'result > arg0', status='COUNTEREXAMPLE', exit_code=5)
    property_check('bun_bigint_counterexample', 'bun', 'function calculate(a) { return a; }',
        ['integer'], 'integer', 'result != 10000000000000000000000000000000000000001', status='COUNTEREXAMPLE', exit_code=5)
    rejected = [('java', 'class ScalarFixture { static int hashCode() { return 0; } }'),
                ('java', 'class record { static int calculate() { return 0; } }'),
                ('java', 'class ScalarFixture { static int native(int a) { return a; } }'),
                ('java', 'class ScalarFixture { static long calculate() { return 2147483647 + 1; } }'),
                ('java', 'class ScalarFixture { static int calculate() { return -(2147483648); } }'),
                ('java', 'class ScalarFixture { long calculate(long a) { return a; } }'),
                ('bun', 'function calculate(a: number): number { return a + 1n; }'),
                ('bun', 'function calculate(a) { return a++; }')]
    for index, (language, source) in enumerate(rejected):
        path = work / f'rejected{index}.source'; path.write_text(source)
        output = work / f'Rejected{index}'
        run([formal, 'translate', '--language', language, '--source', path,
             '--output', output, '--draft-unvalidated'], expected=4)
        assert not output.exists()
    profiles = json.loads(run([formal, 'profiles']))
    assert {'java-scalar-v1', 'bun-scalar-v2'} <= {item['profile'] for item in profiles}
    summary = {'status': 'PASSED', 'nativeVersions': versions, 'checks': records, 'noOutputRejections': len(rejected)}
    (work / 'summary.json').write_text(json.dumps(summary, indent=2))
    print(json.dumps(summary, indent=2))
finally:
    if not args.output:
        shutil.rmtree(work)
