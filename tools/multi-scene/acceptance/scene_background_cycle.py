"""H10 cycle oracle over a sealed, source-bound capture; no native authority.

The caller must qualify the manifest, installed process, raw transfer, display and
cleanup. Notification names come from the native adapter's typed UIKit constants.
All fixture input below is evidence to validate, never an instruction to execute.
"""
import json
import math

from acceptance_common import require, unique
from physical_same_key_contract import validate_backend as complete_backend_inventory

SCENARIO = 'windows.isolated-background-foreground'
PROFILE = 'physical-isolated-background-foreground'
SCENES = ['scene-A', 'scene-B']
PHASES = [('A.before-background', 'scene-A', 'before'),
          ('B.before-background', 'scene-B', 'before'),
          ('B.while-A-background', 'scene-B', 'background'),
          ('A.after-foreground', 'scene-A', 'foreground'),
          ('B.after-A-foreground', 'scene-B', 'foreground')]
NAMES = {'sceneActivate', 'sceneDeactivate', 'sceneForeground', 'sceneBackground', 'sceneDisconnect',
         'windowVisible', 'windowHidden', 'windowKey', 'windowResignKey',
         'appResignActive', 'appActive', 'appBackground', 'appForeground'}
# These are the literal kinds emitted by the existing source-bound native ledger.
GEOMETRY_EVENTS = {'registry-registration', 'registry-ready', 'registry-presentation',
                   'reader-presentation', 'resize-began', 'resize-ended'}
FG = {'foreground-active', 'foreground-inactive'}


def positive(value):
    return type(value) in (int, float) and math.isfinite(value) and value > 0


def geometry(value):
    require(isinstance(value, dict) and all(type(value.get(k)) in (int, float)
            and math.isfinite(value[k]) for k in ['x', 'y', 'width', 'height'])
            and positive(value['width']) and positive(value['height']), 'invalid native geometry')


