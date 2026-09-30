"""Prompt reachability controls; no native execution or human acknowledgement."""
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
                    with self.assertRaises(ValueError):r.qualify(session,self.collector,self.out,self.stage,None)
                self.assertEqual(events,['capture','native','end','ready'][:['capture','native','end','ready'].index(boundary)+1])

    def test_closure_precedes_ready(self):
        events=[]
        session=NS(capture=lambda _:events.append('capture'),end=lambda _:events.append('end'))
        with (patch.object(r,'native_ready',side_effect=lambda *_:events.append('native')),
              patch.object(r,'human_ready',side_effect=lambda *_:events.append('ready'))):
            r.qualify(session,self.collector,self.out,self.stage,None)
        self.assertEqual(events,['capture','native','end','ready'])

    def test_native_active_input_is_not_ready(self):
        self.collector.snapshot=lambda *_:({'payload':{'input_state':{}}},self.out)
        runner=NS(journey=NS(ready_controls=lambda *_:dict(counter=0)),
                  capture=NS(human_release=NS(input_idle=lambda *_:False)))
        with self.assertRaisesRegex(ValueError,'not idle'):r.native_ready(self.collector,'phase',runner)
        self.assertFalse((self.out/'controls-ready.json').exists())

    def test_already_consumed_input_is_not_ready(self):
        self.collector.snapshot=lambda *_:({'payload':{'input_state':{}}},self.out)
        for kind in ('human_callback','native_input','human_scroll_begin','human_scroll_end','native_background'):
            self.collector.evidence=[{'kind':kind}]
            runner=NS(journey=NS(ready_controls=lambda *_:dict(counter=0)),
                      capture=NS(human_release=NS(input_idle=lambda *_:True)))
            with self.subTest(kind=kind),self.assertRaisesRegex(ValueError,'input occurred'):
                r.native_ready(self.collector,'phase',runner)

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
              patch.object(r,'native_ready',side_effect=lambda _c,phase,_r:phases.append(phase))):
            # at=101 must be rejected because this request is issued at102.
            with self.assertRaises(Rejected):r.human_ready(self.collector,self.out,self.stage,runner)
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
              patch.object(r,'native_ready',side_effect=lambda _c,phase,_r:phases.append(phase))):
            r.human_ready(self.collector,self.out,self.stage,runner)
        self.assertEqual(phases,['supported.after-end','supported.after-ready'])

    def test_missing_ready_never_reaches_post_ack_snapshot(self):
        def unavailable(*_):raise ValueError('No operator acknowledgement')
        self.collector.wait=unavailable
        phases=[]
        with patch.object(r.time,'time',return_value=100),patch.object(r,'native_ready',side_effect=lambda _c,phase,_r:phases.append(phase)):
            with self.assertRaises(ValueError):r.human_ready(self.collector,self.out,self.stage,None)
        self.assertEqual(phases,['supported.after-end'])


if __name__=='__main__':unittest.main()
