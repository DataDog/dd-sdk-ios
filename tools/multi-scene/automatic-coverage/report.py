#!/usr/bin/env python3
"""Export accepted inventories and retained failures into one durable summary."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
from analyze import analyze
from run import save


def report(attempt, device=None):
    analyzed = analyze(attempt)
    accepted = {tuple(cell['cell']): cell for cell in analyzed['cells']
                if cell['state'] == 'QUALIFIED_INPUT' and (device is None or cell['cell'][1] == device)}
    output = {'experiment': 'EXP-195', 'boundary': analyzed['boundary'],
              'declared_multiple_scenes': analyzed['declared_multiple_scenes'],
              'device_filter': device, 'qualified_unique_cells': len(accepted), 'cells': [],
              'comparisons': [c for c in analyzed['comparisons'] if device is None or c['after_cell'][1] == device],
              'retained_unqualified': [c for c in analyzed['cells'] if c['state'] != 'QUALIFIED_INPUT'
                                      and (device is None or c['cell'][1] == device)]}
    for cell in accepted.values():
        manifest = json.loads((Path(cell['attempt']) / 'manifest.json').read_text())
        run = next(r for r in manifest['runs'] if r['run_id'] == cell['run_id'])
        build = manifest['builds'][run['build']]
        directory = Path(run['directory'])
        summary = json.loads((directory / 'test-summary.json').read_text())
        receipts = json.loads((directory / 'receipts.json').read_text())
        record = {k: v for k, v in cell.items() if k not in ['attempt', 'state', 'proof']}
        record.update(source_revision=build['revision'], toolchain=build['toolchain'], build_sdk=build['sdk'],
                      fixture_sources=manifest['fixture'], collector_sources=manifest['ui_tests'],
                      collector_build_key=run.get('collector_build_key', run['build']),
                      artifact_directory=str(directory), native_test=summary,
                      clean_install=run['clean_install'], cleanup=run['cleanup'],
                      installed_apps=run['installed'], installed_runner=run.get('installed_runner'),
                      installed_after_test=run.get('installed_after_test'),
                      built_app_metadata=run.get('built_app_metadata'),
                      installed_app_metadata=run.get('installed_app_metadata'),
                      app_metadata_after_test=run.get('app_metadata_after_test'),
                      pose_receipts=[r for r in receipts if r['phase'].startswith(('await-', 'received-'))])
        artifacts = [directory / name for name in ['events.jsonl', 'receipts.json', 'test-summary.json', 'run.json']]
        artifacts += sorted(directory.glob('*-command.json')) + sorted(directory.glob('*-displays.json'))
        artifacts += sorted(directory.glob('*.sample.txt')) + sorted(directory.glob('*runner.log'))
        record['artifacts_sha256'] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in artifacts}
        output['cells'].append(record)
    output['comparison_statuses'] = dict(Counter(c['status'] for c in output['comparisons']))
    return output


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('attempt', type=Path)
    parser.add_argument('--device', choices=['regular', 'duo'])
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = report(args.attempt, args.device)
    save(args.output, result)
    print(json.dumps({k: result[k] for k in ['qualified_unique_cells', 'comparison_statuses']}))
