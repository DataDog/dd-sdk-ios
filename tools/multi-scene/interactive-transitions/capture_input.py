#!/usr/bin/env python3
"""One prompt's source-bound input selection; UI effects remain Xcode tool calls."""
import argparse
import json
import math
from pathlib import Path
import re
import sys
import shutil
import time
import capture_qualification as q
from capture_io import atomic, encoded

require = q.require
PHASES = {
    'setup.detail': ('home', 'home.next'), 'setup.detail-again': ('home', 'home.next'),
    'pop.finish': ('detail', None), 'pop.cancel': ('detail', None),
    'setup.sheet': ('detail', 'detail.sheet'), 'setup.sheet-again': ('detail', 'detail.sheet'),
    'dismiss.finish': ('sheet', None), 'dismiss.cancel': ('sheet', None),
    'return.dismiss': ('sheet', 'sheet.close'), 'return.home': ('detail', 'detail.back'),
    'background': ('home', None),
}
LABELS = {'home.next': 'Open detail', 'detail.sheet': 'Present sheet',
          'sheet.close': 'Dismiss sheet', 'detail.back': 'Return home'}
NUMBER = r'-?[0-9]+(?:\.[0-9]+)?'
FRAME = re.compile(r'^(\s*)([A-Za-z]+), \{\{(' + NUMBER + r'), (' + NUMBER + r')\}, \{(' + NUMBER + r'), (' + NUMBER + r')\}\}')


def one(values, reason):
    require(len(values) == 1, reason)
    return values[0]


def inside(rect, point):
    x, y, w, h = rect
    return w > 0 and h > 0 and x <= point[0] <= x+w and y <= point[1] <= y+h


def contains(outer, inner):
    return inside(outer, inner[:2]) and inside(outer, (inner[0]+inner[2], inner[1]+inner[3]))


def close_rect(a, b):
    return len(a) == len(b) == 4 and all(abs(x-y) <= 1 for x, y in zip(a, b))


def nodes(request, raw):
    q.hierarchy_owner(request, raw)
    sections = re.split(r'^Application bundle identifier: ', raw, flags=re.MULTILINE)[1:]
    require(sections and sections[0].splitlines()[0] == request['app_bundle'], 'task is not the captured foreground application')
    section = one([s for s in sections if s.splitlines()[0] == request['app_bundle']], 'ambiguous task application')
    result = []; parents = []
    for line in section.splitlines():
        match = FRAME.match(line)
        if not match:
            continue
        depth = len(match[1]); rect = [float(n) for n in match.group(3, 4, 5, 6)]
        require(all(math.isfinite(n) for n in rect), 'nonfinite hierarchy geometry')
        while parents and parents[-1]['depth'] >= depth:
            parents.pop()
        node = dict(depth=depth, role=match[2], rect=rect, line=line, ancestors=list(parents))
        for field in ['identifier', 'label']:
            found = re.findall(field + r": '([^']*)'", line)
            require(len(found) <= 1, 'ambiguous hierarchy attribute')
            node[field] = found[0] if found else None
        hit = re.findall(r'hitPoint: \{(' + NUMBER + '), (' + NUMBER + r')\}', line)
        node['hit'] = [float(n) for n in hit[0]] if len(hit) == 1 else None
        result.append(node); parents.append(node)
    require(result, 'empty task hierarchy')
    return result


