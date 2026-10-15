#!/usr/bin/env python3
"""Qualify actual Device Hub input; this helper never changes the Duo pose."""
import argparse
import json
from pathlib import Path
import time
import subprocess
import sys
import uuid
from run import call, save, read_rows


def live(attempt):
    manifest = json.loads((attempt / 'manifest.json').read_text())
    run = json.loads((attempt / 'active-run.json').read_text())
    assert run['device'] == 'duo' and run['poses'], 'not an active Duo pose cell'
    assert manifest['devices']['duo']['owned'] is True
    build = manifest['builds'][run['build']]
    def container(suffix):
        bundle = run.get('runner_bundle', build['bundle_prefix'] + suffix) if suffix == '.uitests.xctrunner' else build['bundle_prefix'] + suffix
        return Path(call(['xcrun', 'simctl', 'get_app_container', run['udid'], bundle, 'data']))
    directory = container('.uitests.xctrunner') / 'Documents' / run['run_id']
    receipts = json.loads((directory / 'receipts.json').read_text())
    rows = read_rows(container('.' + run['framework'].lower()) / 'Documents/events.jsonl')
    assert all(r['run_id'] == run['run_id'] for r in rows + receipts), 'stale live input'
    return run, directory, receipts, rows


def display(run, name):
    path = Path(run['directory']) / (name + '-displays.json')
    call(['xcrun', 'devicectl', 'device', 'info', 'displays', '--device', run['udid'], '--json-output', str(path)])
    data = json.loads(path.read_text())
    assert data['info']['outcome'] == 'success'
    active = [d for d in data['result']['displays'] if d['active']]
    assert len(active) == 1, 'ambiguous active display'
    return {'observed_at': time.time(), 'active': active[0], 'artifact': str(path)}


def geometry(rows, before=None):
    values = [r for r in rows if r['kind'] == 'geometry' and (before is None or r['timestamp'] <= before)]
    assert values, 'missing native geometry'
    return values[-1]


def transition_valid(before, after, name, requested, *, allow_legacy_viewport=False):
    assert before['display']['observed_at'] >= requested, 'stale display precondition'
    assert after['display']['observed_at'] > before['display']['observed_at'], 'stale display readback'
    old, new = before['display']['active'], after['display']['active']
    assert old['primary'] == (name in ('open', 'reopen')), 'wrong starting display'
    assert new['primary'] == (name == 'close'), 'wrong ending display'
    assert old['uniqueId'] != new['uniqueId'], 'active display did not change'
    assert new['backlightState'] == 'activeOn', 'inactive display'
    prior, current = before['geometry'], after['geometry']
    assert prior['timestamp'] <= requested, 'late native precondition'
    assert current['timestamp'] <= after['display']['observed_at'], 'display readback precedes native geometry'
    assert current['timestamp'] > requested and current['sequence'] > prior['sequence'], 'stale native geometry'
    a, b = prior['payload']['scenes'], current['payload']['scenes']
    assert len(a) == len(b) == 1 and a[0]['id'] == b[0]['id'], 'native scene replaced'
    assert b[0]['activation'] == 0, 'not foreground-active'
    assert b[0]['windows'] and all(w['width'] > 0 and w['height'] > 0 for w in b[0]['windows']), 'empty native geometry'
    assert a[0]['windows'] != b[0]['windows'], 'native window inventory did not change'
    def spatial(windows):
        return {(w['width'], w['height'], w.get('horizontal_size_class'), w.get('vertical_size_class')) for w in windows}
    old_geometry, new_geometry = spatial(a[0]['windows']), spatial(b[0]['windows'])
    if old_geometry == new_geometry:
        assert allow_legacy_viewport and new_geometry == {(375, 667, 1, 2)}, 'duplicate windows do not prove a resize'
        return 'legacy_viewport_unchanged'
    return 'resized'


def main():
    p = argparse.ArgumentParser(); p.add_argument('stage', choices=['status', 'before', 'ack', 'home-ack', 'serve'])
    p.add_argument('--attempt', type=Path, required=True); p.add_argument('--pose', choices=['open', 'close', 'reopen'])
    args = p.parse_args()
    if args.stage == 'serve':
        print('READY: status | before/ack open/close/reopen | home-ack | quit', flush=True)
        for line in sys.stdin:
            parts = line.strip().split()
            if parts == ['quit']: return
            valid = parts in [['status'], ['home-ack']] or (len(parts) == 2 and parts[0] in ['before', 'ack'] and parts[1] in ['open', 'close', 'reopen'])
            if not valid:
                print('REJECTED: unknown bounded receipt command', flush=True); continue
            command = [sys.executable, '-B', str(Path(__file__).resolve()), parts[0], '--attempt', str(args.attempt)]
            if len(parts) == 2: command += ['--pose', parts[1]]
            subprocess.run(command, check=False)
            print('READY', flush=True)
        return
    run, directory, receipts, rows = live(args.attempt)
    if args.stage == 'status':
        print(json.dumps({'run_id': run['run_id'], 'phase': receipts[-1]['phase'], 'geometry': geometry(rows)})); return
    if args.stage == 'home-ack':
        assert receipts[-1]['phase'] == 'await-home', 'not waiting at Home boundary'
        requested = next(r['timestamp'] for r in receipts if r['phase'] == 'background.before')
        backgrounds = [r for r in rows if r['kind'] == 'native_background' and r['timestamp'] >= requested]
        assert len(backgrounds) == 1, 'missing or ambiguous actual native background'
        payload = {'run_id': run['run_id'], 'command_id': str(uuid.uuid4()),
                   'native_background_sequence': backgrounds[0]['sequence'], 'observed_at': time.time()}
        destination = directory / 'home.json'; assert not destination.exists(), 'Home receipt already delivered'
        save(Path(run['directory']) / 'home-command.json', payload); save(destination, payload)
        print(json.dumps(payload)); return
    assert receipts[-1]['phase'] == 'await-' + args.pose, 'not waiting at this pose boundary'
    requested = receipts[-1]['timestamp']
    checkpoint = Path(run['directory']) / (args.pose + '-before.json')
    if args.stage == 'before':
        assert not checkpoint.exists(), 'precondition already frozen'
        value = {'run_id': run['run_id'], 'requested_at': requested, 'geometry': geometry(rows, before=requested),
                 'display': display(run, args.pose + '-before')}
        assert value['display']['active']['primary'] == (args.pose in ('open', 'reopen')), 'wrong initial pose'
        save(checkpoint, value); print(json.dumps(value)); return
    before = json.loads(checkpoint.read_text()); assert before['run_id'] == run['run_id']
    after = {'geometry': geometry(rows), 'display': display(run, args.pose + '-after')}
    mode = transition_valid(before, after, args.pose, requested, allow_legacy_viewport=run['build'].endswith('-26.5'))
    destination = directory / (args.pose + '.json'); assert not destination.exists(), 'command already delivered'
    payload = {'run_id': run['run_id'], 'command_id': str(uuid.uuid4()), 'pose': args.pose,
               'geometry_sequence': after['geometry']['sequence'], 'geometry_mode': mode, 'before': before, 'after': after}
    save(Path(run['directory']) / (args.pose + '-command.json'), payload)
    save(destination, payload)
    print(json.dumps({'run_id': run['run_id'], 'pose': args.pose, 'geometry_sequence': payload['geometry_sequence']}))

if __name__ == '__main__': main()
