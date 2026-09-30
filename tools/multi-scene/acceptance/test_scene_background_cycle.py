"""Synthetic H10 boundary controls. Never a physical run or release verdict."""
import copy
import json
import unittest

from acceptance_common import Rejected
import scene_background_cycle as c
from test_focus_activation_contract import snapshot, backend

RUN = 'synthetic-h10-only'
NATIVE = {'scene-A': 'native-A', 'scene-B': 'native-B'}
NOTIFICATIONS = {k: 'synthetic.' + k for k in c.NAMES}


def event(revision, kind, scene='scene-A'):
    owner = snapshot('scene-B', NATIVE)['continuity']['owners'][c.SCENES.index(scene)] if scene else None
    return dict(revision=revision, kind=NOTIFICATIONS.get(kind, kind), owner=owner,
                objectIdentity=owner['sceneIdentity'] if owner else None)


def native(phase, history):
    value = snapshot('scene-B', NATIVE)
    for scene, inventory in zip(value['scenes'], value['inventory']):
        label = scene['logicalSceneID']
        state = ('background' if phase == 'background' else 'foreground-inactive') if label == 'scene-A' else 'foreground-active'
        if phase == 'foreground': state = 'foreground-active' if label == 'scene-A' else 'foreground-inactive'
        scene['activationState'] = inventory['activationState'] = state
        inventory['keyWindowIdentity'] = scene['windowIdentity'] if state == 'foreground-active' else None
        inventory['windows'][0]['key'] = state == 'foreground-active'
    value['continuity']['events'] = copy.deepcopy(history)
    interaction = [dict(logicalSceneID=o['logicalSceneID'], windowIdentity=o['windowIdentity'],
                        rootIdentity=o['rootIdentity'], windowEnabled=True, rootEnabled=True)
                   for o in value['continuity']['owners']]
    return dict(schemaVersion=1, runID=RUN, scenarioID=c.SCENARIO, profile=c.PROFILE,
                notificationNames=NOTIFICATIONS, snapshot=value, interaction=interaction)


def fixture():
    signals = []
    def put(kind, **kwargs):
        signals.append(dict(schemaVersion=5, sequence=len(signals)+1, runID=RUN,
                            scenarioID=c.SCENARIO, kind=kind, **kwargs))
    def view(identifier, scene, active=True, version=1):
        put('rum-view-snapshot', evidenceSource='rum-mapper',
            semanticContext=dict(logicalSceneID=scene, nativeSceneID=NATIVE[scene], screen='home'),
            rumContext=dict(viewID=identifier, sessionID='session-unit', viewName='Home '+scene,
                            viewActive=active, viewDocumentVersion=version))
    def guard(name, phase, history):
        put('assertion', evidenceSource='probe', result='PASS', name=name,
            reason=json.dumps(native(phase, history)))
    # Earlier setup activity is fully inventoried, independent of critical IDs.
    view('setup-A', 'scene-A'); view('setup-A', 'scene-A', False, 2)
    view('A-current', 'scene-A'); view('B-current', 'scene-B')
    history = [event(1, 'sceneBackground'), event(2, 'sceneForeground')]
    guard('h10.arm', 'before', history)
    for index, (marker, scene, phase) in enumerate(c.PHASES):
        if index == 2: history.append(event(3, 'sceneBackground'))
        if index == 3:
            history += [event(4, 'sceneForeground'), event(5, 'sceneDeactivate', 'scene-B')]
        guard('h10.before.' + marker, phase, history)
        put('assertion', evidenceSource='probe', result='PASS', stepKind='emit-scene-context-marker',
            name='h10.invoke.' + marker, semanticContext=dict(logicalSceneID=scene, nativeSceneID=NATIVE[scene]))
        guard('h10.after.' + marker, phase, history)
    # Serialization after the synchronous native sequence is intentionally valid.
    view('A-current', 'scene-A', False, 2); view('A-returned', 'scene-A')
    view('B-current', 'scene-B', True, 4); view('B-current', 'scene-B', True, 2)
    for marker, scene, _ in c.PHASES:
        owner = 'B-current' if scene == 'scene-B' else 'A-returned' if marker == 'A.after-foreground' else 'A-current'
        for kind in ['action', 'resource']:
            put('rum-'+kind, evidenceSource='rum-mapper', eventID=kind+'-'+marker, name=marker,
                rumContext=dict(viewID=owner, sessionID='session-unit'),
                sourceContext=dict(logicalSceneID=scene, nativeSceneID=NATIVE[scene], phase=marker))
    return signals


