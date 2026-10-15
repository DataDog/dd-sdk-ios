"""Prepare portable H10 guard controls with exact source-derived Codable models.

Only immutable data declarations are extracted; no UIKit implementation is replaced
or claimed to run. The actual new guard is compiled unchanged by the caller.
"""
import copy
import hashlib
import json
from pathlib import Path

from acceptance_common import require
from scene_background_cycle import PHASES
from test_scene_background_cycle import RUN, NATIVE, native, event, NOTIFICATIONS

HERE = Path(__file__).resolve().parent
PROBE = HERE.parents[2] / 'Datadog/Example/MultiSceneProbe/Sources/Harness'
SOURCES = {'ProbePhysicalTopologyAdmission.swift': '7b4ff1c0a0619c7481ca60c2b67c1021e8aca90ab7dbccd3b87d4f3ca2ebcabd',
           'ProbeSignal.swift': '25bb504353797f743c6d43904c80f1cfd277cc57b23a02445d5ef859bf25d832'}


def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def between(text, start, end):
    require(text.count(start) == 1, 'ambiguous model source')
    tail = text.split(start, 1)[1]
    require(end in tail, 'model source boundary missing')
    return start + tail.split(end, 1)[0]


def model_source():
    require(all(sha(PROBE / name) == digest for name, digest in SOURCES.items()), 'native model source changed')
    topology = (PROBE / 'ProbePhysicalTopologyAdmission.swift').read_text()
    signal = (PROBE / 'ProbeSignal.swift').read_text()
    parts = ['import Foundation\n', between(signal, 'internal struct ProbeGeometry:', '\n/// Only synthetic'),
             between(topology, 'internal struct ProbePhysicalSceneObservation:', '\ninternal struct ProbePhysicalTopologyObservation:')]
    for name, end in [('ProbePhysicalInputWindow', '\ninternal struct ProbePhysicalWindowInventory:'),
                      ('ProbePhysicalWindowInventory', '\ninternal struct ProbePhysicalSceneInventory:'),
                      ('ProbePhysicalSceneInventory', '\n/// Opt-in event history')]:
        parts.append(between(topology, 'internal struct ' + name + ':', end))
    ledger = between(topology, '    struct Owner: Codable, Equatable {', '    private let lock = NSLock()')
    parts.append('internal enum ProbePhysicalOperationEventLedger {\n' + ledger + '}\n')
    parts.append(between(topology, 'internal struct ProbePhysicalInputSnapshot:', '    @MainActor\n    func idleFailure()') + '}\n')
    witness = HERE / 'scene_background_witness.swift'
    require(sha(witness) == '41f836bd9cccf747583e836a52de675156cc620011264c2b91b5415599b75925', 'native witness source changed')
    parts.append(witness.read_text().split('extension ProbePhysicalOperationInput {', 1)[0])
    return '\n'.join(parts)


def positive():
    history = [event(1, 'sceneBackground'), event(2, 'sceneForeground')]
    steps = [dict(operation='arm', witness=copy.deepcopy(native('before', history)))]
    for index, (marker, scene, phase) in enumerate(PHASES):
        if index == 2: history.append(event(3, 'sceneBackground'))
        if index == 3: history += [event(4, 'sceneForeground'), event(5, 'sceneDeactivate', 'scene-B')]
        for operation in ['before', 'invoked', 'after']:
            step = dict(operation=operation, marker=marker, scene=scene, nativeSceneID=NATIVE[scene])
            if operation != 'invoked': step['witness'] = copy.deepcopy(native(phase, history))
            steps.append(step)
    return copy.deepcopy(dict(name='complete-inactive-peer-cycle', runID=RUN, steps=steps,
                              firstFailure=None, acceptedMarkers=5, completed=True))


