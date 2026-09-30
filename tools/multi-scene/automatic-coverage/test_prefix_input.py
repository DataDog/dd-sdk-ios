"""Offline false-pass and stop controls; these never call a native tool."""
import copy
import json
from pathlib import Path
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import human_supported_session as evidence
import prefix_input as inputs
import prefix_sequence as sequence
import prefix_session as transport
import test_human_contract as fixtures


def fixture(kind='tap'):
    base = fixtures.NativeInputControls(); base.setUp()
    step = next(s for s in inputs.journey.flow('split','initial') if s['kind'] == kind)
    topology = copy.deepcopy(base.topology); topology['framework'] = 'SwiftUI'
    topology['accessibility'] = [dict(id='marker',identifier='screen.sidebar',frame_in_window=[20,20,80,30]),
        dict(id='control',identifier=step['target'],frame_in_window=[20,100,300,100],value='1'),
        dict(id='receipt',identifier='sidebar.receipt',frame_in_window=[20,220,80,30],label='receipt:3')]
    topology['scrolls'] = [dict(id='control',accessibility_id=step['target'],owned=True,window='window',scene='scene',
        enabled=True,hidden=False,alpha=1,tracking=False,dragging=False,decelerating=False,offset=[0,0])]
    before = copy.deepcopy(base.evidence[2]); before['payload'].update(phase=step['phase']+'.before',topology=topology)
    role = {'tap':'Button','toggle':'Switch','scroll':'ScrollView'}[kind]
    label = ", label: '" + ('Tap' if kind=='tap' else 'Enable') + "'" if kind!='scroll' else ''
    raw = "Application bundle identifier: fixture\nApplication UI orientation: Portrait\nApplication, pid: 123, label: 'Fixture'\n"
    raw += " Window, {{0.0, 0.0}, {400.0, 800.0}}, hitPoint: {200.0, 400.0}\n"
    raw += "  StaticText, {{20.0, 20.0}, {80.0, 30.0}}, identifier: 'screen.sidebar', hitPoint: {60.0, 35.0}\n"
    raw += f"  {role}, {{{{20.0, 100.0}}, {{300.0, 100.0}}}}, identifier: '{step['target']}'{label}, hitPoint: {{170.0, 150.0}}\n"
    if kind=='toggle': raw += "   Switch, {{250.0, 120.0}, {60.0, 30.0}}, value: 0, hitPoint: {280.0, 135.0}\n"
    return raw,before,step,base.binding


