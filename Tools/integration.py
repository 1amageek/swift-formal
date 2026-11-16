#!/usr/bin/env python3
"""Exercise actual CLI process behavior without treating integrity as semantics."""
import hashlib
import json
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
output = subprocess.run(['swift', 'build', '--show-bin-path'], cwd=root, text=True,
                        capture_output=True, timeout=30, check=True).stdout.strip()
executable = Path(output) / 'swift-formal'

def run(arguments, expected):
    result = subprocess.run([str(executable), *arguments], cwd=root, text=True,
                            capture_output=True, timeout=20)
    assert result.returncode == expected, (arguments, result.returncode, result.stdout, result.stderr)
    return result

assert 'swift-formal' in run(['--help'], 0).stdout
report = json.loads(run(['doctor', '--toolchain-lock', str(root / 'toolchain.lock.json')], 0).stdout)
assert report['compilerIdentityMatches'] and not report['generationSupported']
with tempfile.TemporaryDirectory(prefix='formal-integration-') as temporary:
    work = Path(temporary)
    lock = json.loads((root / 'toolchain.lock.json').read_text())
    changed = {**lock, 'compilerVersion': 'different compiler'}
    (work / 'wrong-lock.json').write_text(json.dumps(changed))
    result = run(['doctor', '--toolchain-lock', str(work / 'wrong-lock.json')], 2)
    assert json.loads(result.stderr)['code'] == 'TOOLCHAIN_MISMATCH'
    source = work / 'Inventory.swift'
    source.write_text('actor Inventory {\n private func reserve() -> Bool { true }\n}')
    index = json.loads(run(['index', '--source', str(source)], 0).stdout)
    assert any('reserve' in declaration['name'] for declaration in index['declarations'])
    assert not index['providesExecutionSemantics']
    source.write_text('actor Inventory { private func reserve() -> Bool { true } }')
    partial = json.loads(run(['index', '--source', str(source)], 0).stdout)
    assert not partial['completeDeclarationCoverage'] and partial['limitations']
    source.write_text('actor Inventory { func broken(')
    run(['index', '--source', str(source)], 4)
    bundle = work / 'Input.silbundle'
    (bundle / 'modules').mkdir(parents=True)
    (bundle / 'toolchain.lock.json').write_text(json.dumps(lock))
    context = {key: lock[key] for key in ['schemaVersion', 'profileID', 'compilerVersion', 'targetTriple',
                                        'languageMode', 'sdkVersion', 'silStage', 'optimization', 'ownership']}
    context.update(dataLayout='fixture-layout', standardLibraryID='fixture-stdlib',
                   runtimeID='fixture-runtime', compilerArguments=['-emit-sil', '-Onone'])
    (bundle / 'build-context.json').write_text(json.dumps(context))
    sil = b'sil_stage canonical\n// Opaque metadata test, not semantic verification.\n'
    module = bundle / 'modules' / 'Main.sil'
    module.write_bytes(sil)
    manifest = dict(schemaVersion=1, profileID=lock['profileID'], exclusions=[],
                    modules=[dict(id='Main', path='modules/Main.sil', sha256=hashlib.sha256(sil).hexdigest(), dependencies=[])],
                    entryPoints=[dict(moduleID='Main', symbol='$s4Main5entryyyF')])
    (bundle / 'manifest.json').write_text(json.dumps(manifest))
    arguments = ['inspect-bundle', '--bundle', str(bundle), '--toolchain-lock', str(root / 'toolchain.lock.json')]
    inspection = json.loads(run(arguments, 0).stdout)
    assert inspection['integrityChecked'] and not inspection['semanticValidationPerformed']
    module.write_bytes(b'tampered')
    assert json.loads(run(arguments, 4).stderr)['code'] == 'INTEGRITY_MISMATCH'
    generated = work / 'Generated'
    for command in ['capture', 'generate', 'validate', 'check', 'coverage', 'replay']:
        result = run([command, '--out', str(generated)], 3)
        assert not result.stdout and not generated.exists()
        assert json.loads(result.stderr)['code'] == 'UNSUPPORTED_OPERATION'
print('CLI integration passed: compiler probe, mismatch, indexing, bundle tampering, fail-closed commands.')
