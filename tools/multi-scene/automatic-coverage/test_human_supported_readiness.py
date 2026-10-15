"""Prompt reachability controls; no native execution or human acknowledgement."""
import copy
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace as NS
import unittest
from unittest.mock import Mock, patch

import human_supported_readiness as r


class ReadinessTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.out=Path(self.temp.name)/'runtime/cells/cell';self.out.mkdir(parents=True)
        self.collector=NS(pid=123,deadline=1000,run='fresh-run',device='Duo',binding={'scene':'s'},evidence=[])
        self.stage=dict(runtime_plan_sha256='a'*64,page={'nonce':'current'})
        self.enterContext(patch('builtins.print'))

    def test_protocol_failure_cannot_reach_ready_or_ordinary_prompts(self):
        for boundary in ('capture','native','end','ready'):
            with self.subTest(boundary=boundary):
                events=[]
                def call(name):
                    events.append(name)
                    if name==boundary:raise ValueError(name)
                session=NS(capture=lambda _:call('capture'),end=lambda _:call('end'))
                with (patch.object(r,'native_ready',side_effect=lambda *_:call('native')),
                      patch.object(r,'human_ready',side_effect=lambda *_:call('ready'))):
                    with self.assertRaises(ValueError):r.qualify(session,self.collector,self.out,self.stage,None,'stack')
                self.assertEqual(events,['capture','native','end','ready'][:['capture','native','end','ready'].index(boundary)+1])

    def test_closure_precedes_ready(self):
        events=[]
        session=NS(capture=lambda _:events.append('capture'),end=lambda _:events.append('end'))
        with (patch.object(r,'native_ready',side_effect=lambda *_:events.append('native')),
              patch.object(r,'human_ready',side_effect=lambda *_:events.append('ready'))):
            r.qualify(session,self.collector,self.out,self.stage,None,'stack')
        self.assertEqual(events,['capture','native','end','ready'])

    def native_context(self, *, idle=True):
        # Match the frozen observer: ordinary snapshots omit input_state;
        # a separate cleanup.idle request supplies the actual native inventory.
        self.collector.snapshot=lambda *_:({'payload':{'topology':{}}},self.out)
        self.collector.evidence=[dict(kind='launch',payload={'bundle':'fixture','layout':'stack'})]
        def capture_idle(folder,identity,deadline):
            self.assertEqual(identity,{'run_id':self.collector.run,'bundle':'fixture'})
            self.assertEqual(deadline,self.collector.deadline)
            if not idle:raise ValueError('native idle unproven')
            return dict(state='NATIVE_INPUT_IDLE',run_id=self.collector.run,request_id='fresh-idle')
        self.collector.cleanup_idle=Mock(side_effect=capture_idle)
        return NS(journey=NS(ready_controls=lambda *_:dict(counter=0, identifiers=r.readiness_profile('stack')['identifiers'])),
                  capture=NS(oracle=NS(one=lambda values,_:values[0])))

    def test_ordinary_snapshot_requires_separate_idle_proof(self):
        runner=self.native_context()
        r.native_ready(self.collector,'phase',runner,'stack')
        proof=r.supported.read(self.out/'input-idle/proof.json')
        self.assertEqual(proof['request_id'],'fresh-idle')
        self.assertTrue((self.out/'controls-ready.json').exists())

    def test_native_active_input_is_not_ready(self):
        runner=self.native_context(idle=False)
        with self.assertRaisesRegex(ValueError,'idle unproven'):r.native_ready(self.collector,'phase',runner,'stack')
        self.assertFalse((self.out/'controls-ready.json').exists())

    def test_already_consumed_input_is_not_ready(self):
        runner=self.native_context()
        for kind in ('human_callback','native_input','human_scroll_begin','human_scroll_end','native_background'):
            self.collector.evidence=[{'kind':kind}]
            with self.subTest(kind=kind),self.assertRaisesRegex(ValueError,'input occurred'):
                r.native_ready(self.collector,'phase',runner,'stack')
        self.collector.cleanup_idle.assert_not_called()

    def split_context(self):
        import human_journey as journey
        from test_human_contract import NativeInputControls
        fixture=NativeInputControls();fixture.setUp()
        snapshot=copy.deepcopy(fixture.evidence[2]);topology=snapshot['payload']['topology']
        topology['framework']='SwiftUI';topology['accessibility']=[];topology['scrolls']=[]
        for screen,x in [('sidebar',10),('empty',210)]:
            for i,name in enumerate(['screen','tap','toggle','scroll','receipt','next']):
                if screen=='empty' and name=='next':continue
                topology['accessibility'].append(dict(
                    identifier='screen.'+screen if name=='screen' else screen+'.'+name,
                    label='receipt:0' if name=='receipt' else name,
                    frame_in_window=[x,40+i*80,180,40],hidden=False,alpha=1))
            topology['scrolls'].append(dict(id=screen+'-scroll',owned=True,window='window',scene='scene',
                hidden=False,alpha=1,enabled=True,frame_in_window=[x,280,180,40]))
        runner=self.native_context();runner.journey=journey
        self.collector.binding=fixture.binding
        self.collector.evidence=[dict(kind='launch',payload={'bundle':'fixture','layout':'split'})]
        self.collector.snapshot=lambda *_:(snapshot,self.out)
        return runner,topology

    def test_split_sidebar_qualifies_with_a_separate_visible_empty_pane(self):
        runner,_=self.split_context()
        proof=r.native_ready(self.collector,'phase',runner,'split')
        self.assertEqual(proof['scroll_id'],'sidebar-scroll')
        self.assertEqual(proof['identifiers'],r.readiness_profile('split')['identifiers'])

    def test_split_sidebar_does_not_require_a_visible_empty_pane(self):
        runner,topology=self.split_context()
        topology['accessibility']=[v for v in topology['accessibility'] if 'empty' not in v['identifier']]
        topology['scrolls']=topology['scrolls'][:1]
        self.assertEqual(r.native_ready(self.collector,'phase',runner,'split')['scroll_id'],'sidebar-scroll')

    def test_wrong_native_layout_is_rejected_before_readiness(self):
        runner=self.native_context()
        with self.assertRaisesRegex(ValueError,'layout differs'):
            r.native_ready(self.collector,'phase',runner,'split')
        self.collector.cleanup_idle.assert_not_called()
        self.assertFalse((self.out/'controls-ready.json').exists())

    def test_split_empty_pane_cannot_replace_missing_sidebar_controls(self):
        runner,topology=self.split_context()
        for identifier in r.readiness_profile('split')['identifiers']:
            before=copy.deepcopy(topology['accessibility'])
            topology['accessibility']=[v for v in before if v['identifier']!=identifier]
            with self.subTest(identifier=identifier),self.assertRaises(ValueError):
                r.native_ready(self.collector,'phase',runner,'split')
            topology['accessibility']=before
        self.collector.cleanup_idle.assert_not_called()

    def test_split_hidden_sidebar_cannot_reach_ready(self):
        runner,topology=self.split_context();topology['accessibility'][0]['hidden']=True
        with self.assertRaises(ValueError):r.native_ready(self.collector,'phase',runner,'split')
        self.collector.cleanup_idle.assert_not_called()

    def test_split_wrong_or_duplicate_scroll_cannot_reach_ready(self):
        runner,topology=self.split_context();original=copy.deepcopy(topology['scrolls'])
        for name in ('foreign window','foreign scene','wrong pane','duplicate'):
            topology['scrolls']=copy.deepcopy(original)
            if name=='foreign window':topology['scrolls'][0]['window']='foreign'
            elif name=='foreign scene':topology['scrolls'][0]['scene']='foreign'
            elif name=='wrong pane':topology['scrolls'][0]['frame_in_window']=topology['scrolls'][1]['frame_in_window']
            else:topology['scrolls'].append(copy.deepcopy(topology['scrolls'][0]))
            with self.subTest(name=name),self.assertRaises(ValueError):r.native_ready(self.collector,'phase',runner,'split')
        self.collector.cleanup_idle.assert_not_called()

    def test_split_consumed_sidebar_counter_cannot_reach_ready(self):
        runner,topology=self.split_context()
        next(v for v in topology['accessibility'] if v['identifier']=='sidebar.receipt')['label']='receipt:1'
        with self.assertRaisesRegex(ValueError,'input occurred'):r.native_ready(self.collector,'phase',runner,'split')
        self.collector.cleanup_idle.assert_not_called()

    def test_stale_ready_ack_is_rejected_before_human_input(self):
        # Exercise the real acknowledgement validator already used by the page.
        import sys
        sys.path.insert(0,str(r.HERE.parent/'interactive-transitions'))
        import physical_release
        from acceptance_common import Rejected
        runner=NS(capture=NS(human_release=NS(release_protocol=physical_release)))
        def wait(_condition,_deadline):
            path=self.out/'operator-ready/request.json';request=r.supported.read(path)
            response=dict(kind='OPERATOR_RELEASED',request_id=request['request_id'],run_id=request['run_id'],
                          request_sha256=r.supported.sha(path),at=101,user_message='Offline test acknowledgement')
            r.supported.save(path.with_name('operator-released.json'),response)
        self.collector.wait=wait
        phases=[]
        with (patch.object(r.time,'time',return_value=102),patch.object(r,'page',return_value=self.stage['page']),
              patch.object(r,'native_ready',side_effect=lambda _c,phase,_r,_layout:phases.append(phase))):
            # at=101 must be rejected because this request is issued at102.
            with self.assertRaises(Rejected):r.human_ready(self.collector,self.out,self.stage,runner,'stack')
        self.assertEqual(phases,['supported.after-end'])

    def test_real_ack_contract_rechecks_live_controls(self):
        import sys
        sys.path.insert(0,str(r.HERE.parent/'interactive-transitions'))
        import physical_release
        runner=NS(capture=NS(human_release=NS(release_protocol=physical_release)))
        def wait(_condition,_deadline):
            path=self.out/'operator-ready/request.json';request=r.supported.read(path)
            r.supported.save(path.with_name('operator-released.json'),dict(kind='OPERATOR_RELEASED',
                request_id=request['request_id'],run_id=request['run_id'],request_sha256=r.supported.sha(path),
                at=102,user_message='Offline test acknowledgement'))
        self.collector.wait=wait;phases=[]
        with (patch.object(r.time,'time',return_value=102),patch.object(r,'page',return_value=self.stage['page']),
              patch.object(r,'native_ready',side_effect=lambda _c,phase,_r,_layout:phases.append(phase))):
            r.human_ready(self.collector,self.out,self.stage,runner,'stack')
        self.assertEqual(phases,['supported.after-end','supported.after-ready'])

    def test_missing_ready_never_reaches_post_ack_snapshot(self):
        def unavailable(*_):raise ValueError('No operator acknowledgement')
        self.collector.wait=unavailable
        phases=[]
        with patch.object(r.time,'time',return_value=100),patch.object(r,'native_ready',side_effect=lambda _c,phase,_r,_layout:phases.append(phase)):
            with self.assertRaises(ValueError):r.human_ready(self.collector,self.out,self.stage,None,'stack')
        self.assertEqual(phases,['supported.after-end'])


if __name__=='__main__':unittest.main()