def capture(signal, run_id, phase, owners=None):
    require(signal.get('kind') == 'assertion' and signal.get('evidenceSource') == 'probe'
            and signal.get('result') == 'PASS', 'invalid H10 native witness')
    try:
        value = json.loads(signal['reason'])
    except (KeyError, TypeError, ValueError):
        require(False, 'malformed H10 native witness')
    require(isinstance(value, dict) and value.get('schemaVersion') == 1
            and value.get('runID') == run_id and value.get('scenarioID') == SCENARIO
            and value.get('profile') == PROFILE, 'foreign H10 native witness')
    names = value.get('notificationNames', {})
    require(set(names) == NAMES and all(isinstance(v, str) and v for v in names.values())
            and len(set(names.values())) == len(NAMES), 'missing typed notification names')
    snapshot = value.get('snapshot', {})
    continuity = snapshot.get('continuity', {})
    require(snapshot.get('failure') is None and continuity.get('failure') is None
            and snapshot.get('applicationActive') is True, 'native observation failed')
    fields = ['owners', 'scenes', 'input', 'interaction']
    rows = [continuity.get('owners', []), snapshot.get('scenes', []),
            snapshot.get('input', []), value.get('interaction', [])]
    for field, items in zip(fields, rows):
        require(isinstance(items, list) and all(isinstance(x, dict) for x in items)
                and [x.get('logicalSceneID') for x in items] == SCENES, 'incomplete ' + field)
    observed, scenes, inputs, interactions = rows
    for key in ['nativeSceneID', 'sceneIdentity', 'windowIdentity', 'rootIdentity']:
        require(all(isinstance(x.get(key), str) and x[key] for x in observed)
                and len({x[key] for x in observed}) == 2, 'aliased native ' + key)
    require(all(type(x.get('generation')) is int and x['generation'] >= 0 for x in observed),
            'invalid owner generation')
    bindings = {x['logicalSceneID']: dict(x, observerIdentity=i.get('observerIdentity'))
                for x, i in zip(observed, inputs)}
    require(all(isinstance(x['observerIdentity'], str) and x['observerIdentity'] for x in bindings.values())
            and len({x['observerIdentity'] for x in bindings.values()}) == 2, 'aliased input observer')
    if owners is not None:
        require(bindings == owners, 'native owner or observer changed')
    native = sorted(x['nativeSceneID'] for x in observed)
    inventory = snapshot.get('inventory', [])
    require(snapshot.get('connectedSceneIDs') == native
            and isinstance(inventory, list) and sorted(x.get('nativeSceneID', '') for x in inventory) == native,
            'incomplete connected-scene inventory')
    for owner, scene, input_row, interaction in zip(observed, scenes, inputs, interactions):
        label = owner['logicalSceneID']
        for key in ['logicalSceneID', 'nativeSceneID', 'generation', 'windowIdentity', 'rootIdentity']:
            require(scene.get(key) == input_row.get(key) == owner[key], 'owner snapshot differs')
        require(interaction.get('windowIdentity') == owner['windowIdentity']
                and interaction.get('rootIdentity') == owner['rootIdentity']
                and all(type(interaction.get(k)) is bool for k in ['windowEnabled', 'rootEnabled']),
                'interaction flags are not bound to original owners')
        require(scene.get('connected') is True and all(input_row.get(k) is True for k in ['attached', 'enabled', 'reliable'])
                and type(input_row.get('touches')) is int and input_row['touches'] == 0
                and input_row.get('transitioning') is False and input_row.get('resizing') is False,
                'input is held, unobservable or transitioning')
        item = unique([x for x in inventory if x.get('nativeSceneID') == owner['nativeSceneID']], 'scene inventory')
        state = scene.get('activationState')
        require(item.get('activationState') == state, 'native activation observations differ')
        background = phase == 'background' and label == 'scene-A'
        require(state == 'background' if background else state in FG,
                'A phase or usable B foreground state differs', 'INCONCLUSIVE')
        windows = item.get('windows', [])
        require(isinstance(windows, list) and all(isinstance(w.get('identity'), str) and w['identity'] for w in windows)
                and len({w['identity'] for w in windows}) == len(windows), 'invalid complete window inventory')
        window = unique([w for w in windows if w.get('fixtureOwner') == label], 'fixture-owned window')
        require(window['identity'] == owner['windowIdentity'] and window.get('rootIdentity') == owner['rootIdentity']
                and window.get('sceneMatches') is True, 'fixture window or controller differs')
        key = item.get('keyWindowIdentity')
        require([w['identity'] for w in windows if w.get('key') is True] == ([] if key is None else [key]),
                'key window inventory differs')
        geometry(scene.get('geometry')); geometry(item.get('geometry')); geometry(item.get('screenGeometry'))
        if not background:
            require(scene.get('hidden') is False and positive(scene.get('alpha'))
                    and window.get('hidden') is False and positive(window.get('alpha'))
                    and window.get('mounted') is True and input_row.get('mounted') is True
                    and interaction['windowEnabled'] and interaction['rootEnabled'], 'foreground owner is not usable')
            geometry(window.get('geometry'))
            if state == 'foreground-active':
                require(key == owner['windowIdentity'], 'active fixture does not own its key window')
    events = continuity.get('events')
    require(isinstance(events, list) and all(isinstance(e, dict) and type(e.get('revision')) is int for e in events)
            and [e['revision'] for e in events] == list(range(1, len(events) + 1)), 'lost or reordered lifecycle history')
    all_windows = [w for item in inventory for w in item['windows']]
    require(len({w['identity'] for w in all_windows}) == len(all_windows), 'window appears in two scene inventories')
    auxiliary = {w['identity'] for w in all_windows if w.get('fixtureOwner') is None and w.get('sceneMatches') is True}
    require(not auxiliary.intersection(o['windowIdentity'] for o in observed), 'owned window classified as auxiliary')
    return bindings, events, names, auxiliary


def cycle(events, owners, names, arm_revision, phase, auxiliary):
    background, foreground = [], []
    for event in events[arm_revision:]:
        kind, owner = event.get('kind'), event.get('owner')
        require(isinstance(kind, str) and kind in set(names.values()) | GEOMETRY_EVENTS,
                'unknown or unsupported native event kind')
        if owner is not None:
            require(isinstance(owner, dict) and owner.get('logicalSceneID') in owners, 'foreign native event owner')
            expected = {k: v for k, v in owners[owner['logicalSceneID']].items() if k != 'observerIdentity'}
            require(owner == expected and event.get('objectIdentity') in [owner['sceneIdentity'], owner['windowIdentity']],
                    'native event owner or object differs')
        if kind in GEOMETRY_EVENTS or kind in [names['sceneActivate'], names['sceneDeactivate']]:
            require(owner is not None and event.get('objectIdentity') == owner['sceneIdentity'],
                    'unowned scene or geometry event')
        if kind in [names['windowVisible'], names['windowHidden'], names['windowKey'], names['windowResignKey']]:
            if owner:
                require(event.get('objectIdentity') == owner['windowIdentity'], 'window event has a different object')
            else:
                require(event.get('objectIdentity') in auxiliary, 'unowned window event lacks auxiliary inventory binding')
        require(kind not in [names['appBackground'], names['appForeground']],
                'whole application changed foreground membership', 'INCONCLUSIVE')
        if kind in [names['sceneBackground'], names['sceneForeground'], names['sceneDisconnect']]:
            require(owner is not None and event.get('objectIdentity') == owner['sceneIdentity'], 'unowned scene lifecycle')
            require(kind != names['sceneDisconnect'], 'scene disconnected during H10', 'INCONCLUSIVE')
            require(owner['logicalSceneID'] == 'scene-A', 'B changed foreground membership', 'INCONCLUSIVE')
            (background if kind == names['sceneBackground'] else foreground).append(event['revision'])
        if kind == names['windowHidden'] and event.get('objectIdentity') == owners['scene-B']['windowIdentity']:
            require(False, 'B fixture window became hidden', 'INCONCLUSIVE')
    if phase == 'before':
        require(not background and not foreground, 'cycle started before its armed instruction')
    elif phase == 'background':
        require(background and not foreground, 'fresh A background boundary missing')
    else:
        require(background and foreground and max(background) < min(foreground), 'fresh ordered A cycle missing')
    return background, foreground