def controls():
    cases = [positive()]
    def add(name, change, failure=None, accepted=5, completed=False):
        value = positive(); value.update(name=name, firstFailure=failure, acceptedMarkers=accepted, completed=completed)
        change(value['steps']); cases.append(value)
    def w(steps, index): return steps[index]['witness']
    def change_at(index, change): return lambda steps: change(w(steps, index))
    def append_event(value, kind, scene='scene-B', obj=None):
        history = value['snapshot']['continuity']['events']
        item = event(len(history) + 1, kind, scene)
        if obj is not None: item['objectIdentity'] = obj
        history.append(item)
    def auxiliary(steps):
        for step in steps:
            if 'witness' not in step: continue
            value = step['witness']; window = copy.deepcopy(value['snapshot']['inventory'][1]['windows'][0])
            window.update(identity='auxiliary', fixtureOwner=None, key=False)
            value['snapshot']['inventory'][1]['windows'].append(window)
            value['snapshot']['inventory'][1]['geometry']['width'] = 597.3333333333334
    add('auxiliary-window-and-fractional-geometry', auxiliary, completed=True)
    def benign(steps):
        for step in steps[1:]:
            if 'witness' not in step: continue
            value = step['witness']; history = value['snapshot']['continuity']['events']
            for item in history[2:]: item['revision'] += 1
            history.insert(2, event(3, 'registry-presentation', 'scene-B'))
    add('benign-peer-layout-event', benign, completed=True)
    add('before-arm', lambda s: s.pop(0), failure=0, accepted=0)
    add('reused-arm', lambda s: s.insert(1, copy.deepcopy(s[0])), failure=1, accepted=0)
    add('foreign-run', change_at(0, lambda v: v.update(runID='foreign')), failure=0, accepted=0)
    add('changed-notification-map', change_at(1, lambda v: v['notificationNames'].update(sceneBackground='foreign')), failure=1, accepted=0)
    add('wrong-marker', lambda s: s[1].update(marker='other'), failure=1, accepted=0)
    add('wrong-scene', lambda s: s[1].update(scene='scene-B'), failure=1, accepted=0)
    add('wrong-native-invocation', lambda s: s[2].update(nativeSceneID='foreign'), failure=2, accepted=1)
    add('missing-invocation', lambda s: s.pop(2), failure=2, accepted=1)
    add('repeated-invocation', lambda s: s.insert(3, copy.deepcopy(s[2])), failure=3, accepted=1)
    add('missing-after', lambda s: s.pop(3), failure=3, accepted=1)
    add('marker-after-completion', lambda s: s.append(copy.deepcopy(s[1])), failure=16, accepted=5)
    add('incomplete-final-marker', lambda s: s.pop(), accepted=5)
    add('stale-pre-arm-background', change_at(7, lambda v: v['snapshot']['continuity'].update(events=v['snapshot']['continuity']['events'][:2])), failure=7, accepted=2)
    add('background-before-instruction', change_at(1, lambda v: append_event(v, 'sceneBackground', 'scene-A')), failure=1, accepted=0)
    add('peer-background-hidden-between-captures', change_at(7, lambda v: append_event(v, 'sceneBackground')), failure=7, accepted=2)
    add('whole-app-background', change_at(7, lambda v: append_event(v, 'appBackground', None)), failure=7, accepted=2)
    add('missing-foreground', change_at(10, lambda v: v['snapshot']['continuity'].update(events=v['snapshot']['continuity']['events'][:3])), failure=10, accepted=3)
    add('unknown-event', change_at(1, lambda v: append_event(v, 'unrecognized-event')), failure=1, accepted=0)
    add('unbound-auxiliary-event', change_at(1, lambda v: append_event(v, 'windowVisible', None, 'foreign-window')), failure=1, accepted=0)
    add('lost-journal-row', change_at(7, lambda v: v['snapshot']['continuity']['events'].pop(0)), failure=7, accepted=2)
    add('rewritten-journal-prefix', change_at(7, lambda v: v['snapshot']['continuity']['events'][0].update(kind=NOTIFICATIONS['sceneActivate'])), failure=7, accepted=2)
    mutations = {
        'root-replaced': lambda v: v['snapshot']['scenes'][1].update(rootIdentity='replaced'),
        'observer-replaced': lambda v: v['snapshot']['input'][1].update(observerIdentity='replaced'),
        'generation-replaced': lambda v: v['snapshot']['input'][1].update(generation=1),
        'missing-connected-scene': lambda v: v['snapshot']['connectedSceneIDs'].pop(),
        'duplicate-window': lambda v: v['snapshot']['inventory'][1]['windows'].append(copy.deepcopy(v['snapshot']['inventory'][1]['windows'][0])),
        'disabled-window': lambda v: v['interaction'][1].update(windowEnabled=False),
        'disabled-root': lambda v: v['interaction'][1].update(rootEnabled=False),
        'foreign-interaction-owner': lambda v: v['interaction'][1].update(rootIdentity='foreign'),
        'held-touch': lambda v: v['snapshot']['input'][1].update(touches=1),
        'unreliable-input': lambda v: v['snapshot']['input'][1].update(reliable=False),
        'active-resize': lambda v: v['snapshot']['input'][1].update(resizing=True),
        'active-transition': lambda v: v['snapshot']['input'][1].update(transitioning=True),
        'hidden-peer': lambda v: v['snapshot']['scenes'][1].update(hidden=True),
        'unmounted-peer': lambda v: v['snapshot']['input'][1].update(mounted=False),
        'wrong-key-owner': lambda v: v['snapshot']['inventory'][1].update(keyWindowIdentity='foreign'),
        'zero-width': lambda v: v['snapshot']['inventory'][1]['geometry'].update(width=0),
        'journal-overflow': lambda v: v['snapshot']['continuity'].update(failure='overflow')}
    for name, change in mutations.items(): add(name, change_at(7, change), failure=7, accepted=2)
    return cases


def prepare(destination):
    destination = Path(destination)
    require(destination.is_absolute() and destination.resolve() == destination and not destination.exists(), 'fresh guard control output required')
    models = model_source(); cases = controls(); destination.mkdir()
    (destination / 'models.swift').write_text(models)
    (destination / 'controls.json').write_text(json.dumps(cases, indent=2) + '\n')
    files = [HERE / n for n in ['scene_background_guard.swift', 'scene_background_guard_check_main.swift',
                               'scene_background_guard_checks.py', 'scene_background_witness.swift',
                               'scene_background_cycle.py', 'test_scene_background_cycle.py', 'test_focus_activation_contract.py']]
    receipt = dict(state='PREPARED_SYNTHETIC_SWIFT_CONTROLS', source={str(p): sha(p) for p in files},
                   native_models={str(PROBE / p): digest for p, digest in SOURCES.items()},
                   models_sha256=sha(destination / 'models.swift'), controls_sha256=sha(destination / 'controls.json'),
                   controls=len(cases), native_runs=0, gates_closed=[])
    (destination / 'preparation.json').write_text(json.dumps(receipt, indent=2) + '\n')
    return receipt
