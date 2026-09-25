"""Held-gesture, stale acknowledgement and observer-ordering regression controls."""
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock, patch
import physical_capture
import physical_observer
import physical_release as release
import physical_transition
from capture_io import encoded
from acceptance_common import Rejected
from test_transition_contract import sample
import test_physical as transport_tests


IDENTITY=dict(run_id='run',pid=12,source='source',fixture='fixture',nonce='nonce',bundle='bundle')
BINDING=dict(window='window',root='root',scene='scene')


def idle_fixture():
    request=encoded(dict(schema_version=1,run_id='run',request_id='fresh-request',phase='cleanup.idle'))
    rows=[dict(sequence=1,run_id='run',kind='launch',payload=IDENTITY),
          dict(sequence=2,run_id='run',kind='human_failure',payload=dict(reason='observer failed')),
          dict(sequence=3,run_id='run',kind='human_snapshot',payload=dict(request_id='fresh-request',
            request_sha256=hashlib.sha256(request).hexdigest(),phase='cleanup.idle',
            input_state=dict(valid=True,**BINDING,pans=[dict(id='pan',state=0,touches=0)],coordinators=[]),
            topology=dict(**{'bound_'+k:v for k,v in BINDING.items()},window_alive=True,root_alive=True,bound_root_unchanged=True)))]
    return rows,request


def packed(rows):
    raw=b''.join(encoded(r) for r in rows)
    return raw,dict(schema_version=1,run_id='run',request_id='fresh-request',success=True,sequence=len(rows),
        byte_count=len(raw),sha256=hashlib.sha256(raw).hexdigest())