def validate_native(signals, run_id):
    expected = [('h10.arm', 'before')]
    for marker, _, phase in PHASES:
        expected += [(f'h10.before.{marker}', phase), (f'h10.after.{marker}', phase)]
    witnesses = [s for s in signals if str(s.get('name', '')).startswith(('h10.arm', 'h10.before.', 'h10.after.'))]
    require([s.get('name') for s in witnesses] == [x[0] for x in expected], 'missing, duplicate or reordered H10 witness')
    owners = None; previous = []; names = None; arm_revision = None; auxiliary = set()
    for witness, (_, phase) in zip(witnesses, expected):
        bindings, events, typed_names, observed_auxiliary = capture(witness, run_id, phase, owners)
        auxiliary.update(observed_auxiliary)
        if owners is None:
            owners, names, arm_revision = bindings, typed_names, len(events)
        require(typed_names == names and events[:len(previous)] == previous, 'lifecycle journal or typed names replaced')
        boundaries = cycle(events, owners, names, arm_revision, phase, auxiliary)
        previous = events
    invocations = [s for s in signals if str(s.get('name', '')).startswith('h10.invoke.')]
    require([s.get('name') for s in invocations] == ['h10.invoke.' + m for m, _, _ in PHASES],
            'missing or repeated marker invocation')
    for invocation, (marker, scene, _) in zip(invocations, PHASES):
        before = unique([s for s in witnesses if s['name'] == 'h10.before.' + marker], 'before invocation')
        after = unique([s for s in witnesses if s['name'] == 'h10.after.' + marker], 'after invocation')
        require(invocation.get('kind') == 'assertion' and invocation.get('result') == 'PASS'
                and invocation.get('evidenceSource') == 'probe' and invocation.get('stepKind') == 'emit-scene-context-marker'
                and before['sequence'] < invocation['sequence'] < after['sequence']
                and invocation.get('semanticContext', {}).get('logicalSceneID') == scene
                and invocation.get('semanticContext', {}).get('nativeSceneID') == owners[scene]['nativeSceneID'],
                'marker was not invoked between its fresh native guards')
    require(len([s for s in signals if str(s.get('name', '')).startswith('h10.')]) == len(witnesses) + len(invocations),
            'unknown H10 assertion')
    return dict(owners=owners, arm_sequence=witnesses[0]['sequence'], end_sequence=witnesses[-1]['sequence'],
                arm_revision=arm_revision, background_revisions=boundaries[0], foreground_revisions=boundaries[1])


