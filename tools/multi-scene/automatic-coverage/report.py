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
    for failed in output['retained_unqualified']:
        manifest = json.loads((Path(failed['attempt']) / 'manifest.json').read_text())
        run = next(r for r in manifest['runs'] if r['run_id'] == failed['run_id'])
        directory = Path(run['directory'])
        failed.update(test_exit=run.get('test_exit'), clean_install=run.get('clean_install'), cleanup=run.get('cleanup'),
                      artifact_directory=str(directory))
        failed['artifacts_sha256'] = {}
        for name in ['events.jsonl', 'receipts.json', 'test-summary.json', 'run.json', 'bounded-interruption.json',
                     'compatibility-visibility.json', 'compatibility-inner.png', 'legacy-inner-runner.log']:
            artifact = directory / name
            if artifact.exists(): failed['artifacts_sha256'][name] = hashlib.sha256(artifact.read_bytes()).hexdigest()
        for name in ['bounded-interruption.json', 'compatibility-visibility.json']:
            artifact = directory / name
            if artifact.exists(): failed[name.removesuffix('.json')] = json.loads(artifact.read_text())
        receipts_path = directory / 'receipts.json'
        if receipts_path.exists():
            receipts = json.loads(receipts_path.read_text())
            failed['last_input_receipt'] = receipts[-1] if receipts else None
        summary_path = directory / 'test-summary.json'
        if summary_path.exists():
            try:
                summary = json.loads(summary_path.read_text())
                failed['native_failures'] = [failure.get('failureText') for failure in summary.get('testFailures', [])]
            except json.JSONDecodeError:
                failed['native_summary_state'] = 'incomplete result bundle; raw output retained'
    for cell in accepted.values():
        manifest = json.loads((Path(cell['attempt']) / 'manifest.json').read_text())
        run = next(r for r in manifest['runs'] if r['run_id'] == cell['run_id'])
        build = manifest['builds'][run['build']]
        directory = Path(run['directory'])
        summary = json.loads((directory / 'test-summary.json').read_text())
        receipts = json.loads((directory / 'receipts.json').read_text())
        rows = [json.loads(line) for line in (directory / 'events.jsonl').read_text().splitlines()]
        record = {k: v for k, v in cell.items() if k not in ['attempt', 'state', 'proof']}
        record['native_timeline'] = [row for row in rows if row['kind'] in ['native_appear', 'native_input', 'native_background']]
        record['view_phase_timeline'] = []
        background_times = [row['timestamp'] for row in rows if row['kind'] == 'native_background']
        for view in cell['views']:
            timestamp = view['date'] / 1000
            preceding = [receipt for receipt in receipts if receipt['timestamp'] <= timestamp]
            record['view_phase_timeline'].append({'view_id': view['id'], 'index': view['index'],
                'name': view['name'], 'timestamp': timestamp,
                'preceding_input_phase': preceding[-1]['phase'] if preceding else None,
                'seconds_after_last_background': timestamp - max(background_times) if background_times else None})
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
