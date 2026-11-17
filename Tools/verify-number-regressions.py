#!/usr/bin/env python3
"""Reproduce three source/verifier bugs with native execution and bundled model checks."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--formal', type=Path, required=True)
parser.add_argument('--output', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
formal = args.formal.resolve()
work = args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix='formal-number-regressions-'))
if args.output:
    work.mkdir()
records = []


def run(command, expected=0, cwd=None, env=None, timeout=180):
    result = subprocess.run(list(map(str, command)), cwd=cwd or root, env=env,
                            capture_output=True, text=True, timeout=timeout)
    assert result.returncode == expected, (command, result.returncode, result.stdout[-12000:], result.stderr[-12000:])
    return result


def native(directory, source, arguments):
    path = directory / 'native.ts'
    path.write_text(source + '''
const v = new DataView(new ArrayBuffer(8));
const decode = x => { if (x.startsWith('bits:')) { v.setBigUint64(0, BigInt('0x' + x.slice(5))); return v.getFloat64(0); } return Number(x); };
const encode = x => { if (x === undefined) return 'undefined'; if (Number.isNaN(x)) return 'bits:7ff8000000000000'; v.setFloat64(0, x); return 'bits:' + v.getBigUint64(0).toString(16).padStart(16, '0'); };
console.log(JSON.stringify(''' + json.dumps(arguments) + '''.map(xs => encode(calculate(...xs.map(decode))))));
''')
    node = json.loads(run(['node', '--experimental-strip-types', path]).stdout)
    bun = json.loads(run(['bun', 'run', '--no-install', path]).stdout)
    assert node == bun
    (directory / 'native.json').write_text(json.dumps({'node': node, 'bun': bun}, indent=2))
    return node


def finite(name, source, language, arguments, numeric=None):
    directory = work / name
    directory.mkdir()
    expected = native(directory, source, arguments)
    assert 'undefined' not in expected
    source_path = directory / 'source'
    source_path.write_text(source)
    scenario = {'schemaVersion': 1, 'fuel': 64, 'cases': [
        {'name': f'case{i}', 'entry': 'calculate', 'arguments': values,
         'inputViews': ['number'] * len(values), 'resultView': 'number',
         'expected': {'status': 'returned', 'value': value}}
        for i, (values, value) in enumerate(zip(arguments, expected))]}
    scenario_path = directory / 'cases.json'
    scenario_path.write_text(json.dumps(scenario, indent=2))
    command = [formal, 'check', '--language', language, '--source', source_path,
               '--scenario', scenario_path, '--output', directory / 'Checked']
    if numeric:
        command += ['--default-numeric', numeric]
    report = json.loads(run(command).stdout)
    assert len(report['cases']) == len(arguments) and report['translation'] == 'UNVALIDATED'
    for item in report['cases']:
        assert item['irMatchesExpected'] and item['lean'] == 'PROVED' and item['tlc'] == 'MODEL_CHECKED', report
        assert item['distinctStates'] > 1
        assert set(item['leanAxioms']) <= {'propext', 'Classical.choice', 'Quot.sound'}
    draft = json.loads((directory / 'Checked/report.json').read_text())
    if numeric:
        assert draft['defaultNumeric'] == numeric
    (directory / 'result.json').write_text(json.dumps(report, indent=2))
    records.append({'name': name, 'scope': 'NATIVE_IR_LEAN_TLC', 'observations': len(arguments)})
    print('PASS', name, 'native/IR/Lean/TLC', flush=True)
    return directory


try:
    # Native undefined returns cannot be represented by this scalar IR and must not produce a model.
    for language in ['javascript', 'typescript', 'bun']:
        for index, source in enumerate(['function calculate(){return\r1;}', 'function calculate(){return /*\r*/ 1;}']):
            directory = work / f'cr_rejected_{language}_{index}'
            directory.mkdir()
            assert native(directory, source, [[]]) == ['undefined']
            source_path = directory / 'source'
            source_path.write_text(source)
            for mode in ['translate', 'check']:
                output = directory / mode
                command = [formal, mode, '--language', language, '--source', source_path, '--output', output]
                if mode == 'translate':
                    command += ['--draft-unvalidated']
                else:
                    properties = directory / 'properties.json'
                    properties.write_text(json.dumps({'schemaVersion': 1, 'properties': [{
                        'name': 'wrong_model', 'entry': 'calculate', 'inputViews': [], 'resultView': 'number',
                        'requires': 'true', 'ensures': 'result == 1'}]}))
                    command += ['--properties', properties]
                failure = json.loads(run(command, expected=4).stderr)
                assert failure['code'] == 'SOURCE_PARSE_FAILED' and 'LF or CRLF' in failure['message']
                assert not output.exists()
            records.append({'name': directory.name, 'scope': 'NATIVE_UNDEFINED_REJECTED_WITHOUT_MODEL'})
            print('PASS', directory.name, 'native undefined / no generated model', flush=True)

    values = [['0'], ['-0'], ['NaN'], ['Infinity'], ['-1'], ['0.1']]
    sources = {
        'direct': 'function calculate(a){return +a;}',
        'alias': 'function calculate(a){const b=a;return +b;}',
        'call': 'function calculate(a){return helper(a);} function helper(b){return +b;}',
    }
    for language in ['javascript', 'typescript', 'bun']:
        finite('crlf_' + language, 'function calculate(a){\r\nreturn a;\r\n}', language, values)
        for name, source in sources.items():
            directory = finite('plus_' + language + '_' + name, source, language, values, numeric='bigint')
            program = json.loads((directory / 'Checked/program.json').read_text())
            for function in program['functions']:
                assert function['result'] == {'bits': {'width': 64}}
                assert function['blocks'][0]['parameters'][0]['type'] == {'bits': {'width': 64}}

    for name in ['error-directory', 'ERROR handling']:
        finite(name, 'function calculate(){return 1;}', 'bun', [[]])

    # Both universal success and a real NaN counterexample use the shared SANY audit.
    artifact = work / 'plus_bun_call/Checked'
    for name, condition, expected_status, exit_code in [
        ('identity', 'sameValue(result,arg0)', 'PROVED', 0),
        ('nan_reflexivity', 'result == arg0', 'COUNTEREXAMPLE', 5),
    ]:
        path = work / f'{name}.json'
        path.write_text(json.dumps({'schemaVersion': 1, 'properties': [{
            'name': name, 'entry': 'calculate', 'inputViews': ['number'], 'resultView': 'number',
            'requires': 'true', 'ensures': condition}]}))
        report = json.loads(run([formal, 'check', '--artifact', artifact, '--properties', path], expected=exit_code).stdout)
        item = report['properties'][0]
        assert item['status'] == expected_status and item['tla'] == 'SPECIFICATION_GENERATED'
        assert set(item['leanAxioms']) <= {'propext', 'Classical.choice', 'Quot.sound'}
        if exit_code:
            assert item['lean'] == 'COUNTEREXAMPLE_PROVED' and item['counterexampleTLC'] == 'COUNTEREXAMPLE'
            assert item['counterexample'] == ['bits:7ff8000000000000']
        (work / (name + '-result.json')).write_text(json.dumps(report, indent=2))
        records.append({'name': name, 'scope': report['scope'], 'status': expected_status})
        print('PASS', name, expected_status, flush=True)

    # Pinned SANY can emit a semantic error after module processing and still exit zero.
    diagnostic = work / 'sany-error'
    diagnostic.mkdir()
    (diagnostic / 'tmp').mkdir()
    (diagnostic / 'Invalid.tla').write_text('---- MODULE Invalid ----\nEXTENDS Naturals\nBad == MissingOperator\n====\n')
    tools = formal.parent / 'toolchain'
    result = run([tools / 'java/Contents/Home/bin/java', '-Djava.io.tmpdir=' + str(diagnostic / 'tmp'),
                  '-cp', tools / 'tla2tools.jar', 'tla2sany.SANY', 'Invalid.tla'], cwd=diagnostic)
    output = result.stdout + result.stderr
    assert 'Semantic processing of module Invalid' in output and 'Semantic errors:' in output
    transcript = diagnostic / 'semantic-error.txt'
    transcript.write_text(output)
    run(['swift', 'test', '--filter', 'SANYOutputAuditTests'],
        env={**os.environ, 'FORMAL_SANY_DIAGNOSTIC_FIXTURE': str(transcript)})
    records.append({'name': 'zero_exit_sany_error_rejected', 'scope': 'PINNED_SANY_AND_OUTPUT_AUDIT'})
    print('PASS zero-exit SANY semantic error rejected', flush=True)

    summary = {'status': 'PASSED', 'checks': records,
               'nativeVersions': {tool: run([tool, '--version']).stdout.strip() for tool in ['node', 'bun']}}
    (work / 'summary.json').write_text(json.dumps(summary, indent=2))
    print(json.dumps(summary, indent=2))
finally:
    if not args.output:
        shutil.rmtree(work)