class CoordinateControls(unittest.TestCase):
    def select(self, data): return inputs.select(*data,'fixture',123)
    def test_taps_use_current_hit_point(self):
        self.assertEqual(self.select(fixture())['command'],'t 170 150')
    def test_nested_switch_replaces_stretched_parent_center(self):
        self.assertEqual(self.select(fixture('toggle'))['command'],'t 280 135')
    def test_scroll_preserves_downward_direction(self):
        result=self.select(fixture('scroll')); self.assertEqual(result['command'],'t 170 150 f 170 190 0.6')
        self.assertFalse(result['provenance']['original_amplitude_reproduced'])
    def test_roundoff_is_accepted_but_moved_control_is_not(self):
        raw,before,step,binding=fixture(); before['payload']['topology']['accessibility'][1]['frame_in_window'][0]+=.04
        self.select((raw,before,step,binding))
        before['payload']['topology']['accessibility'][1]['frame_in_window'][0]+=1
        with self.assertRaises(ValueError):self.select((raw,before,step,binding))
    def test_wrong_app_pid_phase_marker_label_or_remote_control_rejected(self):
        raw,before,step,binding=fixture()
        mutations=[raw.replace('pid: 123','pid: 124'), raw.replace('identifier: fixture','identifier: other'),
            raw.replace("label: 'Tap'","label: 'Delete'"), raw.replace('screen.sidebar','screen.detail'),
            raw.replace("identifier: 'sidebar.tap'", "identifier: 'sidebar.tap', activationBundleId: fixture"),
            raw.replace("identifier: 'sidebar.tap'", "identifier: 'sidebar.tap', isRemoteLeafPlaceholder"),
            raw.replace('hitPoint: {170.0, 150.0}','hitPoint: {390.0, 150.0}')]
        for text in mutations:
            with self.subTest(text=text),self.assertRaises(ValueError):self.select((text,before,step,binding))
        before['payload']['phase']='old.before'
        with self.assertRaises(ValueError):self.select((raw,before,step,binding))
    def test_duplicate_control_and_nested_switch_rejected(self):
        for kind in ('tap','toggle'):
            raw,before,step,binding=fixture(kind); raw+=raw.splitlines()[-1]+'\n'
            with self.subTest(kind=kind),self.assertRaises(ValueError):self.select((raw,before,step,binding))
    def test_parent_without_nested_switch_is_not_a_toggle_guess(self):
        raw,before,step,binding=fixture('toggle');raw='\n'.join(raw.splitlines()[:-1])+'\n'
        with self.assertRaises(ValueError):self.select((raw,before,step,binding))
    def test_scroll_must_be_owned_idle_enabled_at_original_offset(self):
        for key,value in [('owned',False),('window','other'),('scene','other'),('enabled',False),('hidden',True),
                          ('tracking',True),('dragging',True),('decelerating',True),('offset',[0,40])]:
            raw,before,step,binding=fixture('scroll');before['payload']['topology']['scrolls'][0][key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):self.select((raw,before,step,binding))
    def test_consumed_foreign_gapped_or_replaced_native_prefix_rejected(self):
        _,before,_,_=fixture();rows=[dict(run_id='run',sequence=1,kind='launch',payload={}),
            dict(run_id='run',sequence=2,kind='human_window_binding',payload={}),before]
        raw=b''.join(json.dumps(r).encode()+b'\n' for r in rows)
        inputs.unconsumed(raw,raw,'run',before)
        for kind in (*inputs.INPUT_KINDS,'human_snapshot','human_failure'):
            changed=raw+json.dumps(dict(run_id='run',sequence=4,kind=kind,payload={})).encode()+b'\n'
            with self.subTest(kind=kind),self.assertRaises(ValueError):inputs.unconsumed(changed,raw,'run',before)
        with self.assertRaises(ValueError):inputs.unconsumed(raw.replace(b'"run"',b'"old"'),raw,'run',before)
        with self.assertRaises(ValueError):inputs.unconsumed(raw[:-1],raw,'run',before)
        with self.assertRaises(ValueError):inputs.unconsumed(raw+b'{"sequence":4',raw,'run',before)
    def test_final_sidebar_requires_both_original_counter_and_toggle(self):
        _,before,_,binding=fixture('toggle');inputs.final_state(before,binding)
        for key,value in [('value','0'),('value',None)]:
            before['payload']['topology']['accessibility'][1][key]=value
            with self.assertRaises(ValueError):inputs.final_state(before,binding)
    def test_upward_or_stationary_scroll_cannot_match_original_direction(self):
        _,before,step,_=fixture('scroll');before['sequence']=1;after={'sequence':4}
        for offset in (0,20,-20):
            rows=[dict(sequence=2,kind='human_scroll_begin',payload={'scroll':{'offset':[0,0]}}),
                  dict(sequence=3,kind='human_scroll_end',payload={'scroll':{'offset':[0,offset]}})]
            if offset<0:inputs.scroll_direction(rows,before,after,step)
            else:
                with self.assertRaises(ValueError):inputs.scroll_direction(rows,before,after,step)