def select(request, raw, snapshot):
    """No stale coordinates: every command derives from this exact hierarchy."""
    require(request['phase'] in PHASES, 'unadmitted input phase')
    screen, target = PHASES[request['phase']]
    inventory = nodes(request, raw)
    marker = one([n for n in inventory if n['identifier'] == 'screen.'+screen], 'screen marker missing or ambiguous')
    window = one([n for n in marker['ancestors'] if n['role'] == 'Window'], 'screen has no unique containing Window')
    t = snapshot['payload']['topology']
    binding = dict(root=t['bound_root'], scene=t['bound_scene'], window=t['bound_window'])
    require(t['root_alive'] and t['window_alive'] and t['bound_root_unchanged'], 'source owner no longer alive')
    scene = one([s for s in t['scene_inventory'] if s['id'] == binding['scene']], 'owned scene absent')
    owned = one([w for w in scene['windows'] if w['id'] == binding['window']], 'owned window absent')
    require(scene['activation'] == 0 and owned['owned'] and owned['key'] and owned['root_attached']
            and not owned['hidden'] and owned['alpha'] > 0 and owned['root'] == binding['root'], 'owned window not foreground and key')
    require(close_rect(window['rect'], owned['bounds']), 'actual containing Window differs from native owned geometry')
    q.driver.journey.visible(snapshot, screen, binding)
    require(contains(window['rect'], marker['rect']), 'screen marker is outside owned Window')
    for node in [marker, window, *marker['ancestors']]:
        require('activationBundleId:' not in node['line'] and 'isRemoteLeafPlaceholder' not in node['line'], 'overlapping or remote screen needs separate input admission')
    provenance = dict(screen=screen, binding=binding, window=window['rect'], marker=marker['line'].strip())
    if target:
        control = one([n for n in inventory if n['identifier'] == target], 'control missing or ambiguous')
        require(control['role'] in ['Button', 'Link', 'NavigationLink'] and control['label'] == LABELS[target]
                and window in control['ancestors'] and control['hit'] is not None, 'wrong native control role, label or window')
        require('activationBundleId:' not in control['line'] and 'isRemoteLeafPlaceholder' not in control['line'], 'target requires unadmitted activation')
        native = q.driver.capture_contract.target(snapshot, target, binding)
        require(close_rect(control['rect'], native['frame_in_window']) and contains(window['rect'], control['rect'])
                and inside(control['rect'], control['hit']) and inside(window['rect'], control['hit']), 'target geometry changed or hitPoint outside target')
        command = 't ' + ' '.join(format(n, '.6g') for n in control['hit'])
        provenance.update(target=target, element=control['line'].strip(), hit_point=control['hit'])
    elif request['phase'] == 'background':
        command = 'b h'
    else:
        x, y, w, h = window['rect']; cancel = request['phase'].endswith('.cancel')
        if request['phase'].startswith('pop.'):
            points = [(x+1, y+h/2), (x+w*(.25 if cancel else .9), y+h/2)]
        else:
            control = one([n for n in inventory if n['identifier'] == 'sheet.close'], 'sheet control missing or ambiguous')
            require(window in control['ancestors'], 'sheet control belongs to another window')
            common = [n for n in marker['ancestors'] if n in control['ancestors'] and n is not window]
            # Source declares a sheet, not a custom popover. Require a large inset
            # enclosing surface; a small SwiftUI content stack cannot supply it.
            candidates = {tuple(n['rect']) for n in common if contains(window['rect'], n['rect'])
                          and n['rect'][0] > x and n['rect'][1] > y and n['rect'][2] < w
                          and n['rect'][2] > w*.7 and n['rect'][3] > h*.6
                          and n['rect'][1] < y+h*.15 and n['rect'][1]+n['rect'][3] > y+h*.7}
            outer = [r for r in candidates if all(contains(r, s) for s in candidates)]
            sheet = one(outer, 'sheet enclosing surface missing or ambiguous')
            if t['framework'] == 'UIKit':
                controller = one([n for n in common if n['identifier'] == 'controller.sheet'], 'owned UIKit sheet surface missing')
                require(close_rect(controller['rect'], sheet), 'UIKit sheet surface mismatch')
            else:
                require(t['framework'] == 'SwiftUI' and snapshot['payload']['transition']['model']['sheet'] is True,
                        'native SwiftUI sheet not presented')
                graph = q.driver.native.controller_map(snapshot)
                front = q.driver.geometry.front_controllers(snapshot, binding)
                presented = [(parent, graph.get(parent['presented'])) for parent in graph.values()
                             if parent['window'] == binding['window'] and parent['presented'] != 'nil'
                             and graph.get(parent['presented'], {}).get('presenting') == parent['id']]
                parent, receiver = one(presented, 'ambiguous public sheet presentation')
                require(receiver is not None and receiver['id'] in front and receiver['window'] == binding['window']
                        and receiver['presenting'] == parent['id'], 'public presented owner is not attached and foremost')
                provenance['presentation'] = dict(presenter=parent['id'], presented=receiver['id'])
            sx, sy, sw, sh = sheet
            begin = (sx+sw/2, sy+16)
            require(begin[1] < min(marker['rect'][1], control['rect'][1]), 'sheet gesture would start in content')
            points = [begin, (begin[0], sy+sh*(.2 if cancel else .875))]
            provenance['sheet'] = list(sheet)
        if cancel:
            points.append(points[0])
        require(all(inside(window['rect'], p) for p in points), 'gesture leaves owned window')
        durations = [.55, .55, .1] if cancel else [.9, .1]
        command = 'mt ' + ' '.join('['+' '.join(format(n, '.6g') for n in p)+'] '+str(d) for p, d in zip(points, durations))
        provenance.update(points=points, durations=durations)
    return dict(command=command, provenance=provenance)


def pending(request_path, now):
    request = q.shared.read(request_path)
    require(request['issued_at'] <= now < request['deadline'], 'input prompt expired')
    require(not any(request_path.with_name(n).exists() for n in ['tool-return.json', 'input-failure.json', 'action-intent.json']), 'input prompt already consumed')
    out = request_path.parents[2]
    summary = q.shared.read(out/'summary.json')
    require(summary['state'] == 'RUNNING' and summary['cleanup'] == 'NOT_STARTED'
            and summary['identity']['run_id'] == request['run_id']
            and summary['identity']['pid'] == request['app_pid'] and summary['identity']['bundle'] == request['app_bundle'], 'cell no longer owns this input')
    require(q.driver.process_identity(request['app_pid']) == request['process_identity'], 'task process changed')
    native_path = Path(request['native_events_path'])
    require(native_path.is_file() and not native_path.is_symlink() and native_path.stat().st_size <= q.driver.MAX_BYTES, 'live native evidence missing or oversized')
    rows = [json.loads(line) for line in native_path.read_text().splitlines()]
    require(rows and all(r['run_id'] == request['run_id'] for r in rows), 'foreign native run')
    require([r['sequence'] for r in rows] == list(range(1, len(rows)+1)), 'native prefix not contiguous')
    before = one([r for r in rows if r['sequence'] == request['native_before_sequence']], 'native ready snapshot absent')
    require(before['kind'] == 'human_snapshot' and before['payload']['request_id'] == request['request_id']
            and before['payload']['phase'] == request['phase']+'.before', 'native readiness belongs to another prompt')
    retained = [json.loads(line) for line in request_path.with_name('events.jsonl').read_text().splitlines()]
    require(one([r for r in retained if r['sequence'] == before['sequence']], 'retained native readiness absent') == before, 'native readiness bytes changed')
    require(not q.driver.consumed(rows, before) and not any(r['kind'] in ['human_failure', 'transition_observer_rejected']
            and r['sequence'] > before['sequence'] for r in rows), 'native readiness already consumed')
    return request, before


