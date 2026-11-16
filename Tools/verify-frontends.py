#!/usr/bin/env python3
"""Finite native/IR/Lean/TLC comparisons for versioned source profiles, not semantic certification."""
import argparse
import signal
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
all_languages = ['swift', 'rust', 'c', 'cpp', 'go', 'typescript', 'javascript', 'python', 'java', 'bun']
parser = argparse.ArgumentParser()
parser.add_argument('--languages', nargs='+', choices=all_languages, default=all_languages)
parser.add_argument('--native-only', action='store_true')
options = parser.parse_args()
languages = options.languages
math_languages = {'typescript', 'javascript', 'python', 'bun'}

def run(args, cwd=root, environment=None, timeout=120, expected=0):
    result = subprocess.run([str(x) for x in args], cwd=cwd, env=environment, timeout=timeout,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if result.returncode != expected:
        Path('/tmp/formal-frontend-tool-failure.log').write_text(result.stdout)
        raise AssertionError((args, result.returncode, result.stdout[-6000:]))
    return result.stdout

def bits(n):
    return '<<' + ', '.join(str((n >> i) & 1) for i in range(64)) + '>>'

def tla_value(n, mathematical):
    return f'ParseInteger("{n}")' if mathematical else f'Bits(64, {bits(n)})'

def lean_value(n, mathematical):
    return f'(.integer ({n}))' if mathematical else f'(.bits 64 {n % (1 << 64)})'

def c_literal(n):
    return '(-9223372036854775807LL - 1LL)' if n == -(1 << 63) else str(n) + 'LL'

def native(language, source, cases, directory, overflow=False):
    suffix = {'swift': 'swift', 'rust': 'rs', 'c': 'c', 'cpp': 'cpp', 'go': 'go',
              'typescript': 'ts', 'javascript': 'js', 'python': 'py', 'java': 'java', 'bun': 'ts'}[language]
    calls = [f'calculate({a}, {b})' for a, b, _ in cases]
    if language == 'swift': harness = '\n'.join(f'print({c})' for c in calls)
    elif language == 'rust': harness = 'fn main() { ' + ''.join(f'println!("{{}}", {c});' for c in calls) + ' }'
    elif language in {'c', 'cpp'}:
        calls = [f'calculate({c_literal(a)}, {c_literal(b)})' for a, b, _ in cases]
        harness = '#include <stdio.h>\nint main(void) {' + ''.join(f'printf("%lld\\n", (long long){c});' for c in calls) + 'return 0;}'
    elif language == 'go': harness = 'func main() { ' + ';'.join(f'println({c})' for c in calls) + ' }'
    elif language == 'java':
        harness = 'class NativeHarness { public static void main(String[] args) { ' + ''.join(f'System.out.println(ScalarFixture.calculate({a}L, {b}L));' for a, b, _ in cases) + ' } }'
    elif language in math_languages - {'python'}:
        harness = '\n'.join(f'console.log(calculate({a}n, {b}n).toString());' for a, b, _ in cases)
    else: harness = '\n'.join(f'print({c})' for c in calls)
    path = directory / f'main.{suffix}'
    path.write_text(source + '\n' + harness + '\n')
    binary = directory / 'native'
    if language == 'swift': run(['swiftc', path, '-o', binary]); command = [binary]
    elif language == 'rust': run(['rustc', '--edition=2021', '-C', 'overflow-checks=yes', path, '-o', binary]); command = [binary]
    elif language in {'c', 'cpp'}:
        run(['clang' if language == 'c' else 'clang++', '-std=c11' if language == 'c' else '-std=c++20', '-Wall', '-Werror', *(['-fsanitize=undefined', '-fno-sanitize-recover=all'] if overflow else []), path, '-o', binary]); command = [binary]
    elif language == 'go': run(['go', 'build', '-o', binary, path]); command = [binary]
    elif language == 'typescript':
        # Type-check with the pinned compiler, then execute its actual JavaScript output.
        run(['node', tsc, '--target', 'ES2020', '--strict', path]); command = ['node', path.with_suffix('.js')]
    elif language == 'javascript': command = ['node', path]
    elif language == 'bun': command = ['bun', 'run', '--no-install', path]
    elif language == 'java':
        run(['javac', '-d', directory, path]); command = ['java', '-cp', directory, 'NativeHarness']
    else: command = ['python3', path]
    if overflow:
        result = subprocess.run([str(x) for x in command], cwd=directory, timeout=20, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        assert (result.returncode == -signal.SIGTRAP if language == 'swift' else result.returncode != 0 and 'overflow' in result.stdout.lower()), (language, result.returncode, result.stdout[-2000:])
        return
    actual = run(command).splitlines()
    assert actual == [str(c[2]) for c in cases], (language, actual, cases)

with tempfile.TemporaryDirectory(prefix='formal-frontends-') as temporary:
    output = Path(temporary)
    run(['swift', 'test', '--filter', 'SourceFrontendTests'], environment={**os.environ, 'FORMAL_FRONTEND_OUTPUT': str(output)}, timeout=180)
    environment = {**os.environ, 'PATH': str(lean) + os.pathsep + os.environ['PATH']}
    for language in languages:
        directory = output / language
        source = (root / f'Fixtures/Sources/{language}.source').read_text()
        observations = [[int(x) for x in row] for row in json.loads((directory / 'observations.json').read_text())]
        native(language, source, observations, directory)
        if language in {'rust', 'c', 'cpp', 'swift'}:
            native(language, source, [[-(1 << 63), 1, None]], directory, overflow=True)
        if language in {'go', 'java'}:
            native(language, source, [[-(1 << 63), 1, -(1 << 63)+1]], directory)
        if options.native_only:
            print(f'{language}: native result and applicable overflow checks passed.', flush=True)
            continue
        run([lean / 'lake', 'build'], cwd=directory / 'lean', environment=environment, timeout=180)
        mathematical = language in math_languages
        checks = list(observations)
        if mathematical:
            a = 10**40; b = 2 * 10**40
            large = [a, b, a*b+1]
            native(language, source, [large], directory)
            checks.append(large)
        theorem_source = '''import Generated.Program
open SwiftFormal Generated

def observe (actual : List Value) : Option Status := do
  let state ← initial program "calculate" actual
  match evaluate program 200 state with
  | .terminal final => some final.status
  | _ => none
'''
        for i, (a, b, expected) in enumerate(checks):
            theorem_source += f'\ntheorem case{i} : observe [{lean_value(a, mathematical)}, {lean_value(b, mathematical)}] = some (.returned {lean_value(expected, mathematical)}) := by rfl\n#print axioms case{i}\n'
        if language in {'rust', 'c', 'cpp', 'swift'}:
            kind = '.trapped "integer overflow"' if language == 'swift' else '.failed .panic "integer overflow"' if language == 'rust' else '.failed .undefinedBehavior "signed integer overflow"'
            theorem_source += f'\ntheorem overflow : observe [{lean_value(-(1<<63), False)}, {lean_value(1, False)}] = some ({kind}) := by rfl\n#print axioms overflow\n'
        theorem = directory / 'lean/FiniteChecks.lean'
        theorem.write_text(theorem_source)
        audit = run([lean / 'lake', 'env', 'lean', theorem], cwd=directory / 'lean', environment=environment)
        assert 'sorry' not in audit.lower(), audit
        declarations = 0
        for line in audit.splitlines():
            if 'does not depend on any axioms' in line: declarations += 1
            if 'depends on axioms:' in line:
                declarations += 1
                names = set(x.strip() for x in re.search(r'\[(.*)\]', line).group(1).split(','))
                assert names <= set(lock['allowedLeanAxioms']), line
        assert declarations == len(checks) + (language in {'rust', 'c', 'cpp', 'swift'}), audit
        # Use a finite deterministic trace, checking the result and eventual termination.
        scenarios = [(a, b, expected, 'returned') for a, b, expected in checks]
        if language in {'rust', 'c', 'cpp', 'swift'}:
            scenarios.append((-(1<<63), 1, None, {'rust':'panic', 'swift':'trapped'}.get(language, 'undefinedBehavior')))
        if language in {'go', 'java'}: scenarios.append((-(1<<63), 1, -(1<<63)+1, 'returned'))
        for i, (a, b, expected, status) in enumerate(scenarios):
            name = f'Case{i}'
            condition = f'state.status \\in {{"running", "{status}"}}'
            if expected is not None:
                condition += f' /\\ (state.status = "returned" => state.result = {tla_value(expected, mathematical)})'
            (directory / f'tla/{name}.tla').write_text(f'''---- MODULE {name} ----
EXTENDS SwiftFormalRuntime
VARIABLE state
P == INSTANCE Program WITH EntrySymbol <- "calculate", EntryArguments <- <<{tla_value(a, mathematical)}, {tla_value(b, mathematical)}>>, state <- state
Init == P!Init
Next == P!Next
Expected == {condition}
====
''')
            (directory / f'tla/{name}.cfg').write_text('INIT Init\nNEXT Next\nINVARIANT Expected\n')
            sany = run(['java', '-Xss16m', '-Xmx512m', '-cp', jar, 'tla2sany.SANY', f'{name}.tla'], cwd=directory / 'tla')
            assert 'error' not in sany.lower(), sany
            tlc = run(['java', '-Xss16m', '-Xmx512m', '-cp', jar, 'tlc2.TLC', '-workers', '1', '-cleanup', '-dump', 'dot', 'trace.dot', name], cwd=directory / 'tla')
            assert 'Model checking completed. No error has been found.' in tlc, tlc
            assert int(re.findall(r'(\d+) distinct states found', tlc)[-1]) > 1, tlc
            graph = (directory / 'tla/trace.dot').read_text()
            assert f'\\"{status}\\"' in graph, graph[-2000:]
        print(f'{language}: native/IR parity, Lean kernel checks, SANY/TLC results and terminal reachability passed.', flush=True)
print(f'Finite checks passed for {languages}. General source-to-IR proof and Actor support remain incomplete.')