class TransportControls(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name)
        self.calls=[];self.fail=None;self.late=False
        self.session=transport.Session(self.root,dict(owner='worker',device='device',bundle='fixture',run_id='run',
            plan_sha256='a'*64,product_sha256='b'*64),seconds=120,deadline=time.time()+300,emit=self.worker)
    def worker(self, text):
        path=Path(json.loads(text)['automatic_prefix_tool']['request']);request=evidence.read(path)
        admitted=transport.dispatch_or_reject(path,'worker')
        if admitted['state']=='NO_CALL':return
        started=time.time();self.calls.append(request['operation'])
        if request['operation']=='start':value={'deviceUUID':'device','deviceIsSimulator':True,'interactionSessionKey':'actual-key'}
        elif request['operation']=='end':value={'userMessage':'Session stopped'}
        else:
            hierarchy=path.with_name('actual.txt');image=path.with_name('actual.png')
            hierarchy.write_text(fixture()[0]);image.write_bytes(b'\x89PNG\r\n\x1a\nfixture')
            value={'applicationState':'Running','hierarchyPath':str(hierarchy),'screenshotPath':str(image)}
        raw={'structuredContent':value}
        if self.fail==request['operation']:raw={'isError':True,'content':[{'type':'text','text':'actual tool failure'}]}
        finish=time.time() if not self.late else request['deadline']+1
        transport.publish(path,raw,owner='worker',started_at=started,finished_at=finish)
    def test_actual_session_and_raw_captures_are_bound_and_ended(self):
        self.session.start();self.session.capture(123);self.session.end(time.time()+120)
        self.assertEqual(self.calls,['start','capture','end'])
        self.assertEqual(evidence.read(self.root/'worker-completed.json')['input_commands'],0)
        self.assertTrue((self.root/'initial/returned-actual.png').exists() is False)
        self.assertTrue((self.root/'initial/returned-screenshot.png').exists())
    def test_error_is_preserved_then_end_runs_without_retry(self):
        self.session.start();self.fail='capture'
        with self.assertRaises(ValueError):self.session.capture(123)
        self.assertTrue(evidence.read(self.root/'initial/tool-result.json')['isError'])
        self.session.end(time.time()+120);self.assertEqual(self.calls,['start','capture','end'])
    def test_late_return_is_preserved_without_acceptance_or_retry(self):
        self.late=True
        with self.assertRaises(ValueError):self.session.start()
        self.assertTrue((self.root/'start/tool-result.json').is_file());self.assertEqual(self.calls,['start'])
    def test_duplicate_dispatch_and_changed_session_cannot_be_consumed(self):
        self.session.start()
        with self.assertRaises(FileExistsError):transport.dispatch(self.root/'start/request.json','worker')
        self.session.key='remembered-key'
        with self.assertRaises(ValueError):self.session.capture(123)
        self.assertEqual(self.calls,['start'])
    def test_start_error_never_invents_a_session_for_cleanup(self):
        self.fail='start'
        with self.assertRaises(ValueError):self.session.start()
        with self.assertRaises(ValueError):self.session.end(time.time()+120)
        self.assertEqual(self.calls,['start'])
    def test_artifact_copy_failure_is_published_without_waiting_for_timeout(self):
        self.session.start()
        with patch.object(transport,'artifacts',side_effect=OSError('retained copy unavailable')):
            with self.assertRaisesRegex(ValueError,'could not be preserved'):self.session.capture(123)
        self.assertEqual(evidence.read(self.root/'initial/response.json')['artifact_error'],'retained copy unavailable')
        self.assertTrue((self.root/'initial/tool-result.json').is_file())
        self.session.end(time.time()+120)
    def test_one_action_has_truthful_completion_count_and_cannot_repeat(self):
        self.session.start();self.session.capture(123)
        _,before,step,binding=fixture()
        rows=[dict(run_id='run',sequence=1,kind='launch',payload={}),
              dict(run_id='run',sequence=2,kind='human_window_binding',payload=binding),before]
        raw=b''.join(json.dumps(r).encode()+b'\n' for r in rows)
        documents=self.root/'documents';documents.mkdir();(documents/'events.jsonl').write_bytes(raw)
        capture=SimpleNamespace(binding=binding,prefix=raw,run='run',documents=documents,
                                process_identity='original-process',live=lambda deadline:None)
        import human_release
        with patch.object(human_release,'process_identity',return_value='original-process'):
            self.session.input(1,step,capture,before,time.time()+120)
            with self.assertRaises(ValueError):self.session.input(1,step,capture,before,time.time()+120)
        self.session.end(time.time()+120)
        self.assertEqual(self.calls,['start','capture','capture','action','end'])
        self.assertEqual(evidence.read(self.root/'worker-completed.json')['input_commands'],1)
    def test_changed_process_stops_before_any_action(self):
        self.session.start();self.session.capture(123)
        _,before,step,binding=fixture()
        rows=[dict(run_id='run',sequence=1,kind='launch',payload={}),
              dict(run_id='run',sequence=2,kind='human_window_binding',payload=binding),before]
        raw=b''.join(json.dumps(r).encode()+b'\n' for r in rows)
        documents=self.root/'documents';documents.mkdir();(documents/'events.jsonl').write_bytes(raw)
        capture=SimpleNamespace(binding=binding,prefix=raw,run='run',documents=documents,
                                process_identity='original',live=lambda deadline:None)
        import human_release
        with patch.object(human_release,'process_identity',return_value='replaced'):
            with self.assertRaisesRegex(ValueError,'worker did not dispatch: input process changed'):
                self.session.input(1,step,capture,before,time.time()+120)
        failed=evidence.read(self.root/'01-action/response.json')
        self.assertEqual(failed['kind'],'AUTOMATIC_PREFIX_NO_CALL')
        self.assertFalse((self.root/'01-action/tool-result.json').exists())
        self.assertFalse((self.root/'01-action/dispatch.json').exists())
        self.session.end(time.time()+120)
        self.assertNotIn('action',self.calls)


