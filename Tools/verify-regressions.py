#!/usr/bin/env python3
"""Execute four frontend regressions through native tools, CLI, IR observations, TLC, and Lean."""
import argparse
import hashlib
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
store = Path(os.environ.get('FORMAL_TOOLS_ROOT', root / '.tools')).resolve()
lean = store / 'lean-4.35.0-darwin_aarch64/bin'
jar = store / 'tla2tools.jar'
tsc = store / 'typescript/node_modules/typescript/bin/tsc'
lock = json.loads((root / 'Tools/toolchain-artifacts.lock.json').read_text())
with jar.open('rb') as handle:
    assert hashlib.file_digest(handle, 'sha256').hexdigest() == lock['tla']['sha256']
assert json.loads((tsc.parent.parent / 'package.json').read_text())['version'] == '5.9.3'
formal = None
parser = argparse.ArgumentParser()
parser.add_argument('--fixtures', nargs='+', help='Verify only the named positive fixtures')
parser.add_argument('--skip-rejections', action='store_true', help='Reuse unchanged rejection evidence')
options = parser.parse_args()


def execute(arguments, cwd=root, environment=None, timeout=120, success=True):
    result = subprocess.run([str(arg) for arg in arguments], cwd=cwd, env=environment, timeout=timeout,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if success and result.returncode != 0:
        raise AssertionError((arguments, result.returncode, result.stdout[-8000:]))
    return result


def native(language, source, observations, directory):
    suffix = {'c': 'c', 'cpp': 'cpp', 'go': 'go', 'javascript': 'js', 'typescript': 'ts'}[language]
    calls = []
    for entry, left, right, kind, _, output_kind in observations:
        if language in {'javascript', 'typescript'}:
            calls.append(f'console.log({entry}({left}n, {right}n).toString());')
        elif language == 'go':
            calls.append(f'println({entry}({left}, {right}))')
        else:
            suffix_literal = 'ULL' if kind == 'unsigned' else 'LL'
            expression = f'{entry}({left}{suffix_literal}, {right}{suffix_literal})'
            calls.append(f'printf("%lld\\n", (long long){expression});')
    if language == 'go': harness = 'func main() { ' + '; '.join(calls) + ' }'
    elif language in {'c', 'cpp'}: harness = '#include <stdio.h>\nint main(void) { ' + ' '.join(calls) + ' return 0; }'
    else: harness = '\n'.join(calls)
    path = directory / f'native.{suffix}'
    path.write_text(source + '\n' + harness + '\n')
    binary = directory / 'native'
    if language in {'c', 'cpp'}:
        execute(['clang' if language == 'c' else 'clang++', '-std=c11' if language == 'c' else '-std=c++20',
                 '-fsanitize=undefined', '-fno-sanitize-recover=all', path, '-o', binary])
        command = [binary]
    elif language == 'go':
        execute(['go', 'build', '-o', binary, path]); command = [binary]
    elif language == 'typescript':
        execute(['node', tsc, '--target', 'ES2020', '--strict', path]); command = ['node', path.with_suffix('.js')]
    else: command = ['node', path]
    result = execute(command)
    assert result.stdout.splitlines() == [row[4] for row in observations], (language, result.stdout, observations)


def reject_cli(language, source, directory, diagnostic):
    path = directory / 'rejected.source'
    path.write_text(source)
    output = directory / 'Rejected'
    result = subprocess.run([str(formal), 'translate', '--language', language, '--source', str(path),
                             '--output', str(output), '--draft-unvalidated'], timeout=30,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert result.returncode == 4 and not result.stdout, (result.returncode, result.stdout, result.stderr)
    report = json.loads(result.stderr)
    assert report['code'] == 'SOURCE_PARSE_FAILED' and diagnostic in report['message'], report
    assert not output.exists() and not list(directory.glob('.formal-*')), directory


def negative_regressions(output):
    for language in ['c', 'cpp', 'javascript', 'typescript']:
        directory = output / f'negative-{language}'; directory.mkdir()
        source = (root / f'Fixtures/Regressions/spaced-{language}.source').read_text()
        # Verify the original counterexample in its native language, then require explicit rejection.
        updated = source.replace('- -a', '--a')
        native(language, updated, [['f', '9', '2', 'signed', '8', 'signed']], directory)
        reject_cli(language, updated, directory, 'Unsupported update operator')
        literal = '0n' if language in {'javascript', 'typescript'} else '0LL'
        binding = 'const x' if language in {'javascript', 'typescript'} else 'const ' + ('std::int64_t' if language == 'cpp' else 'int64_t') + ' x'
        updated = source.replace('return - -a;', f'{binding} = a---b; return a + x * {literal};')
        native(language, updated, [['f', '9', '2', 'signed', '8', 'signed']], directory)
        reject_cli(language, updated, directory, 'Unsupported update operator')
    for language in ['c', 'cpp']:
        directory = output / f'forward-{language}'; directory.mkdir()
        type_name = 'int64_t' if language == 'c' else 'std::int64_t'
        header = 'stdint.h' if language == 'c' else 'cstdint'
        source = f'#include <{header}>\n{type_name} f({type_name} a, {type_name} b) {{ return g(a, b); }}\n{type_name} g({type_name} a, {type_name} b) {{ return a + b; }}\n'
        path = directory / ('forward.c' if language == 'c' else 'forward.cpp'); path.write_text(source)
        rejected = execute(['clang' if language == 'c' else 'clang++', '-std=c11' if language == 'c' else '-std=c++20', '-fsyntax-only', path], success=False)
        assert rejected.returncode != 0 and 'undeclared' in rejected.stdout, rejected.stdout
        reject_cli(language, source, directory, 'precedes its declaration')
    directory = output / 'deep-rejection'; directory.mkdir()
    expression = 'a'
    for _ in range(50): expression = '(' + expression + ')' + '+a' * 120
    source = 'function f(a) { return ' + expression + '; }\n'
    assert len(source.encode()) == 12_128
    path = directory / 'deep.js'; path.write_text(source + '\nconsole.log(f(1n).toString());\n')
    assert execute(['node', path]).stdout.strip() == '6001'
    reject_cli('javascript', source, directory, 'depth limit exceeded')
    for i, (parameter_type, result_type, expression) in enumerate([
        ('int64', 'int64', '9223372036854775807 + 1'),
        ('int64', 'int64', 'a + (9223372036854775807 + 1)'),
        ('uint64', 'bool', 'a < -1'),
    ]):
        directory = output / f'go-rejection-{i}'; directory.mkdir()
        source = f'package main\nfunc f(a {parameter_type}, b {parameter_type}) {result_type} {{ return {expression} }}\n'
        path = directory / 'native.go'; path.write_text(source + 'func main() { println(f(9, 2)) }\n')
        rejected = execute(['go', 'build', '-o', directory / 'native', path], success=False)
        assert rejected.returncode != 0 and 'overflows' in rejected.stdout, rejected.stdout
        reject_cli('go', source, directory, 'out of range')
    print('Negative regressions: native counterexamples checked; CLI rejects updates, forward calls, deep AST, and invalid Go conversions without artifacts.', flush=True)


def bits(value, width=64):
    return '<<' + ','.join(str((int(value) >> index) & 1) for index in range(width)) + '>>'


def lean_value(value, kind):
    if kind == 'integer': return f'(.integer ({value}))'
    if kind == 'boolean': return f'(.bits 1 {1 if value == "true" else 0})'
    return f'(.bits 64 {int(value) % (1 << 64)})'


def tla_value(value, kind):
    if kind == 'integer': return f'ParseInteger("{value}")'
    if kind == 'boolean': return f'Bits(1,<<{1 if value == "true" else 0}>>)'
    return f'Bits(64,{bits(value)})'


def verify_backends(directory, observations, environment):
    execute([lean / 'lake', 'build'], cwd=directory / 'lean', environment=environment, timeout=180)
    proof = '''import Generated.Program
open SwiftFormal Generated
set_option maxRecDepth 8192
set_option maxHeartbeats 1000000

def observe (entry : String) (actual : List Value) : Option Status := do
  let start ← initial program entry actual
  match evaluate program 512 start with
  | .terminal final => some final.status
  | _ => none
'''
    for i, (entry, left, right, kind, expected, result_kind) in enumerate(observations):
        proof += f'\ntheorem case{i} : observe "{entry}" [{lean_value(left, kind)}, {lean_value(right, kind)}] = some (.returned {lean_value(expected, result_kind)}) := by rfl\n#print axioms case{i}\n'
    path = directory / 'lean/Regressions.lean'; path.write_text(proof)
    audit = execute([lean / 'lake', 'env', 'lean', path], cwd=directory / 'lean', environment=environment).stdout
    assert 'sorry' not in audit.lower(), audit
    count = 0
    for line in audit.splitlines():
        if 'does not depend on any axioms' in line: count += 1
        if 'depends on axioms:' in line:
            count += 1
            names = {name.strip() for name in re.search(r'\[(.*)\]', line).group(1).split(',')}
            assert names <= set(lock['allowedLeanAxioms']), line
    assert count == len(observations), audit
    for i, (entry, left, right, kind, expected, result_kind) in enumerate(observations):
        name = f'Regression{i}'
        (directory / f'tla/{name}.tla').write_text(f'''---- MODULE {name} ----
EXTENDS SwiftFormalRuntime
VARIABLE state
P == INSTANCE Program WITH EntrySymbol <- "{entry}", EntryArguments <- <<{tla_value(left, kind)}, {tla_value(right, kind)}>>, state <- state
Init == P!Init
Next == P!Next
Expected == state.status \\in {{"running", "returned"}} /\\ (state.status = "returned" => state.result = {tla_value(expected, result_kind)})
====
''')
        (directory / f'tla/{name}.cfg').write_text('INIT Init\nNEXT Next\nINVARIANT Expected\n')
        sany = execute(['java', '-Xss16m', '-Xmx512m', '-cp', jar, 'tla2sany.SANY', f'{name}.tla'], cwd=directory / 'tla').stdout
        assert 'error' not in sany.lower(), sany
        tlc = execute(['java', '-Xss16m', '-Xmx512m', '-cp', jar, 'tlc2.TLC', '-workers', '1', '-cleanup', '-dump', 'dot', 'trace.dot', name], cwd=directory / 'tla').stdout
        assert 'Model checking completed. No error has been found.' in tlc, tlc
        assert int(re.findall(r'(\d+) distinct states found', tlc)[-1]) > 1, tlc
        assert '\\"returned\\"' in (directory / 'tla/trace.dot').read_text()


with tempfile.TemporaryDirectory(prefix='formal-regressions-') as temporary:
    output = Path(temporary)
    environment = {**os.environ, 'FORMAL_REGRESSION_OUTPUT': str(output), 'PATH': str(lean) + os.pathsep + os.environ['PATH']}
    execute(['swift', 'test', '--filter', 'FrontendRegressionTests'], environment=environment, timeout=180)
    # Keep SwiftPM lock/progress diagnostics on stderr, separate from the path on stdout.
    path_query = subprocess.run(['swift', 'build', '--show-bin-path'], cwd=root, capture_output=True, text=True, timeout=30, check=True)
    formal = Path(path_query.stdout.strip()) / 'formal'
    assert formal.is_file(), formal
    if not options.skip_rejections: negative_regressions(output)
    available = {directory.name for directory in output.iterdir() if (directory / 'observations.json').is_file()}
    if options.fixtures: assert set(options.fixtures) <= available, (options.fixtures, available)
    count = 0
    for directory in sorted(output.iterdir()):
        if not (directory / 'observations.json').is_file(): continue
        if options.fixtures and directory.name not in options.fixtures: continue
        language = directory.name.rsplit('-', 1)[1]
        source = (directory / 'source.txt').read_text()
        observations = json.loads((directory / 'observations.json').read_text())
        native(language, source, observations, directory)
        draft = directory / 'Draft'
        report = execute([formal, 'translate', '--language', language, '--source', directory / 'source.txt', '--output', draft, '--draft-unvalidated'])
        assert json.loads(report.stdout)['status'] == 'DRAFT_UNVALIDATED'
        for path in ['lean/Generated/Program.lean', 'tla/Program.tla']:
            assert (directory / path).read_bytes() == (draft / path).read_bytes(), path
        verify_backends(draft, observations, environment)
        count += len(observations)
        print(f'{directory.name}: {len(observations)} native/IR/TLA+/Lean results agree.', flush=True)
    assert count > 0
    rejection_status = 'reused' if options.skip_rejections else 'passed without artifacts'
    print(f'Verified {count} native/IR/TLA+/Lean results; rejection checks: {rejection_status}.', flush=True)
