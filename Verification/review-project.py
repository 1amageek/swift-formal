#!/usr/bin/env python3
"""Assemble reviewed original evidence; never execute or promote checker claims."""
import argparse
from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--manifest', type=Path, required=True)
parser.add_argument('--report-tool', type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
manifest_path = args.manifest.resolve(strict=True)
if not manifest_path.is_relative_to(root):
    parser.error('The review manifest must belong to the target repository')
module_spec = importlib.util.spec_from_file_location('invar_project_report', args.report_tool.resolve(strict=True))
builder = importlib.util.module_from_spec(module_spec)
module_spec.loader.exec_module(builder)
manifest = json.loads(manifest_path.read_text())
document = builder.build(root, manifest)
run = root / 'Verification/ReviewedProject/runs' / datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
run.mkdir(parents=True)
retained_manifest = run / 'manifest.json'
retained_manifest.write_text(json.dumps(manifest, indent=2) + '\n')
encoded = json.dumps(document, ensure_ascii=False, indent=2) + '\n'
(run / 'Report.json').write_text(encoded)
current = root / 'Verification/ReviewedProject/Report.json'
temporary = current.with_suffix('.tmp')
with temporary.open('x') as output:
    output.write(encoded)
temporary.replace(current)
outcome = document['metadata']['verificationReport']['outcome']
print(json.dumps({'manifest': str(retained_manifest.relative_to(root)), 'report': str(current.relative_to(root)), 'overall': outcome}))
raise SystemExit({'passed': 0, 'failed': 5, 'incomplete': 6}[outcome])
