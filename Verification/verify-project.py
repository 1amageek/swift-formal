#!/usr/bin/env python3
"""Execute both verification paths and publish a complete acceptance assessment."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from collections import Counter
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--formal', type=Path, required=True)
parser.add_argument('--report-tool', type=Path, required=True)
parser.add_argument('--skip-supporting-tests', action='store_true')
args = parser.parse_args()
formal = args.formal.resolve(strict=True)
builder = args.report_tool.resolve(strict=True)
module_spec = importlib.util.spec_from_file_location('invar_project_report', builder)
report_module = importlib.util.module_from_spec(module_spec)
module_spec.loader.exec_module(report_module)
run_id = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
run = root / 'Verification/Project/runs' / run_id
run.mkdir(parents=True)
production = sorted((root / 'Sources').rglob('*.swift'))
inputs = {path: hashlib.sha256(path.read_bytes()).hexdigest() for path in production}
inputs[root / 'Documentation/SPEC.md'] = hashlib.sha256((root / 'Documentation/SPEC.md').read_bytes()).hexdigest()
inputs[root / 'DESIGN.md'] = hashlib.sha256((root / 'DESIGN.md').read_bytes()).hexdigest()
for relative in ['Tools/run-with-timeout.py', 'Tools/verify-backends.py', 'Tools/integration.py', 'Verification/verify-project.py', 'Verification/Project/Reviews/requirements.json']:
    path = root / relative
    inputs[path] = hashlib.sha256(path.read_bytes()).hexdigest()
for subject in ['VerificationOutcome', 'ActorIsolation', 'SourceAdmission']:
    for path in (root / 'Verification/Specifications' / subject).iterdir():
        if path.suffix in {'.tla', '.cfg', '.lean', '.py'}:
            inputs[path] = hashlib.sha256(path.read_bytes()).hexdigest()
tool_identity = {'formal': hashlib.sha256(formal.read_bytes()).hexdigest(), 'reportBuilder': hashlib.sha256(builder.read_bytes()).hexdigest()}


def reference(path):
    return {'path': str(path.relative_to(root)), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


def execute(name, command, seconds):
    wrapped = ['python3', str(root / 'Tools/run-with-timeout.py'), '--seconds', str(seconds), '--', *map(str, command)]
    result = subprocess.run(wrapped, cwd=root, capture_output=True, text=True, timeout=seconds + 10)
    log = run / (name + '.log')
    log.write_text(result.stdout + result.stderr)
    return result.returncode, log


observations = {}
specification_root = root / 'Verification/Specifications/VerificationOutcome'
spec_code, spec_log = execute('specification', ['python3', specification_root / 'verify.py', '--toolchain', formal.parent / 'toolchain'], 120)
observations['specification'] = {'command': ['python3', 'Verification/Specifications/VerificationOutcome/verify.py', '--toolchain', str(formal.parent / 'toolchain')], 'exitCode': spec_code, 'log': reference(spec_log)}
actor_root = root / 'Verification/Specifications/ActorIsolation'
actor_code, actor_log = execute('actor-specification', ['python3', actor_root / 'verify.py', '--toolchain', formal.parent / 'toolchain'], 120)
observations['actor-specification'] = {'command': ['python3', 'Verification/Specifications/ActorIsolation/verify.py', '--toolchain', str(formal.parent / 'toolchain')], 'exitCode': actor_code, 'log': reference(actor_log)}
admission_root = root / 'Verification/Specifications/SourceAdmission'
admission_code, admission_log = execute('source-admission', ['python3', admission_root / 'verify.py', '--toolchain', formal.parent / 'toolchain'], 120)
observations['source-admission'] = {'command': ['python3', 'Verification/Specifications/SourceAdmission/verify.py', '--toolchain', str(formal.parent / 'toolchain')], 'exitCode': admission_code, 'log': reference(admission_log)}
if admission_code != 0:
    raise ValueError('The source-admission contract did not pass; no project assessment was published')

commands = {
    'unit': (['swift', 'test', '--disable-xctest'], 120),
    'backends': (['python3', 'Tools/verify-backends.py'], 120),
    'cli': (['python3', 'Tools/integration.py'], 120),
}
for name, (command, seconds) in ({} if args.skip_supporting_tests else commands).items():
    result_code, log = execute(name, command, seconds)
    observations[name] = {'command': command, 'exitCode': result_code, 'log': reference(log)}




def model(path):
    source = path.read_bytes()
    with tempfile.TemporaryDirectory(prefix='formal-project-source-') as scratch:
        captured = Path(scratch) / path.name
        captured.write_bytes(source)
        command = [str(formal), 'translate', '--language', 'swift', '--source', str(captured), '--output', str(Path(scratch) / 'model'), '--draft-unvalidated']
        try:
            result = subprocess.run(command, capture_output=True, text=True, timeout=12)
            return {'path': str(path.relative_to(root)), 'sha256': hashlib.sha256(source).hexdigest(),
                    'exitCode': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr,
                    'outcome': 'unknown' if result.returncode == 0 else 'unsupported' if result.returncode == 3 else 'failed'}
        except subprocess.TimeoutExpired:
            return {'path': str(path.relative_to(root)), 'sha256': hashlib.sha256(source).hexdigest(), 'outcome': 'unknown', 'detail': 'Source generation exceeded 12 seconds'}


with ThreadPoolExecutor(max_workers=4) as workers:
    records = list(workers.map(model, production))
generation_counts = Counter(record['outcome'] for record in records)
if {record['path'] for record in records} != {str(path.relative_to(root)) for path in production}:
    raise ValueError('Production-source inventory is incomplete')
for record in records:
    if inputs[root / record['path']] != record['sha256']:
        raise ValueError('Changed production input: ' + record['path'])
source_log = run / 'production-models.json'
source_log.write_text(json.dumps({'command': ['formal', 'translate', '--language', 'swift', '--source', '<captured production source>', '--output', '<fresh scratch>', '--draft-unvalidated'],
                                 'toolSHA256': hashlib.sha256(formal.read_bytes()).hexdigest(), 'files': records}, indent=2) + '\n')

inventory_reference = reference(root / 'Documentation/SPEC.md')
sections = [{'heading': '## 17. 受け入れテスト', 'kind': 'table'}, {'heading': '## 19. Definition of Done', 'kind': 'bullets', 'prefix': 'D'}]
inventory = report_module.inventory((root / 'Documentation/SPEC.md').read_text(), sections)
ids = [item['id'] for item in inventory]
spec_claims = []
if spec_code == 0:
    log = spec_log.read_text()
    if 'Five invariants, four Lean theorems and three controls checked.' not in log:
        raise ValueError('Specification checker did not confirm the expected observations')
    spec_claims.append({'id': 'interruption-contract', 'requirements': ['A26'], 'domain': 'specification.tla.finite', 'outcome': 'passed',
                        'scope': 'Bounded requirements-derived outcome protocol, one invocation and clock 0..2. Both checked-success outcomes are represented by the positive proof outcome. No implementation correspondence is asserted.'})
for claim in spec_claims:
    claim.update(method='modelCheck', obligations=[{**reference(specification_root / 'VerificationOutcome.tla'), 'selector': 'InterruptedCannotProve'},
                                                  {**reference(specification_root / 'VerificationOutcome.lean'), 'selector': 'VerificationOutcome.interruptionIsUnknown'}])
spec_receipt = {'schemaVersion': 2, 'activity': 'specificationCheck', 'command': observations['specification']['command'], 'executed': True, 'exitCode': spec_code,
                'inputs': [reference(specification_root / file) for file in ['VerificationOutcome.tla', 'VerificationOutcome.cfg', 'VerificationOutcome.lean']],
                'outputs': [reference(spec_log)], 'claims': spec_claims}
(run / 'specification-receipt.json').write_text(json.dumps(spec_receipt, indent=2) + '\n')
actor_claims = []
if actor_code == 0:
    if 'Reentrancy counterexample, atomic safety and four Lean theorems checked.' not in actor_log.read_text():
        raise ValueError('Actor checker did not confirm the expected observations')
    actor_claims = [
        {'id': 'reentrant-design', 'requirements': ['A12'], 'domain': 'specification.tla.finite', 'outcome': 'passed',
         'scope': 'Two calls, initial stock one. TLC finds the stale-observation trace and Lean checks every transition in the same abstract trace. No SIL correspondence.'},
        {'id': 'atomic-design', 'requirements': ['A13'], 'domain': 'specification.lean.quantified', 'outcome': 'passed',
         'scope': 'Lean proves capacity conservation and no overselling for arbitrary natural capacities and any number of atomic reservations. TLC checks both task orderings for stock one. Atomic non-suspending actor execution is the explicit specification assumption.'},
    ]
for claim in actor_claims:
    selector = 'ActorIsolation.reentrantCounterexample' if claim['id'] == 'reentrant-design' else 'ActorIsolation.noOverselling'
    claim.update(method='modelCheck' if claim['id'] == 'reentrant-design' else 'proof',
                 obligations=[{**reference(actor_root / 'ActorIsolation.lean'), 'selector': selector}])
actor_receipt = {'schemaVersion': 2, 'activity': 'specificationCheck', 'command': observations['actor-specification']['command'], 'executed': True, 'exitCode': actor_code,
                 'inputs': [reference(actor_root / file) for file in ['ActorIsolation.tla', 'Correct.cfg', 'Reentrant.cfg', 'ActorIsolation.lean']],
                 'outputs': [reference(actor_log)], 'claims': actor_claims}
(run / 'actor-receipt.json').write_text(json.dumps(actor_receipt, indent=2) + '\n')
admission_receipt = {'schemaVersion': 2, 'activity': 'specificationCheck', 'command': observations['source-admission']['command'], 'executed': True,
                     'exitCode': admission_code,
                     'inputs': [reference(admission_root / file) for file in ['SourceAdmission.tla', 'SourceAdmission.cfg', 'SourceAdmission.lean', 'verify.py']],
                     'outputs': [reference(admission_log)], 'claims': []}
(run / 'source-admission-receipt.json').write_text(json.dumps(admission_receipt, indent=2) + '\n')
unsupported = all(record['outcome'] == 'unsupported' for record in records)
source_receipt = {'schemaVersion': 2, 'activity': 'modelGeneration', 'command': ['formal', 'translate', '<all exact production Swift files>'], 'executed': True,
                  'exitCode': 3 if unsupported else 6, 'inputs': [reference(path) for path in production], 'outputs': [reference(source_log)],
                  'claims': [{'id': 'production-source-models', 'requirements': ids, 'domain': 'generatedModel.source.profile',
                              'outcome': 'unsupported' if unsupported else 'unknown', 'method': 'generation',
                              'sourceInputs': [reference(path) for path in production], 'modelInputs': [],
                              'scope': str(len(records)) + ' exact production Swift files. Generation alone does not verify an implementation property.'}]}
(run / 'implementation-receipt.json').write_text(json.dumps(source_receipt, indent=2) + '\n')

titles = [
    'Fixed-width subtraction', 'Overflow and wrapping', 'Branches and payloads', 'SSA block arguments', 'Loops and recursion',
    'Nontermination', 'Memory and inout', 'Direct calls', 'Throw and catch', 'Unresolved external calls', 'Unsupported instructions',
    'Actor reentrancy counterexample', 'Actor isolation correction', 'Async call semantics', 'Executor identity', 'Terminal and deadlock',
    'Artificial bounds', 'Module dependency closure', 'Missing debug locations', 'Missing source index', 'Translation tampering',
    'Output-expression tampering', 'Admitted or custom axioms', 'Deterministic regeneration', 'Toolchain mismatch', 'Timeout and interruption',
    'Deleted control-flow mutation', 'Shared IR mistranslation', 'Empty or contradictory scenarios',
    'Both backends from supported SIL', 'Deterministic generation without inference', 'Complete semantic coverage', 'Explicit unsupported diagnostics',
    'Actor fixtures in both backends', 'Automatic source/model correspondence', 'Separate generation and proof outcomes', 'Finite and universal scope distinction',
    'Complete provenance', 'Generator and validator mutation suite', 'Reproducible output bytes', 'Dependency ownership boundary',
]
assert len(titles) == len(inventory) == 41
requirements = []
generation_detail = (str(sum(record.get('exitCode') == 0 for record in records)) + ' production models generated; '
                     + ', '.join(str(count) + ' ' + outcome for outcome, count in sorted(generation_counts.items()))
                     + '. No production property or validated source correspondence is established by generation.')
for item, title in zip(inventory, titles):
    identity = item['id']
    claims = ['interruption-contract'] if identity == 'A26' and spec_claims else ['reentrant-design'] if identity == 'A12' and actor_claims else ['atomic-design'] if identity == 'A13' and actor_claims else []
    number = int(identity[1:])
    group = 'Product completion' if identity.startswith('D') else 'Core execution' if number <= 10 else 'Actor and concurrency' if 12 <= number <= 15 else 'Trust and validation' if number >= 21 else 'Input and execution boundaries'
    requirements.append({'id': identity, 'title': title, 'group': group,
        'specification': {'claims': claims} if claims else {'claims': [], 'reason': 'No complete independently checked requirements-derived model is retained for this acceptance condition.'},
        'implementation': {'claims': ['production-source-models'], 'reason': generation_detail},
        'correspondence': {'claims': [], 'reason': 'Formal currently supplies UNVALIDATED source correspondence. No validated translation certificate establishes this acceptance condition.'}})
    
manifest = {'schemaVersion': 2, 'title': 'Formal · Whole-project verification', 'inventory': {'source': inventory_reference, 'sections': sections},
            'productionInputs': [reference(path) for path in production], 'reviews': [reference(root / 'Verification/Project/Reviews/requirements.json')],
            'governingDocuments': [reference(root / 'DESIGN.md')], 'requirements': requirements,
            'receipts': [reference(run / 'specification-receipt.json'), reference(run / 'actor-receipt.json'), reference(run / 'source-admission-receipt.json'), reference(run / 'implementation-receipt.json')]}
for path, digest in inputs.items():
    if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
        raise ValueError('Verification input changed during execution: ' + str(path))
(run / 'observations.json').write_text(json.dumps({'commands': observations, 'tools': tool_identity,
                                                'inputs': [reference(path) for path in inputs]}, indent=2) + '\n')
(run / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
result = report_module.build(root, manifest)
(run / 'Report.json').write_text(json.dumps(result, indent=2) + '\n')
current = root / 'Verification/Project/Report.json'
temporary = current.with_suffix('.tmp')
with temporary.open('x') as file:
    file.write(json.dumps(result, indent=2) + '\n')
temporary.replace(current)
print(json.dumps({'run': str(run.relative_to(root)), 'requirements': len(inventory), 'productionFiles': len(records),
                  'productionModelsGenerated': sum(record.get('exitCode') == 0 for record in records), 'productionOutcomes': dict(generation_counts), 'overall': result['metadata']['verificationReport']['outcome'], 'manifest': str((run / 'manifest.json').relative_to(root)), 'report': str(current.relative_to(root))}))
raise SystemExit({'passed': 0, 'failed': 5, 'incomplete': 6}[result['metadata']['verificationReport']['outcome']])