class Release(unittest.TestCase):
    def test_standalone_acknowledgement_command_publishes_bound_reply(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'request.json';now=time.time()
            request=dict(kind='HUMAN_RELEASE_REQUIRED',request_id='request',run_id='run',issued_at=now,deadline=now+30)
            raw=encoded(request);path.write_bytes(raw)
            result=subprocess.run([sys.executable,'-B',str(Path(release.__file__).resolve()),
                '--request',str(path),'--user-message','Released'],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            reply=json.loads(path.with_name('operator-released.json').read_bytes())
            release.validate_ack(request,raw,reply,time.time())
    def test_idle_cleanup_preserves_failure_and_cannot_qualify_scenario(self):
        rows,request=idle_fixture();raw,checkpoint=packed(rows)
        self.assertEqual(release.native_idle(raw,checkpoint,request,IDENTITY,BINDING)['state'],'NATIVE_INPUT_IDLE')
        with self.assertRaises(Rejected):physical_capture.driver.shared_capture.pending_rows(raw,'run')
        self.assertEqual(rows[1]['kind'],'human_failure')
    def test_held_gesture_touches_or_coordinator_defer_cleanup(self):
        for field,value in [('state',1),('state',2),('touches',1),('state',True)]:
            rows,request=idle_fixture();rows[-1]['payload']['input_state']['pans'][0][field]=value
            with self.subTest(field=field,value=value),self.assertRaises(Rejected):
                release.native_idle(*packed(rows),request,IDENTITY,BINDING)
        rows,request=idle_fixture();rows[-1]['payload']['input_state']['coordinators']=['active']
        with self.assertRaises(Rejected):release.native_idle(*packed(rows),request,IDENTITY,BINDING)
    def test_foreign_process_owner_or_stale_request_rejected(self):
        for field in ['pid','source','fixture','nonce','bundle']:
            rows,request=copy.deepcopy(idle_fixture());rows[0]['payload'][field]='other'
            with self.subTest(field=field),self.assertRaises(Rejected):release.native_idle(*packed(rows),request,IDENTITY,BINDING)
        for key in ['window','root','scene']:
            rows,request=idle_fixture();rows[-1]['payload']['input_state'][key]='other'
            with self.subTest(key=key),self.assertRaises(Rejected):release.native_idle(*packed(rows),request,IDENTITY,BINDING)
        rows,request=idle_fixture();rows[-1]['payload']['request_id']='old'
        with self.assertRaises(Rejected):release.native_idle(*packed(rows),request,IDENTITY,BINDING)
    def test_incomplete_writer_receipt_or_gesture_inventory_rejected(self):
        rows,request=idle_fixture();raw,receipt=packed(rows)
        for field,value in [('sha256','wrong'),('success',False),('sequence',2),('byte_count',len(raw)+1)]:
            bad=dict(receipt);bad[field]=value
            with self.subTest(field=field),self.assertRaises(Rejected):release.native_idle(raw,bad,request,IDENTITY,BINDING)
        for pans in [[],[dict(id='pan',state=0,touches=0)]*2]:
            rows,request=idle_fixture();rows[-1]['payload']['input_state']['pans']=pans
            with self.assertRaises(Rejected):release.native_idle(*packed(rows),request,IDENTITY,BINDING)
    def test_release_requires_fresh_bound_real_reply(self):
        request=dict(kind='HUMAN_RELEASE_REQUIRED',request_id='request',run_id='run',issued_at=100,deadline=200)
        raw=encoded(request);reply=dict(kind='OPERATOR_RELEASED',request_id='request',run_id='run',at=110,
            user_message='Released',request_sha256=hashlib.sha256(raw).hexdigest())
        release.validate_ack(request,raw,reply,120)
        for key,value in [('at',99),('at',121),('run_id','old'),('request_id','old'),('request_sha256','wrong'),('user_message','')]:
            changed=dict(reply);changed[key]=value
            with self.subTest(key=key),self.assertRaises(Rejected):release.validate_ack(request,raw,changed,120)
        with self.assertRaises(Rejected):release.validate_ack(request,raw,reply,201)
    def test_missing_release_never_queries_native_or_authorizes_cleanup(self):
        with tempfile.TemporaryDirectory() as directory:
            clock=[100.0];collector=Mock()
            with patch.object(release.time,'time',side_effect=lambda:clock[0]),patch.object(release.time,'sleep',side_effect=lambda _:clock.__setitem__(0,300)),patch('builtins.print'):
                with self.assertRaises(Rejected):release.fence(collector,Path(directory),IDENTITY,250)
            collector.cleanup_idle.assert_not_called()
            self.assertFalse((Path(directory)/'human-release/quiescent.json').exists())
    def test_native_query_happens_only_after_acknowledgement(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);clock=[100.0];collector=Mock()
            def reply(_):
                clock[0]=101;release.acknowledge(root/'human-release/request.json','Released')
            def native(*args):
                self.assertTrue((root/'human-release/operator-released.json').exists());return dict(state='NATIVE_INPUT_IDLE')
            collector.cleanup_idle.side_effect=native
            with patch.object(release.time,'time',side_effect=lambda:clock[0]),patch.object(release.time,'sleep',side_effect=reply),patch('builtins.print'):
                release.fence(collector,root,IDENTITY,250)
            self.assertTrue((root/'human-release/quiescent.json').exists())


def ordered(cancelled=False, delayed=True):
    rows,before,after=sample(cancelled)
    armed=rows[0]['payload'];armed.update(expected_from='detail',expected_to='home')
    sources=dict(edge='pan')
    armed['pop_recognizer_sources']=sources
    before['payload']['transition']['pop_recognizer_sources']=copy.deepcopy(sources)
    begin=next(r for r in rows if r['kind']=='transition_begin')['payload']
    begin.update(pan_began_uptime_ns=11,resolution_index=2 if delayed else 1,
                 resolution_probe='bound-probe',recognizer_state=2 if delayed else 1)
    pan=dict(kind='transition_pan_began',payload=dict(request_id='request',phase=before['payload']['phase'],
        uptime_ns=11,recognizer=copy.deepcopy(begin['recognizer']),expected_from='detail',expected_to='home'))
    candidate={k:begin[k] for k in ['coordinator','from','to','window','scene','interactive','initially_interactive','percent_complete']}
    def probe(index,coordinators):
        return dict(kind='transition_probe',payload=dict(request_id='request',phase=before['payload']['phase'],
            probe_id='bound-probe' if coordinators else 'waiting-probe',index=index,uptime_ns=11+index,
            recognizer=copy.deepcopy(begin['recognizer']),recognizer_state=1 if index==1 else 2,
            pan_began_uptime_ns=11,coordinators=coordinators))
    rows[2:2]=[pan]+([probe(1,[]),probe(2,[candidate])] if delayed else [probe(1,[candidate])])
    for row in rows:
        if row['kind'] in ['transition_begin','transition_registered','transition_change','transition_complete']:
            row['payload']['container']='container';row['payload']['container_present']=True
    end=next(r for r in rows if r['kind']=='transition_complete')
    end['payload'].update(active_record=True,completed_record=False,observer_failed=False,
        observer_request_id='request',interaction_changes=1,rejections=[],from_window='window',to_window='window',
        result_window='window',result_scene='scene',result_is_key=True,from_presenting='nil',to_presented='nil',
        controllers=copy.deepcopy(after['payload']['transition']['controllers']))
    observed=copy.deepcopy(end);observed['kind']='transition_terminal_observed';del observed['payload']['callback_id']
    rows.insert(rows.index(end),observed)
    for index,row in enumerate(rows,1):row['sequence']=index
    return rows,before,after


class ObserverOrdering(unittest.TestCase):
    def check(self,values,cancelled=False):
        return physical_transition.transition(*values,cancelled=cancelled,binding=dict(window='window',scene='scene'))
    def test_native_pan_then_still_interactive_resolution_and_completion(self):
        for cancelled in [False,True]:
            for delayed in [False,True]:self.check(ordered(cancelled,delayed),cancelled)
    def test_late_duplicate_or_foreign_resolution_rejected(self):
        for field,value in [('recognizer_state',3),('interactive',False),('resolution_index',3),('pan_began_uptime_ns',12),('from','other')]:
            rows,a,b=ordered();next(r for r in rows if r['kind']=='transition_begin')['payload'][field]=value
            with self.subTest(field=field),self.assertRaises(ValueError):self.check((rows,a,b))
        rows,a,b=ordered();rows.insert(2,copy.deepcopy(rows[2]))
        with self.assertRaises(ValueError):self.check((rows,a,b))
        rows,a,b=ordered();rows[2]['sequence']=8
        with self.assertRaises(ValueError):self.check((rows,a,b))
    def test_early_interaction_change_cannot_be_repaired_by_later_registration(self):
        rows,a,b=ordered();next(r for r in rows if r['kind']=='transition_change')['sequence']=6.5
        with self.assertRaises(ValueError):self.check((rows,a,b))
    def test_observed_coordinator_must_be_exact_unique_and_live(self):
        for field,value in [('from','foreign'),('to','foreign'),('window','foreign'),('scene','foreign'),
                            ('coordinator','foreign'),('interactive',False),('initially_interactive',False),
                            ('percent_complete',float('nan'))]:
            rows,a,b=ordered();probe=[r for r in rows if r['kind']=='transition_probe'][-1]
            probe['payload']['coordinators'][0][field]=value
            with self.subTest(field=field),self.assertRaises(ValueError):self.check((rows,a,b))
        rows,a,b=ordered();probe=[r for r in rows if r['kind']=='transition_probe'][-1]
        probe['payload']['coordinators'].append(dict(probe['payload']['coordinators'][0],coordinator='other'))
        with self.assertRaises(ValueError):self.check((rows,a,b))
    def test_no_rescue_after_an_earlier_registration_boundary(self):
        rows,a,b=ordered();probes=[r for r in rows if r['kind']=='transition_probe']
        probes[0]['payload']['coordinators']=copy.deepcopy(probes[1]['payload']['coordinators'])
        with self.assertRaises(ValueError):self.check((rows,a,b))
    def test_missing_reordered_ended_or_substituted_callback_rejected(self):
        for field,value in [('index',True),('index',3),('recognizer_state',3),('recognizer_state',True),
                            ('pan_began_uptime_ns',12),('probe_id','waiting-probe'),('uptime_ns',100)]:
            rows,a,b=ordered();probe=[r for r in rows if r['kind']=='transition_probe'][-1]
            probe['payload'][field]=value
            with self.subTest(field=field),self.assertRaises(ValueError):self.check((rows,a,b))
        rows,a,b=ordered();rows.remove(next(r for r in rows if r['kind']=='transition_probe'))
        with self.assertRaises(ValueError):self.check((rows,a,b))
    def test_original_rejected_native_attempt_cannot_be_qualified(self):
        rows,a,b=ordered();rows.append(dict(kind='human_failure',payload=dict(reason='original rejection')))
        with self.assertRaises(ValueError):self.check((rows,a,b))

    def test_unrelated_content_pan_cannot_satisfy_or_poison_bound_sheet_chain(self):
        rows,a,b=ordered();real=next(r for r in rows if r['kind']=='transition_pan_began')
        unrelated=copy.deepcopy(real);unrelated['payload']['recognizer']['id']='content-pan'
        a['payload']['transition']['armed'].append(unrelated['payload']['recognizer'])
        a['payload']['transition']['pop_recognizer_sources']['content']='content-pan'
        rows[0]['payload']['pop_recognizer_sources']['content']='content-pan'
        rows[0]['payload']['recognizers'].append(unrelated['payload']['recognizer'])
        probe=copy.deepcopy(next(r for r in rows if r['kind']=='transition_probe'))
        probe['payload'].update(probe_id='content-probe',recognizer=unrelated['payload']['recognizer'])
        terminal=dict(kind='transition_unmatched_pan_end',payload=dict(unrelated['payload'],recognizer_state=3,uptime_ns=12,pan_began_uptime_ns=11))
        rows[2:2]=[unrelated,probe,terminal]
        for index,row in enumerate(rows,1):row['sequence']=index
        for index,row in enumerate([r for r in rows if r['kind']=='transition_probe'],1):row['payload']['index']=index
        begin=next(r for r in rows if r['kind']=='transition_begin');begin['payload']['resolution_index']=3
        closed=next(r for r in rows if r['kind']=='transition_closed')
        closed['payload']['terminal_recognizers'].append(copy.deepcopy(unrelated['payload']['recognizer']))
        self.check((rows,a,b))
        rows.remove(terminal)
        with self.assertRaises(ValueError):self.check((rows,a,b))
    def test_overlay_preserves_the_frozen_source(self):
        path=Path(__file__).with_name('TransitionObservation.swift');raw=path.read_bytes();sha=hashlib.sha256(raw).hexdigest()
        result=physical_observer.render(raw,sha).decode()
        self.assertEqual(path.read_bytes(),raw)
        self.assertIn('navigation.interactivePopGestureRecognizer',result)
        self.assertIn('controller.presentationController?.containerView',result)
        self.assertNotIn('DispatchQueue.main.async',result)
        self.assertIn('owner?.observed(self, recognizer: recognizer)',result)
        self.assertNotIn('var pending: [UIView] = [window]; var seen',result)
        with self.assertRaises(ValueError):physical_observer.render(raw+b'changed','old')


class PublicPopSources(unittest.TestCase):
    check = ObserverOrdering.check
    def inventory(self, cancelled=False):
        rows, before, after = ordered(cancelled)
        original = copy.deepcopy(next(r for r in rows if r['kind']=='transition_begin')['payload']['recognizer'])
        def content(value):
            if isinstance(value, dict):
                if value.get('id') == 'pan' and 'edges' in value:
                    value['id'] = 'content-pan'; value.pop('edges')
                for child in value.values():content(child)
            elif isinstance(value, list):
                for child in value:content(child)
        content(rows)
        closed = next(r for r in rows if r['kind']=='transition_closed')['payload']
        inventories = [rows[0]['payload']['recognizers'], before['payload']['transition']['armed'],
                       closed['recognizers'], closed['terminal_recognizers']]
        seen = set()
        for inventory in inventories:
            if id(inventory) not in seen:inventory.append(copy.deepcopy(original)); seen.add(id(inventory))
        sources = dict(edge='pan', content='content-pan')
        rows[0]['payload']['pop_recognizer_sources'] = sources
        before['payload']['transition']['pop_recognizer_sources'] = copy.deepcopy(sources)
        return rows, before, after
    def test_content_pop_finish_and_cancel_keep_full_callback_contract(self):
        for cancelled in [False, True]:
            rows, before, after = self.inventory(cancelled)
            self.check((rows, before, after), cancelled)
            rows.remove(next(r for r in rows if r['kind']=='transition_begin'))
            with self.assertRaises(ValueError):self.check((rows, before, after), cancelled)
    def test_unbound_missing_or_unknown_public_sources_reject(self):
        for sources in [{}, dict(content='content-pan'), dict(edge='foreign', content='content-pan'),
                        dict(edge='pan', content=12), dict(edge='pan', content='content-pan', private='pan')]:
            rows, before, after = self.inventory()
            rows[0]['payload']['pop_recognizer_sources'] = sources
            before['payload']['transition']['pop_recognizer_sources'] = copy.deepcopy(sources)
            with self.subTest(sources=sources), self.assertRaises(ValueError):self.check((rows, before, after))
    def test_aliases_share_one_target_and_nil_content_retains_edge_fallback(self):
        for sources in [dict(edge='pan'), dict(edge='pan', content='nil'), dict(edge='pan', content='pan')]:
            rows, before, after = ordered()
            rows[0]['payload']['pop_recognizer_sources'] = sources
            before['payload']['transition']['pop_recognizer_sources'] = copy.deepcopy(sources)
            self.check((rows, before, after))
        rows, before, after = ordered()
        rows[0]['payload']['recognizers'].append(copy.deepcopy(rows[0]['payload']['recognizers'][0]))
        with self.assertRaises(ValueError):self.check((rows, before, after))
    def test_source_inventory_cannot_change_between_arm_and_snapshot(self):
        rows, before, after = self.inventory()
        before['payload']['transition']['pop_recognizer_sources']['edge'] = 'content-pan'
        with self.assertRaises(ValueError):self.check((rows, before, after))
    def test_overlay_uses_available_public_content_property_without_policy_changes(self):
        path=Path(__file__).with_name('TransitionObservation.swift');raw=path.read_bytes()
        rendered=physical_observer.render(raw,hashlib.sha256(raw).hexdigest()).decode()
        self.assertIn('if #available(iOS 26.0, *)',rendered)
        self.assertIn('navigation.interactiveContentPopGestureRecognizer',rendered)
        self.assertIn('popRecognizerSources',rendered)
        for mutation in ['.delegate =', '.isEnabled =', '.require(toFail:', 'DispatchQueue.main.async']:
            self.assertNotIn(mutation,rendered)
        self.assertEqual(path.read_bytes(),raw)


class TerminalContext(unittest.TestCase):
    check=ObserverOrdering.check
    def sheet(self, cancelled=False):
        rows,a,b=ordered(cancelled)
        for row in rows:
            phase=row['payload'].get('phase')
            if phase:row['payload']['phase']=phase.replace('pop.','dismiss.')
        before_graph=[dict(id='detail',window='window',presenting='home',presented='nil',children=[]),
                      dict(id='home',window='window',presenting='nil',presented='detail',children=[])]
        after_graph=copy.deepcopy(before_graph) if cancelled else [dict(before_graph[1],presented='nil')]
        a['payload']['transition'].update(controllers=before_graph,model=dict(path=['detail'],sheet=True))
        b['payload']['transition'].update(controllers=after_graph,model=dict(path=['detail'],sheet=cancelled))
        for payload in self.terminals(rows):
            payload.update(from_window='window' if cancelled else 'nil',from_presenting='home' if cancelled else 'nil',
                           to_presented='detail' if cancelled else 'nil',controllers=copy.deepcopy(after_graph))
        return rows,a,b
    def terminals(self, rows):
        return [r['payload'] for r in rows if r['kind'] in ['transition_terminal_observed','transition_complete']]
    def test_completed_sheet_can_detach_container_but_keeps_actual_return_owner(self):
        for detached in [False,True]:
            rows,a,b=self.sheet()
            for p in self.terminals(rows):
                if detached:p.update(window='nil',scene='nil',from_window='nil')
            self.check((rows,a,b))
            for p in self.terminals(rows):
                self.assertEqual(p['window'],'nil' if detached else 'window')
    def test_completed_sheet_can_lose_container_without_rewriting_actual_identity(self):
        rows,a,b=self.sheet()
        for p in self.terminals(rows):
            p.update(container='ObjectIdentifier(0x0000000000000000)',container_present=False,
                     window='nil',scene='nil',from_window='nil')
        self.check((rows,a,b))
        self.assertEqual(self.terminals(rows)[0]['container'],'ObjectIdentifier(0x0000000000000000)')
    def test_absent_container_is_not_allowed_for_pop(self):
        for cancelled in [False,True]:
            rows,a,b=ordered(cancelled)
            for p in self.terminals(rows):
                p.update(container='ObjectIdentifier(0x0000000000000000)',container_present=False,
                         window='nil',scene='nil',from_window='nil')
            with self.subTest(cancelled=cancelled),self.assertRaises(ValueError):self.check((rows,a,b),cancelled)
    def test_cancelled_sheet_retains_public_presentation_when_container_detaches_or_disappears(self):
        for present in [False,True]:
            for covered_presenter in [False,True]:
                rows,a,b=self.sheet(True)
                for p in self.terminals(rows):
                    p.update(container='container' if present else 'ObjectIdentifier(0x0000000000000000)',
                             container_present=present,window='nil',scene='nil',
                             to_window='nil' if covered_presenter else 'window')
                    p['controllers'][1]['window']=p['to_window']
                b['payload']['transition']['controllers'][1]['window']='nil' if covered_presenter else 'window'
                self.check((rows,a,b),True)
    def test_public_presentation_relation_cannot_be_inferred_from_return_window(self):
        for cancelled in [False,True]:
            for key,value in [('from_presenting','foreign'),('to_presented','foreign'),
                              ('from_presenting','nil' if cancelled else 'home'),
                              ('to_presented','nil' if cancelled else 'detail')]:
                rows,a,b=self.sheet(cancelled)
                for p in self.terminals(rows):p[key]=value
                with self.subTest(cancelled=cancelled,key=key,value=value),self.assertRaises(ValueError):
                    self.check((rows,a,b),cancelled)
    def test_original_presentation_graph_is_required_before_terminal_and_after(self):
        for cancelled in [False,True]:
            for boundary in ['before','terminal','after']:
                rows,a,b=self.sheet(cancelled)
                if boundary=='before':graphs=[a['payload']['transition']['controllers']]
                elif boundary=='after':graphs=[b['payload']['transition']['controllers']]
                else:graphs=[p['controllers'] for p in self.terminals(rows)]
                for graph in graphs:next(c for c in graph if c['id']=='home')['presented']='foreign'
                with self.subTest(cancelled=cancelled,boundary=boundary),self.assertRaises(ValueError):
                    self.check((rows,a,b),cancelled)
        rows,a,b=self.sheet(True)
        for p in self.terminals(rows):p['controllers'][1]['window']='foreign'
        with self.assertRaises(ValueError):self.check((rows,a,b),True)
    def test_terminal_graph_must_be_preserved_and_contain_the_return_controller(self):
        for make,cancelled in [(ordered,False),(ordered,True),(self.sheet,False),(self.sheet,True)]:
            rows,a,b=make(cancelled)
            for p in self.terminals(rows):p['controllers']=[]
            with self.subTest(make=make,cancelled=cancelled),self.assertRaises(ValueError):self.check((rows,a,b),cancelled)
    def test_presence_flag_cannot_hide_nonnull_replacement_or_null_identity(self):
        for identity,present in [('foreign',False),('ObjectIdentifier(0x0000000000000000)',True),('nil',False),('foreign',True)]:
            rows,a,b=self.sheet()
            for p in self.terminals(rows):p.update(container=identity,container_present=present,window='nil',scene='nil',from_window='nil')
            with self.subTest(identity=identity,present=present),self.assertRaises(ValueError):self.check((rows,a,b))
    def test_initial_and_interaction_change_container_must_exist(self):
        for kind in ['transition_begin','transition_registered','transition_change']:
            rows,a,b=self.sheet();p=next(r['payload'] for r in rows if r['kind']==kind)
            p.update(container='ObjectIdentifier(0x0000000000000000)',container_present=False)
            with self.subTest(kind=kind),self.assertRaises(ValueError):self.check((rows,a,b))
    def test_detached_pop_is_not_accepted(self):
        for make,cancelled in [(ordered,False),(ordered,True)]:
            rows,a,b=make(cancelled)
            for p in self.terminals(rows):p.update(window='nil',scene='nil')
            with self.subTest(make=make,cancelled=cancelled),self.assertRaises(ValueError):self.check((rows,a,b),cancelled)
    def test_foreign_or_missing_terminal_result_owner_stays_invalid(self):
        for key,value in [('window','foreign'),('scene','foreign'),('result_window','nil'),('result_window','foreign'),
                          ('result_scene','nil'),('result_scene','foreign'),('result_is_key',False),('result_is_key',1),
                          ('to_window','nil')]:
            rows,a,b=self.sheet()
            for p in self.terminals(rows):p[key]=value
            with self.subTest(key=key,value=value),self.assertRaises(ValueError):self.check((rows,a,b))
    def test_detached_container_requires_dismissed_endpoint_to_be_detached(self):
        rows,a,b=self.sheet()
        for p in self.terminals(rows):p.update(window='nil',scene='nil',from_window='foreign')
        with self.assertRaises(ValueError):self.check((rows,a,b))
    def test_terminal_predicate_failures_are_not_hidden_by_completion_row(self):
        for key,value in [('active_record',False),('completed_record',True),('observer_failed',True),
                          ('observer_request_id','old'),('interaction_changes',0),('interaction_changes',2),
                          ('interaction_changes',True),('rejections',['changed transition endpoints']),
                          ('from','foreign'),('to','foreign'),('container','foreign'),('current_request_id','old')]:
            rows,a,b=self.sheet()
            for p in self.terminals(rows):p[key]=value
            with self.subTest(key=key,value=value),self.assertRaises(ValueError):self.check((rows,a,b))
    def test_missing_repeated_or_late_terminal_observation_is_invalid(self):
        for change in ['missing','duplicate','late']:
            rows,a,b=self.sheet();observed=next(r for r in rows if r['kind']=='transition_terminal_observed')
            if change=='missing':rows.remove(observed)
            elif change=='duplicate':rows.insert(rows.index(observed),copy.deepcopy(observed))
            else:observed['sequence']=100
            with self.subTest(change=change),self.assertRaises(ValueError):self.check((rows,a,b))
    def test_substituting_original_window_for_actual_nil_is_invalid(self):
        rows,a,b=self.sheet()
        for p in self.terminals(rows):p.update(window='nil',scene='nil',from_window='nil')
        end=next(r['payload'] for r in rows if r['kind']=='transition_complete')
        end.update(window='window',scene='scene')
        with self.assertRaises(ValueError):self.check((rows,a,b))
    def test_terminal_success_still_requires_fresh_attached_result_graph(self):
        rows,a,b=self.sheet()
        for p in self.terminals(rows):p.update(window='nil',scene='nil',from_window='nil')
        b['payload']['transition']['controllers']=[]
        with self.assertRaises(ValueError):self.check((rows,a,b))
    def test_overlay_persists_rejected_context_before_guard(self):
        path=Path(__file__).with_name('TransitionObservation.swift');raw=path.read_bytes()
        value=physical_observer.render(raw,hashlib.sha256(raw).hexdigest()).decode()
        observed=value.index('ObservationStore.shared.append("transition_terminal_observed", observed)')
        guard=value.index('guard reasons.isEmpty else')
        self.assertLess(observed,guard)
        self.assertIn('"interaction_changes": record.changes, "rejections": reasons',value)
        self.assertIn('record.phase == "dismiss.finish.before" && !context.isCancelled',value)
        self.assertIn('resultWindow?.isKeyWindow != true',value)
        self.assertNotIn('"window": record.window',value)
        self.assertEqual(path.read_bytes(),raw)


class TransferRecovery(unittest.TestCase):
    setUp=transport_tests.Transport.setUp
    def failed_read(self,signature='(com.apple.dt.CoreDeviceError 7000 (NSPOSIXErrorDomain 60))',device='device'):
        raw=transport_tests.response(device=device);raw['info']['outcome']='failed';raw['errorSignature']=signature
        return raw,dict(returncode=1)
    def test_one_actual_second_read_recovers_socket_failure(self):
        failure=self.failed_read();calls=[]
        def pull(bundle,source,destination,label,deadline,check=True):
            calls.append(destination)
            if len(calls)==1:destination.write_bytes(b'partial');return failure
            destination.write_bytes(b'fresh actual bytes');return transport_tests.response(),dict(returncode=0)
        with patch.object(self.remote,'pull',side_effect=pull):
            actual=self.collector.download('events.jsonl',time.time()+30)
        self.assertEqual(actual,b'fresh actual bytes');self.assertEqual(len(calls),2)
        self.assertEqual(calls[0].read_bytes(),b'partial');self.assertTrue(calls[0].with_suffix('.failed-read.json').exists())
    def test_wrong_response_or_repeated_failure_is_not_retried_indefinitely(self):
        for failure,calls in [(self.failed_read('different'),1),(self.failed_read(device='wrong'),1),(self.failed_read(),2)]:
            with self.subTest(failure=failure),patch.object(self.remote,'pull',return_value=failure) as pull:
                with self.assertRaises(Rejected):self.collector.download('events.jsonl',time.time()+30)
                self.assertEqual(pull.call_count,calls)
    def test_expired_deadline_cannot_admit_a_second_transfer(self):
        with patch.object(self.remote,'pull',return_value=self.failed_read()) as pull:
            with self.assertRaises(Rejected):self.collector.download('events.jsonl',time.time()-1)
            pull.assert_not_called()
    def test_malformed_response_binding_never_recovers(self):
        for arguments in [['--device'],['--device','device','--device','device'],None]:
            failure=self.failed_read();failure[0]['info']['arguments']=arguments
            with self.subTest(arguments=arguments),patch.object(self.remote,'pull',return_value=failure) as pull:
                with self.assertRaises(Rejected):self.collector.download('events.jsonl',time.time()+30)
                self.assertEqual(pull.call_count,1)
    def test_late_actual_success_is_not_published(self):
        clock=[100.0]
        def pull(bundle,source,destination,label,deadline,check=True):
            destination.write_bytes(b'late actual bytes');clock[0]=111
            return transport_tests.response(),dict(returncode=0)
        with patch.object(physical_capture.time,'time',side_effect=lambda:clock[0]),patch.object(self.remote,'pull',side_effect=pull):
            with self.assertRaises(Rejected):self.collector.download('events.jsonl',110)
        self.assertFalse((self.collector.documents/'events.jsonl').exists())


if __name__=='__main__':unittest.main()