def session_key(request_path):
    framework = request_path.parents[2].name
    root = request_path.parents[4]
    actual = q.tool_value(q.shared.read(root/'sessions'/framework/'start.json')['actual_return'])
    return actual['interactionSessionKey']


def preserve(request_path, observed, prefix):
    receipts = {}
    try:
        actual = q.tool_value(observed['actual_return'])
    except Exception:
        return
    for name in ['hierarchy', 'screenshot', 'logs']:
        value = actual.get(name+'Path')
        if not value:
            continue
        source = Path(value)
        if not source.is_file() or source.is_symlink():
            continue
        dest = request_path.with_name(prefix+'-'+name+source.suffix)
        require(not dest.exists(), 'actual artifact destination consumed')
        shutil.copy2(source, dest)
        receipts[name] = dict(path=str(dest), source_path=str(source), sha256=q.shared.sha(dest))
    atomic(request_path.with_name(prefix+'-artifacts.json'), encoded(receipts))


def plan(request_path, payload):
    observed = payload['observation']; before_path = request_path.with_name('worker-before.json')
    atomic(before_path, encoded(observed))  # Preserve the actual return before validation.
    preserve(request_path, observed, 'worker-before')
    try:
        request, snapshot = pending(request_path, time.time())
        require(observed['interaction_session_key'] == session_key(request_path), 'foreign interaction session')
        actual = q.before_action(request, observed, time.time())
        selection = select(request, Path(actual['hierarchyPath']).read_text(), snapshot)
        pending(request_path, time.time())
        q.before_action(request, observed, time.time())
        intent = dict(request_id=request['request_id'], run_id=request['run_id'], at=time.time(),
                      before_sha256=q.shared.sha(before_path), **selection)
        atomic(request_path.with_name('action-intent.json'), encoded(intent))
        return dict(state='READY', deadline=request['deadline'], **selection)
    except Exception as error:
        # The plan command runs before dispatch; an existing intent must never be
        # converted to zero-action proof on a repeated call.
        if not request_path.with_name('action-intent.json').exists():
            q.publish_no_input_failure(request_path, before_path, type(error).__name__+': '+str(error))
        return dict(state='STOP', reason=type(error).__name__+': '+str(error))


def abort(request_path, payload):
    require(payload.get('dispatch_attempted') is False, 'attempted effect cannot be zero-action proof')
    require(not request_path.with_name('worker-action.json').exists(), 'actual effect return already exists')
    intent = q.shared.read(request_path.with_name('action-intent.json'))
    before_path = request_path.with_name('worker-before.json')
    request = q.shared.read(request_path)
    require(intent['request_id'] == request['request_id'] and intent['run_id'] == request['run_id']
            and intent['before_sha256'] == q.shared.sha(before_path), 'unbound stopped dispatch')
    atomic(request_path.with_name('worker-stop.json'), encoded(dict(at=time.time(), dispatch_attempted=False,
                                                                  reason='dispatch bound expired after planning')))
    q.publish_no_input_failure(request_path, before_path, 'dispatch bound expired before action; no effect sent')
    return dict(state='STOP', reason='dispatch bound expired before action')


def publish(request_path, payload):
    observed = payload['observation']; action_path = request_path.with_name('worker-action.json')
    atomic(action_path, encoded(observed))
    preserve(request_path, observed, 'worker-action')
    intent = q.shared.read(request_path.with_name('action-intent.json'))
    require(observed['command'] == intent['command'] and observed['interaction_session_key'] == session_key(request_path), 'action differs from bound intent')
    require(observed['started_at'] >= intent['at'], 'action preceded intent')
    q.publish(request_path, request_path.with_name('worker-before.json'), action_path)
    q.completed_input(request_path)
    return dict(state='PUBLISHED', phase=q.shared.read(request_path)['phase'], command=observed['command'])


def main():
    parser = argparse.ArgumentParser(); parser.add_argument('stage', choices=['plan', 'publish', 'abort'])
    parser.add_argument('--request', type=Path, required=True); args = parser.parse_args()
    payload = json.load(sys.stdin)
    print(json.dumps(dict(plan=plan, publish=publish, abort=abort)[args.stage](args.request.resolve(strict=True), payload)), flush=True)


if __name__ == '__main__':
    main()