def validate_local(signals, run_id, *, profile):
    """Consume the complete sealed signal prefix, including delayed mapper rows."""
    require(profile == PROFILE and isinstance(signals, list) and signals, 'wrong H10 capture/profile')
    require(all(type(s.get('sequence')) is int and s['sequence'] == i + 1 and s.get('schemaVersion') == 5
                and s.get('runID') == run_id and s.get('scenarioID') == SCENARIO for i, s in enumerate(signals)),
            'foreign or incomplete H10 signal stream')
    require(not any(s.get('kind') == 'rum-error' or s.get('result') in ['FAIL', 'INCONCLUSIVE', 'SKIPPED'] for s in signals),
            'failed assertion or RUM error in H10 capture')
    native = validate_native(signals, run_id)
    views, documents, view_scenes, first_seen, initial_documents = {}, {}, {}, {}, {}
    for signal in signals:
        if signal.get('kind') != 'rum-view-snapshot': continue
        context = signal.get('rumContext', {}); view = context.get('viewID'); session = context.get('sessionID')
        require(signal.get('evidenceSource') == 'rum-mapper' and isinstance(view, str) and view
                and isinstance(session, str) and session and type(context.get('viewActive')) is bool
                and type(context.get('viewDocumentVersion')) is int and context['viewDocumentVersion'] > 0,
                'missing independent View state')
        identity = dict(view_id=view, session_id=session, name=context.get('viewName'))
        require(view not in views or views[view] == identity, 'View identity mutated')
        views[view] = identity; first_seen.setdefault(view, signal['sequence'])
        document = context['viewDocumentVersion']; documents.setdefault(view, {})
        require(document not in documents[view], 'duplicate View document')
        documents[view][document] = context['viewActive']
        if signal['sequence'] < native['arm_sequence']:
            initial_documents.setdefault(view, {})[document] = context['viewActive']
        semantic = signal.get('semanticContext') or {}; scene = semantic.get('logicalSceneID')
        if scene in SCENES:
            require(semantic.get('screen') == 'home' and semantic.get('nativeSceneID') == native['owners'][scene]['nativeSceneID'],
                    'wrong Home native owner')
            require(view not in view_scenes or view_scenes[view] == scene, 'View scene changed')
            view_scenes[view] = scene
    require(views and len({v['session_id'] for v in views.values()}) == 1, 'foreign RUM session')
    session = next(iter(views.values()))['session_id']; work = []
    for signal in signals:
        if signal.get('kind') not in ['rum-action', 'rum-resource']: continue
        context = signal.get('rumContext', {}); source = signal.get('sourceContext', {})
        require(signal.get('evidenceSource') == 'rum-mapper' and context.get('sessionID') == session
                and context.get('viewID') in views and isinstance(signal.get('eventID'), str) and signal['eventID'],
                'unknown work identity or owner')
        marker = unique([x for x in PHASES if x[0] == signal.get('name')], 'known H10 marker')
        guard = unique([s for s in signals if s.get('name') == 'h10.before.' + marker[0]], 'pre-invocation witness')
        require(signal['sequence'] > guard['sequence'], 'work predates its native ownership boundary')
        require(source.get('phase') == marker[0] and source.get('logicalSceneID') == marker[1]
                and source.get('nativeSceneID') == native['owners'][marker[1]]['nativeSceneID']
                and view_scenes.get(context['viewID']) == marker[1], 'source label or actual mapper owner differs')
        work.append(dict(kind=signal['kind'].removeprefix('rum-'), event_id=signal['eventID'], session_id=session,
                         view_id=context['viewID'], phase=marker[0], source_scene=marker[1]))
    require(len(work) == 10 and len({(w['kind'], w['event_id']) for w in work}) == 10, 'missing or duplicated work')
    marker_owners = {}
    for marker, _, _ in PHASES:
        pair = [unique([w for w in work if w['phase'] == marker and w['kind'] == kind], marker + ' ' + kind)
                for kind in ['action', 'resource']]
        require(pair[0]['view_id'] == pair[1]['view_id'], 'Action and Resource owner differ')
        marker_owners[marker] = pair[0]['view_id']
    a0, b0, bm, a1, b1 = [marker_owners[m] for m, _, _ in PHASES]
    require(len({a0, b0, a1}) == 3 and b0 == bm == b1, 'A did not restart or B current occurrence changed', 'FAIL')
    for view, scene in [(a0, 'scene-A'), (b0, 'scene-B')]:
        active = {v for v, docs in initial_documents.items()
                  if view_scenes.get(v) == scene and docs[max(docs)] is True}
        require(active == {view}, 'initial current occurrence absent or ambiguous before arm')
    require(first_seen[a1] > native['arm_sequence'], 'foreground occurrence reuses setup View')
    activity = [documents[a0][version] for version in sorted(documents[a0])]
    require(activity[0] is True and activity[-1] is False and activity == sorted(activity, reverse=True),
            'original A View did not end once', 'FAIL')
    require(all(documents[b0].values()) and all(documents[a1].values()), 'current A or peer B View ended', 'FAIL')
    critical = {a0, b0, a1}
    require({v for v in views if first_seen[v] >= native['arm_sequence']} <= critical,
            'unexpected new View during the critical cycle', 'FAIL')
    return dict(state='PASS_LOCAL_COMPONENT_ONLY', profile=PROFILE, session_id=session, views=list(views.values()),
                work=work, marker_owners=marker_owners, native=native, display_qualified=False,
                native_process_qualified=False, cleanup_qualified=False, gates_closed=[])


def validate_backend(local, run_id, rows, count, *, identity):
    require(set(identity) == {'application_id', 'service', 'source'} and all(isinstance(v, str) and v for v in identity.values()),
            'missing backend identity')
    require(type(count) is int and count >= 0, 'invalid backend count')
    for row in rows:
        value = row.get('attributes', {}).get('custom', {})
        require(value.get('application', {}).get('id') == identity['application_id']
                and value.get('service') == identity['service'] and value.get('source') == identity['source'],
                'foreign backend application/service/source')
    result = complete_backend_inventory(local, run_id, rows, count)
    result.update(state='PASS_BACKEND_COMPONENT_ONLY', marker_pairs=5, gates_closed=[])
    return result
