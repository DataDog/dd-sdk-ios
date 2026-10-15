"""Current supported-tool coordinates for the bounded split ancestry diagnostic.

The hierarchy supplies coordinates only. Native source ownership and effects
remain the existing human journey oracle's responsibility.
"""
import json
import math
import re
from pathlib import Path

import human_journey as journey
import human_supported_session as evidence

require = evidence.require
NUMBER = r'-?[0-9]+(?:\.[0-9]+)?'
FRAME = re.compile(r'^(\s*)([A-Za-z]+), \{\{(' + NUMBER + r'), (' + NUMBER + r')\}, \{(' + NUMBER + r'), (' + NUMBER + r')\}\}')
LABELS = dict(tap='Tap', toggle='Enable', next='Open detail', sheet='Present sheet',
              back='Return home', close='Dismiss sheet')
INPUT_KINDS = ('human_callback', 'native_input', 'human_scroll_begin', 'human_scroll_end', 'native_background')


def original(reference):
    require(evidence.reference(reference['path']) == reference, 'original prefix changed')
    value = evidence.read(reference['path'])
    require(value['state'] == 'ORIGINAL_PREFIX_BOUND_ONLY' and value['new_native_runs'] == 0
            and not value['gates_closed'] and [s['step'] for s in value['steps']] == journey.flow('split', 'initial'),
            'not the exact original split prefix')
    for key in ('source_owner', 'source_plan', 'source_summary', 'journey_source', 'fold_before', 'failed_fold_effect'):
        ref = value[key]
        require(evidence.reference(ref['path']) == ref, 'original prefix dependency changed: ' + key)
    for item in value['steps']:
        for key in ('before', 'after', 'effect'):
            ref = item[key]
            require(evidence.reference(ref['path']) == ref, 'original step bytes changed')
        if item['step']['kind'] == 'scroll':
            rows = [json.loads(line) for line in Path(item['after']['path']).read_bytes().splitlines()]
            selected = [r for r in rows if item['before_sequence'] < r['sequence'] < item['after_sequence']]
            start = journey.h.one([r for r in selected if r['kind'] == 'human_scroll_begin'], 'original scroll begin')
            end = journey.h.one([r for r in selected if r['kind'] == 'human_scroll_end'], 'original scroll end')
            require(start['payload']['scroll']['offset'] == [0, 0]
                    and end['payload']['scroll']['offset'][1] < 0, 'original scroll direction differs')
    return value


def nodes(raw, bundle, pid):
    headers = re.findall(r'^Application bundle identifier: ([^\n]+)\nApplication UI orientation: [^\n]*\nApplication, pid: ([0-9]+),', raw, re.MULTILINE)
    require(headers and headers[0] == (bundle, str(pid))
            and [p for b, p in headers if b == bundle] == [str(pid)], 'wrong or ambiguous foreground task')
    section = re.split(r'^Application bundle identifier: ', raw, flags=re.MULTILINE)[1]
    result, parents = [], []
    for line in section.splitlines():
        match = FRAME.match(line)
        if not match:
            continue
        depth = len(match[1]); rect = [float(n) for n in match.group(3, 4, 5, 6)]
        require(all(math.isfinite(n) for n in rect), 'nonfinite tool geometry')
        while parents and parents[-1]['depth'] >= depth:
            parents.pop()
        item = dict(depth=depth, role=match[2], rect=rect, line=line, ancestors=list(parents))
        for field in ('identifier', 'label'):
            values = re.findall(field + r": '([^']*)'", line)
            require(len(values) <= 1, 'ambiguous tool attribute')
            item[field] = values[0] if values else None
        hits = re.findall(r'hitPoint: \{(' + NUMBER + '), (' + NUMBER + r')\}', line)
        require(len(hits) <= 1, 'ambiguous hit point')
        item['hit'] = [float(n) for n in hits[0]] if hits else None
        result.append(item); parents.append(item)
    require(result, 'empty task hierarchy')
    return result


def inside(rect, point):
    return (point is not None and all(math.isfinite(n) for n in point)
            and rect[2] > 0 and rect[3] > 0
            and rect[0] <= point[0] <= rect[0] + rect[2]
            and rect[1] <= point[1] <= rect[1] + rect[3])


def same_rect(a, b):
    # Xcode publishes one decimal place; compare in points with bounded tolerance.
    return len(a) == len(b) == 4 and all(math.isfinite(n) for n in a + b) and all(abs(x-y) <= .1 for x, y in zip(a, b))


