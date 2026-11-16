#!/usr/bin/env python3
"""Exercise a real portable distribution without host verification tool dependencies."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser()
parser.add_argument('--distribution', type=Path, required=True)
args = parser.parse_args()
distribution = args.distribution.resolve()
package = Path(__file__).resolve().parents[1]
measurements = []

def run(executable, arguments, environment, expected=0, timeout=180):
    started = time.monotonic()
    result = subprocess.run([str(executable), *map(str, arguments)], env=environment,
                            capture_output=True, text=True, timeout=timeout)
    measurements.append({'command': arguments[0], 'seconds': round(time.monotonic() - started, 3), 'exit': result.returncode})
    if result.returncode != expected:
        try:
            report = json.loads(result.stdout)
            directory = Path(report['runDirectory'])
            for path in sorted(directory.rglob('*')):
                if path.suffix in ['.stdout', '.stderr'] and path.stat().st_size:
                    print(path.name, path.read_text()[:6000], file=__import__('sys').stderr)
        except (ValueError, KeyError):
            pass
    assert result.returncode == expected, (arguments, result.returncode, result.stdout, result.stderr)
    return result

with tempfile.TemporaryDirectory(prefix='formal-distribution-') as temporary:
    work = Path(temporary)
    poison = work / 'poison'; poison.mkdir()
    for name in ['java', 'javac', 'bun', 'lean', 'lake', 'swift', 'swiftc', 'curl', 'zstd']:
        path = poison / name
        path.write_text('#!/bin/sh\nprintf "HOST TOOL MUST NOT RUN\\n" >&2\nexit 99\n')
        path.chmod(0o755)
    environment = {**os.environ, 'PATH': str(poison), 'JAVA_HOME': '/missing-java',
                   'JAVA_TOOL_OPTIONS': '-invalid-option', 'JDK_JAVA_OPTIONS': '-invalid-option',
                   '_JAVA_OPTIONS': '-invalid-option', 'LEAN_SYSROOT': '/missing-lean',
                   'LEAN_PATH': '/missing-lean', 'ELAN_TOOLCHAIN': 'missing'}
    linked = work / 'LinkedSource'; linked.mkdir()
    shutil.copy2(distribution / 'formal', linked / 'formal')
    for bundle in distribution.glob('*.bundle'):
        shutil.copytree(bundle, linked / bundle.name)
    (linked / 'toolchain').symlink_to(distribution / 'toolchain', target_is_directory=True)
    packaged = work / 'CopiedTools'
    run(linked / 'formal', ['package', '--output', packaged], environment)
    assert (packaged / 'toolchain').is_dir() and not (packaged / 'toolchain').is_symlink()
    shutil.rmtree(linked)
    prefix = work / 'OriginalPrefix'
    run(packaged / 'formal', ['install', '--prefix', prefix], environment)
    run(packaged / 'formal', ['install', '--prefix', prefix], environment, expected=2)
    moved = work / 'MovedPrefix'; prefix.rename(moved)
    binary = moved / 'bin/formal'
    policy = json.loads(run(binary, ['toolchain'], environment).stdout)
    assert policy['java']['version'] == '21.0.13+9.0.LTS'
    environment['PATH'] = str(moved / 'bin') + os.pathsep + str(poison)
    # PATH invocation exercises executable discovery through the relative installed symlink.
    assert run('formal', ['--version'], environment).stdout == 'formal 0.4.0\n'
    binary = 'formal'
    source_by_language = {
        'python': 'def calculate(a: int, b: int) -> int:\n    return a + b\n',
        'javascript': 'function calculate(a, b) { return a + b + 0n; }',
        'typescript': 'function calculate(a: bigint, b: bigint): bigint { return a + b; }',
        'swift': 'func calculate(_ a: Int64, _ b: Int64) -> Int64 { return a + b }',
        'rust': 'fn calculate(a: i64, b: i64) -> i64 { return a + b; }',
        'c': '#include <stdint.h>\nint64_t calculate(int64_t a, int64_t b) { return a + b; }',
        'cpp': '#include <cstdint>\nint64_t calculate(int64_t a, int64_t b) { return a + b; }',
        'java': 'class ScalarFixture { static long calculate(long a, long b) { return a + b; } }',
        'bun': 'function calculate(a: bigint, b: bigint): bigint { return a + b; }',
        'go': 'package main\nfunc calculate(a int64, b int64) int64 { return a + b }',
    }
    def scenario(path, arguments, expected, fuel=512):
        path.write_text(json.dumps({'schemaVersion': 1, 'fuel': fuel, 'cases': [
            {'name': 'case0', 'entry': 'calculate', 'arguments': arguments, 'expected': expected}]}))
    cases = work / 'cases.json'
    outputs = {}
    for language, source in source_by_language.items():
        source_path = work / (language + '.source'); source_path.write_text(source)
        expected = {'status': 'returned', 'value': '11'}
        scenario(cases, ['2', '9'], expected)
        output = work / language
        report = json.loads(run(binary, ['check', '--language', language, '--source', source_path,
                                        '--scenario', cases, '--output', output], environment).stdout)
        assert report['translation'] == 'UNVALIDATED' and report['scope'] == 'FINITE_GENERATED_MODEL_CASES'
        assert report['artifactDataMatchesIR'] and report['cases'][0]['irMatchesExpected']
        assert report['cases'][0]['tlc'] == 'MODEL_CHECKED' and report['cases'][0]['lean'] == 'PROVED', report
        assert report['cases'][0]['distinctStates'] > 1
        assert set(report['cases'][0]['leanAxioms']) <= set(policy['allowedLeanAxioms'])
        outputs[language] = output
    properties = work / 'properties.json'
    properties.write_text(json.dumps({'schemaVersion': 1, 'properties': [{
        'name': 'monotone_addition', 'entry': 'calculate', 'inputViews': ['integer', 'integer'],
        'resultView': 'integer', 'requires': 'arg1 >= 0', 'ensures': 'result >= arg0'}]}))
    universal = json.loads(run(binary, ['check', '--artifact', outputs['python'], '--properties', properties], environment).stdout)
    assert universal['scope'] == 'ALL_INPUTS_UNDER_PRECONDITIONS'
    assert universal['properties'][0]['status'] == 'PROVED' and universal['properties'][0]['tla'] == 'SPECIFICATION_GENERATED'
    assert universal['translation'] == 'UNVALIDATED'
    number_source = work / 'number.ts'
    number_source.write_text('function calculate(a: number, b: number) { return a + b; }')
    cases.write_text(json.dumps({'schemaVersion': 1, 'fuel': 32, 'cases': [{
        'name': 'rounding', 'entry': 'calculate', 'arguments': ['0.1', '0.2'],
        'inputViews': ['number', 'number'], 'resultView': 'number',
        'expected': {'status': 'returned', 'value': 'bits:3fd3333333333334'}}]}))
    number_output = work / 'number'
    number_report = json.loads(run(binary, ['check', '--language', 'bun', '--source', number_source,
        '--scenario', cases, '--output', number_output], environment).stdout)
    assert number_report['cases'][0]['irMatchesExpected']
    assert number_report['cases'][0]['lean'] == 'PROVED' and number_report['cases'][0]['tlc'] == 'MODEL_CHECKED'
    properties.write_text(json.dumps({'schemaVersion': 1, 'properties': [{
        'name': 'ieee_sum', 'entry': 'calculate', 'inputViews': ['number', 'number'],
        'resultView': 'number', 'requires': 'true', 'ensures': 'sameValue(result, arg0 + arg1)'}]}))
    number_property = json.loads(run(binary, ['check', '--artifact', number_output, '--properties', properties], environment).stdout)
    assert number_property['properties'][0]['status'] == 'PROVED'
    scenario(cases, ['2', '9'], {'status': 'returned', 'value': '12'})
    counterexample = json.loads(run(binary, ['check', '--artifact', outputs['python'], '--scenario', cases], environment, expected=5).stdout)
    assert counterexample['cases'][0]['tlc'] == 'COUNTEREXAMPLE'
    assert counterexample['cases'][0]['lean'] == 'UNPROVED'
    assert not counterexample['cases'][0]['irMatchesExpected']
    scenario(cases, ['2', '9'], {'status': 'returned', 'value': '11'}, fuel=1)
    bounded = json.loads(run(binary, ['check', '--artifact', outputs['python'], '--scenario', cases], environment, expected=6).stdout)
    assert bounded['cases'][0]['tlc'] == 'UNKNOWN' and bounded['cases'][0]['lean'] == 'UNKNOWN'
    scenario(cases, ['9223372036854775807', '1'], {'status': 'trapped'})
    failure = json.loads(run(binary, ['check', '--artifact', outputs['swift'], '--scenario', cases], environment).stdout)
    assert failure['cases'][0]['tlc'] == 'MODEL_CHECKED' and failure['cases'][0]['lean'] == 'PROVED'
    scenario(cases, ['999999999999999999999999999999', '1'], {'status': 'returned', 'value': '1000000000000000000000000000000'})
    bigint = json.loads(run(binary, ['check', '--artifact', outputs['python'], '--scenario', cases], environment).stdout)
    assert bigint['cases'][0]['tlc'] == 'MODEL_CHECKED' and bigint['cases'][0]['lean'] == 'PROVED'
    scenario(cases, ['2', '9'], {'status': 'returned', 'value': '11'})
    runtime = outputs['python'] / 'lean/SwiftFormal/Runtime.lean'
    runtime.write_text(runtime.read_text() + '\n-- mutated\n')
    tampered = run(binary, ['check', '--artifact', outputs['python'], '--scenario', cases], environment, expected=4)
    assert json.loads(tampered.stderr)['code'] == 'INTEGRITY_MISMATCH'
    # Tamper only a clone-owned file; the input distribution remains intact.
    jar = moved / 'libexec/formal/0.4.0/toolchain/tla2tools.jar'
    with jar.open('r+b') as handle:
        handle.seek(0); handle.write(b'BAD!')
    tool_tamper = run(binary, ['toolchain'], environment, expected=4)
    assert json.loads(tool_tamper.stderr)['code'] == 'INTEGRITY_MISMATCH'
    print(json.dumps({'status': 'PASSED', 'scenarios': ['ten profiles', 'counterexample', 'fuel bound',
          'overflow expectation', 'BigInt', 'runtime tamper', 'tool tamper', 'offline install', 'relocation', 'no clobber', 'linked toolchain packaging', 'all-input property', 'Number rounding', 'Number all-input sum'],
          'measurements': measurements}, indent=2))