class SequenceControls(unittest.TestCase):
    def test_saved_ordinary_payloads_need_separate_idle_snapshots(self):
        # Replay one original effect with source-shaped idle captures. This is
        # an offline transport control, not a new native observation.
        root=Path('/Users/valentin.pertuisot/work/dd-sdk-ios-extractions/evidence/s2-split-prefix-0oeq73m2')
        selected=evidence.read(root/'prefix-binding.json')['steps'][0]
        for key in ('before','after'):
            self.assertEqual(evidence.reference(selected[key]['path']),selected[key])
        raw=Path(selected['after']['path']).read_bytes()
        rows=[json.loads(line) for line in raw.splitlines()]
        binding=next(r['payload'] for r in rows if r['kind']=='human_window_binding')
        before=next(r for r in rows if r['sequence']==selected['before_sequence'])
        after=next(r for r in rows if r['sequence']==selected['after_sequence'])
        ready=next(r for r in rows if r['kind']=='human_snapshot' and r['payload']['phase']=='cleanup.idle')
        self.assertNotIn('input_state',before['payload']);self.assertNotIn('input_state',after['payload'])
        import human_release
        with tempfile.TemporaryDirectory() as temporary:
            folder=Path(temporary);(folder/'events.jsonl').write_bytes(raw)
            calls=[];sent=[]
            capture=SimpleNamespace(binding=binding,module=SimpleNamespace(human_release=human_release),
                documents=folder,prefix=Path(selected['before']['path']).read_bytes(),run=before['run_id'],live=lambda _:None)
            def snapshot(name,phase,deadline):
                calls.append(phase)
                if phase=='cleanup.idle':
                    if not sent:return ready,rows[:ready['sequence']]
                    idle=copy.deepcopy(after);idle['sequence']=len(rows)+1
                    idle['payload'].update(phase=phase,input_state=copy.deepcopy(ready['payload']['input_state']))
                    return idle,rows+[idle]
                return (before,rows[:before['sequence']]) if phase.endswith('.before') else (after,rows)
            capture.snapshot=snapshot
            session=SimpleNamespace(input=lambda *args:sent.append(args),input_commands=1)
            with patch.object(sequence.journey,'flow',return_value=[selected['step']]):
                with self.assertRaisesRegex(ValueError,'incomplete original input sequence'):
                    sequence.run(capture,session,folder/'prefix',dict(step=90,passive_snapshot=30,settle=0),time.time()+120)
            self.assertEqual(len(sent),1)
            self.assertEqual(calls,['cleanup.idle',before['payload']['phase'],after['payload']['phase'],'cleanup.idle'])
            self.assertEqual(evidence.read(folder/'prefix/01-effect.json')['effect'],{'kind':'tap','callback':33})

    def test_first_input_failure_stops_without_another_step_or_effect(self):
        with tempfile.TemporaryDirectory() as temporary:
            _,before,_,binding=fixture()
            capture=SimpleNamespace(binding=binding,module=SimpleNamespace(human_release=SimpleNamespace(input_idle=lambda *a:True)))
            calls=[]
            def snapshot(*args):
                calls.append(args)
                if args[1]=='cleanup.idle':
                    row=copy.deepcopy(before);row['payload'].update(phase='cleanup.idle',input_state={});row['sequence']=2
                    return row,[row]
                self.assertNotIn('input_state',before['payload'])
                return before,[before]
            capture.snapshot=snapshot
            session=SimpleNamespace(input=lambda *a:(_ for _ in ()).throw(ValueError('actual failed input')))
            with self.assertRaisesRegex(ValueError,'actual failed input'):
                sequence.run(capture,session,Path(temporary)/'prefix',dict(step=90,passive_snapshot=30,settle=1),time.time()+120)
            self.assertEqual(len(calls),2)
            self.assertEqual(calls[0][1],'cleanup.idle')
    def test_exact_phase_set_contains_no_home_or_extra_gesture(self):
        self.assertEqual(len(sequence.phases()),26)
        self.assertFalse(any('home' in p or 'fold' in p for p in sequence.phases()))


if __name__=='__main__':unittest.main()