def select(raw, snapshot, step, binding, bundle, pid):
    require(step in journey.flow('split', 'initial') and snapshot['payload']['phase'] == step['phase'] + '.before',
            'unadmitted input phase')
    _, owned = journey.h.topology(snapshot['payload']['topology'], binding)
    native = journey.h.target(snapshot, step['target'], binding)
    native_marker = journey.visible(snapshot, step['screen'], binding)
    items = nodes(raw, bundle, pid)
    target = journey.h.one([n for n in items if n['identifier'] == step['target']], 'tool target')
    marker = journey.h.one([n for n in items if n['identifier'] == 'screen.' + step['screen']], 'tool screen')
    window = journey.h.one([n for n in target['ancestors'] if n['role'] == 'Window'], 'tool window')
    require(any(n is window for n in marker['ancestors']) and same_rect(window['rect'], owned['bounds'])
            and same_rect(target['rect'], native['frame_in_window'])
            and same_rect(marker['rect'], native_marker['frame_in_window']), 'tool/native owner geometry differs')
    control = target
    if step['kind'] == 'toggle':
        require(target['role'] == 'Switch' and target['label'] == 'Enable', 'wrong toggle container')
        control = journey.h.one([n for n in items if n['role'] == 'Switch'
                                 and any(a is target for a in n['ancestors'])], 'nested actual Switch')
    elif step['kind'] == 'scroll':
        require(target['role'] == 'ScrollView', 'wrong scroll control')
        scroll = journey.h.one([s for s in snapshot['payload']['topology']['scrolls']
            if s['id'] == native['id'] and s['accessibility_id'] == step['target']], 'owned current scroll')
        require(scroll['owned'] and scroll['window'] == binding['window'] and scroll['scene'] == binding['scene']
                and scroll['enabled'] and not scroll['hidden'] and scroll['alpha'] > 0
                and not any(scroll[k] for k in ('tracking', 'dragging', 'decelerating'))
                and all(abs(n) <= .1 for n in scroll['offset']), 'scroll is not idle at its original start')
    else:
        require(target['role'] in ('Button', 'Link', 'NavigationLink')
                and target['label'] == LABELS[step['target'].split('.')[-1]], 'wrong button role or label')
    for node in [marker, control, *marker['ancestors'], *control['ancestors']]:
        require('activationBundleId:' not in node['line'] and 'isRemoteLeafPlaceholder' not in node['line'],
                'remote or overlapping input is not admitted')
    point = control['hit']
    require(inside(control['rect'], point) and inside(target['rect'], point) and inside(window['rect'], point),
            'hit point is absent or outside current target')
    command = 't ' + ' '.join(format(n, '.8g') for n in point)
    proof = dict(step=step, binding=binding, target=target['line'].strip(), control=control['line'].strip(), hit_point=point)
    if step['kind'] == 'scroll':
        end = [point[0], point[1] + target['rect'][3] * .4]
        require(inside(target['rect'], end) and inside(window['rect'], end), 'downward swipe leaves current target')
        command += ' f ' + ' '.join(format(n, '.8g') for n in end) + ' 0.6'
        proof.update(direction='down', end_point=end, original_amplitude_reproduced=False)
    return dict(command=command, provenance=proof)


def unconsumed(raw, prefix, run, before):
    require(raw.startswith(prefix), 'native stream changed before dispatch')
    require(raw.endswith(b'\n'), 'partial native write cannot authorize input')
    complete = raw[:raw.rfind(b'\n') + 1]
    rows = [json.loads(line) for line in complete.splitlines()]
    require(rows and all(r['run_id'] == run for r in rows)
            and [r['sequence'] for r in rows] == list(range(1, len(rows)+1)), 'foreign or gapped dispatch stream')
    require(before in rows and not any(r['kind'] in (*INPUT_KINDS, 'human_failure', 'human_snapshot')
        for r in rows if r['sequence'] > before['sequence']), 'input readiness already consumed')


def scroll_direction(rows, before, after, step):
    if step['kind'] == 'scroll':
        selected = journey.interval(rows, before, after)
        begin = journey.h.one([r for r in selected if r['kind'] == 'human_scroll_begin'], 'prefix scroll begin')
        end = journey.h.one([r for r in selected if r['kind'] == 'human_scroll_end'], 'prefix scroll end')
        require(all(abs(n) <= .1 for n in begin['payload']['scroll']['offset'])
                and end['payload']['scroll']['offset'][1] < 0, 'prefix scroll did not follow original direction')


def final_state(snapshot, binding):
    require(journey.counter(snapshot, 'sidebar', binding, 'SwiftUI') == 3
            and str(journey.h.target(snapshot, 'sidebar.toggle', binding)['value']) == '1',
            'final original sidebar state differs')