def renumber(rows):
    for i, row in enumerate(rows): row['sequence'] = i+1
    return rows


def mutate(rows, change, selector=lambda s: True):
    for signal in rows:
        if 'reason' in signal and selector(signal):
            value = json.loads(signal['reason']); change(value); signal['reason'] = json.dumps(value)


class BackgroundCycleTests(unittest.TestCase):
    def validate(self, rows): return c.validate_local(rows, RUN, profile=c.PROFILE)

    def test_complete_cycle_accepts_delayed_mapper_setup_and_inactive_peer(self):
        value = self.validate(fixture())
        self.assertEqual(value['state'], 'PASS_LOCAL_COMPONENT_ONLY')
        self.assertEqual((len(value['work']), len(value['views'])), (10, 4))
        self.assertEqual(value['native']['arm_revision'], 2)
        self.assertEqual(value['native']['background_revisions'], [3])
        self.assertEqual(value['native']['foreground_revisions'], [4])
        self.assertFalse(value['display_qualified']); self.assertEqual(value['gates_closed'], [])

    def test_auxiliary_windows_geometry_and_long_elapsed_time_are_not_gates(self):
        rows = fixture()
        for signal in rows: signal['timestampMilliseconds'] = signal['sequence'] * 1_000_000_000
        def change(value):
            inventory = value['snapshot']['inventory'][1]
            inventory['geometry']['width'] = 597.3333333333334
            inventory['windows'].append(dict(identity='auxiliary', key=False, fixtureOwner=None, sceneMatches=True))
        mutate(rows, change); self.validate(rows)

    def test_native_owner_inventory_and_input_discriminators(self):
        def changes(case, v):
            s=v['snapshot']; b=s['scenes'][1]; i=s['input'][1]; w=s['inventory'][1]
            if case == 'owner': b['rootIdentity']='replaced'
            if case == 'generation': b['generation']=1
            if case == 'observer': i['observerIdentity']='replaced'
            if case == 'connected': s['connectedSceneIDs'].pop()
            if case == 'duplicate-window': w['windows'].append(copy.deepcopy(w['windows'][0]))
            if case == 'hidden': b['hidden']=True
            if case == 'zero-alpha': b['alpha']=0
            if case == 'nan': b['geometry']['x']=float('nan')
            if case == 'disabled-root': v['interaction'][1]['rootEnabled']=False
            if case == 'disabled-window': v['interaction'][1]['windowEnabled']=False
            if case == 'interaction-owner': v['interaction'][1]['rootIdentity']='foreign'
            if case == 'unmounted': i['mounted']=False
            if case == 'held': i['touches']=1
            if case == 'unreliable': i['reliable']=False
            if case == 'transition': i['transitioning']=True
            if case == 'resizing': i['resizing']=True
            if case == 'wrong-key': w['keyWindowIdentity']='foreign'
            if case == 'failure': s['continuity']['failure']='overflow'
        for case in ['owner','generation','observer','connected','duplicate-window','hidden','zero-alpha','nan',
                     'disabled-root','disabled-window','interaction-owner','unmounted','held','unreliable',
                     'transition','resizing','wrong-key','failure']:
            rows=fixture(); mutate(rows, lambda v: changes(case,v), lambda s:s['name']=='h10.after.B.while-A-background')
            with self.subTest(case=case), self.assertRaises(Rejected): self.validate(rows)

    def test_no_background_credit_from_stale_or_replaced_journal(self):
        for case in ['stale','gap','reset','changed-prefix','foreign-owner','unowned','wrong-object','reversed','repeated-cycle']:
            rows=fixture()
            def change(v):
                events=v['snapshot']['continuity']['events']
                if case=='stale': events[:]=events[:2]
                elif case=='gap': events[-1]['revision']+=1
                elif case=='reset': events[:]=[]
                elif case=='changed-prefix': events[0]['kind']='changed'
                elif case=='foreign-owner': events[-1]['owner']['nativeSceneID']='other'
                elif case=='unowned': events[-1]['owner']=None
                elif case=='wrong-object': events[-1]['objectIdentity']='auxiliary'
                elif case=='reversed': events[-1]['kind']=NOTIFICATIONS['sceneForeground']
                else: events.append(event(len(events)+1,'sceneBackground'))
            selected='h10.after.B.after-A-foreground' if case=='repeated-cycle' else 'h10.after.B.while-A-background'
            mutate(rows,change,lambda s:s['name']==selected)
            with self.subTest(case=case),self.assertRaises(Rejected): self.validate(rows)

    def test_transient_peer_background_disconnect_hide_and_app_background_reject(self):
        for case in ['sceneBackground','sceneForeground','sceneDisconnect','appBackground','windowHidden']:
            rows=fixture()
            def change(v):
                events=v['snapshot']['continuity']['events']; e=event(len(events)+1,case,'scene-B')
                if case=='windowHidden': e['objectIdentity']=e['owner']['windowIdentity']
                events.append(e)
            mutate(rows,change,lambda s:s['name']=='h10.after.B.after-A-foreground')
            with self.subTest(case=case),self.assertRaises(Rejected): self.validate(rows)

    def test_known_peer_focus_key_geometry_resize_and_auxiliary_events_are_allowed(self):
        rows=fixture()
        def change(v):
            events=v['snapshot']['continuity']['events']
            for kind in ['sceneActivate','sceneDeactivate','windowKey','windowResignKey',
                         'registry-registration','registry-ready','registry-presentation',
                         'reader-presentation','resize-began','resize-ended']:
                value=event(len(events)+1,kind,'scene-B')
                if kind.startswith('window'):value['objectIdentity']=value['owner']['windowIdentity']
                events.append(value)
            v['snapshot']['inventory'][1]['windows'].append(dict(identity='aux-window',key=False,fixtureOwner=None,sceneMatches=True))
            events.append(dict(revision=len(events)+1,kind=NOTIFICATIONS['windowHidden'],owner=None,objectIdentity='aux-window'))
        mutate(rows,change,lambda s:s['name']=='h10.after.B.after-A-foreground');self.validate(rows)

    def test_ownerless_window_event_requires_a_real_auxiliary_inventory_entry(self):
        for identity in ['arbitrary', 'window-scene-A', 'window-scene-B', None]:
            rows=fixture()
            def change(v):
                events=v['snapshot']['continuity']['events']
                events.append(dict(revision=len(events)+1,kind=NOTIFICATIONS['windowHidden'],owner=None,objectIdentity=identity))
            mutate(rows,change,lambda s:s['name']=='h10.after.B.after-A-foreground')
            with self.subTest(identity=identity),self.assertRaisesRegex(Rejected,'auxiliary inventory'):self.validate(rows)

    def test_unknown_or_unowned_native_events_do_not_pass_continuity(self):
        for kind,scene in [('unknown-lifecycle','scene-A'),('unknown-owner','scene-B'),('unknown',None),
                           ('registry-route','scene-B'),('registry-disconnect','scene-A'),
                           ('sceneActivate',None),('reader-presentation',None)]:
            rows=fixture()
            def change(v):
                events=v['snapshot']['continuity']['events'];events.append(event(len(events)+1,kind,scene))
            mutate(rows,change,lambda s:s['name']=='h10.after.B.after-A-foreground')
            with self.subTest(kind=kind,scene=scene),self.assertRaises(Rejected):self.validate(rows)

    def test_intended_A_background_is_required_only_in_middle_phase(self):
        rows=fixture()
        def change(v):
            v['snapshot']['scenes'][0]['activationState']='foreground-inactive'
            v['snapshot']['inventory'][0]['activationState']='foreground-inactive'
        mutate(rows,change,lambda s:s['name']=='h10.before.B.while-A-background')
        with self.assertRaises(Rejected): self.validate(rows)

    def test_missing_late_and_foreign_invocation_cannot_borrow_native_guards(self):
        for case in ['missing','late','foreign','duplicate','unknown']:
            rows=fixture(); signal=next(s for s in rows if s.get('name')=='h10.invoke.B.while-A-background')
            if case=='missing': rows.remove(signal)
            elif case=='late': rows.remove(signal);rows.append(signal)
            elif case=='foreign':signal['semanticContext']['nativeSceneID']='foreign'
            elif case=='duplicate':rows.append(copy.deepcopy(signal))
            else:signal['name']='h10.unknown'
            renumber(rows)
            with self.subTest(case=case),self.assertRaises(Rejected): self.validate(rows)

    def test_mapper_peer_end_A_reuse_extra_views_and_duplicate_documents_reject(self):
        for case in ['peer-end','no-A-stop','A-reuse','foreign-current','extra-view','duplicate-document','retired-initial']:
            rows=fixture(); old=next(s for s in rows if s.get('rumContext',{}).get('viewID')=='A-current')
            peer=next(s for s in rows if s.get('rumContext',{}).get('viewID')=='B-current')
            if case=='peer-end':peer['rumContext']['viewActive']=False
            elif case=='no-A-stop':
                for s in rows:
                    if s.get('rumContext',{}).get('viewID')=='A-current':s['rumContext']['viewActive']=True
            elif case=='A-reuse':
                for s in rows:
                    if s.get('name')=='A.after-foreground':s['rumContext']['viewID']='A-current'
            elif case=='foreign-current':
                for s in rows:
                    if s.get('name')=='B.after-A-foreground':s['rumContext']['viewID']='A-returned'
            elif case=='extra-view':
                added=copy.deepcopy(old);added['rumContext']['viewID']='extra';rows.append(added)
            elif case=='duplicate-document':rows.append(copy.deepcopy(peer))
            else:old['rumContext']['viewActive']=False
            renumber(rows)
            with self.subTest(case=case),self.assertRaises(Rejected):self.validate(rows)

    def test_absent_swapped_duplicate_or_foreign_work_rejects(self):
        for case in ['missing','duplicate','owner','event-id','source','session','run','profile']:
            rows=fixture(); work=next(s for s in rows if s.get('kind')=='rum-resource')
            if case=='missing':rows.remove(work)
            elif case=='duplicate':rows.append(copy.deepcopy(work))
            elif case=='owner':work['rumContext']['viewID']='B-current'
            elif case=='event-id':work['eventID']=''
            elif case=='source':work['sourceContext']['nativeSceneID']='other'
            elif case=='session':work['rumContext']['sessionID']='other'
            elif case=='run':work['runID']='old'
            else:
                mutate(rows,lambda v:v.update(profile='physical-focus-activation-only'))
            renumber(rows)
            with self.subTest(case=case),self.assertRaises(Rejected):self.validate(rows)

    def test_mapper_work_before_native_boundary_is_rejected(self):
        rows=fixture(); work=next(s for s in rows if s.get('kind')=='rum-action')
        rows.remove(work); rows.insert(4,work);renumber(rows)
        with self.assertRaisesRegex(Rejected,'predates'):self.validate(rows)

    def test_ended_A_document_cannot_reactivate_the_same_ID(self):
        rows=fixture(); old=next(s for s in rows if s.get('kind')=='rum-view-snapshot'
                              and s['rumContext'].get('viewID')=='A-current')
        for version,active in [(3,True),(4,False)]:
            extra=copy.deepcopy(old);extra['rumContext'].update(viewDocumentVersion=version,viewActive=active);rows.append(extra)
        renumber(rows)
        with self.assertRaisesRegex(Rejected,'end once'):self.validate(rows)

    def test_complete_backend_joins_setup_and_selected_work(self):
        local=self.validate(fixture()); rows,identity=backend(local)
        for row in rows:row['attributes']['custom']['context']['probe']['run_id']=RUN
        self.assertEqual(c.validate_backend(local,RUN,rows,len(rows),identity=identity)['marker_pairs'],5)
        for case in ['missing','duplicate','owner','application','run','error']:
            values=copy.deepcopy(rows)
            if case=='missing':values.pop()
            elif case=='duplicate':values.append(copy.deepcopy(values[-1]))
            elif case=='owner':values[-1]['attributes']['custom']['view']['id']='A-current'
            elif case=='application':values[-1]['attributes']['custom']['application']['id']='other'
            elif case=='run':values[-1]['attributes']['custom']['context']['probe']['run_id']='old'
            else:values[-1]['attributes']['custom']['type']='error'
            with self.subTest(case=case),self.assertRaises(Rejected):
                c.validate_backend(local,RUN,values,len(rows),identity=identity)


if __name__ == '__main__': unittest.main()
