"""Home completion keeps native provenance separate from the semantic inventory."""
import copy
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import human_home as home
import test_local_event_collection as events
from acceptance_common import Rejected


def encoded(value):return (json.dumps(value)+'\n').encode()


class HomeCompletion(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);self.folder=self.root/'input';self.folder.mkdir()
        self.docs=self.root/'documents';self.docs.mkdir()
        self.before=encoded(dict(schema_version=1,run_id='run',request_id='home',phase='background.before'))
        (self.folder/'request.json').write_bytes(self.before)
        self.rows=[events.row(1,'launch',{}),events.row(2,'rum',events.view(True,1)),
            events.row(3,'human_snapshot',dict(phase='background.before',request_id='home')),
            events.row(4,'human_observer_cost',dict(operation='snapshot',event_sequence=3,request_id='home',duration_ns=1)),
            events.row(5,'native_background',{}),events.row(6,'geometry',{})]
        self.prefix=events.encode(self.rows)
        self.rows += [events.row(7,'rum',events.action()),events.row(8,'rum',events.view(False,2))]
        self.initial=events.encode(self.rows);self.idle=b'native idle proof'
        self.first=self.checkpoint(self.prefix,'background-5')
        for name,raw in [('background-events.jsonl',self.prefix),('background-checkpoint.json',self.first),
            ('background-collected-events.jsonl',self.initial),('home-input-idle.json',self.idle)]:
            (self.folder/name).write_bytes(raw)
        self.mode='normal';self.publications=0
        self.collector=SimpleNamespace(documents=self.docs,run='run',pid=42,binding=dict(window='window',root='root',scene='scene'),
            live=lambda deadline:None,wait=self.wait)
    def checkpoint(self,raw,identifier):
        return encoded(dict(schema_version=1,run_id='run',request_id=identifier,sequence=len(raw.splitlines()),
            success=True,byte_count=len(raw),sha256=home.digest(raw)))
    def wait(self,condition,deadline):
        value=condition()
        if value is None:raise Rejected('missing native publication')
        return value
    def publish(self,path,value,**kwargs):
        raw=encoded(value)
        if kwargs.get('exclusive') and path.exists():raise Rejected('consumed output')
        path.write_bytes(raw)
        if path!=self.docs/'human-snapshot-request.json':return
        self.publications+=1;ack=value;final_rows=copy.deepcopy(self.rows)
        if self.mode=='active':final_rows.append(events.row(9,'rum',events.view(True,3)))
        if self.mode=='action':
            action=events.action();action['action']['id']='later';final_rows.append(events.row(9,'rum',action))
        if self.mode=='foreign':final_rows[-1]['payload']['session']['id']='foreign'
        if self.mode=='snapshot':final_rows.append(events.row(9,'human_snapshot',dict(phase='background.finish')))
        final=events.encode(final_rows);checkpoint=self.checkpoint(final,'home-finish-'+ack['request_id'])
        if self.mode=='after_checkpoint_active':final=events.encode(final_rows+[events.row(9,'rum',events.view(True,3))])
        (self.docs/'events.jsonl').write_bytes(final)
        if self.mode!='missing_checkpoint':(self.docs/('events-checkpoint-home-finish-'+ack['request_id']+'.json')).write_bytes(checkpoint)
        receipt=dict(schema_version=1,run_id='run',request_id='home',request_sha256=home.digest(self.before),pid=42,
            state='EXPIRED' if self.mode=='expired' else 'END_REQUESTED',app_state=2,task_was_valid=True,
            finish_request_id=ack['request_id'],finish_request_sha256=home.digest(raw),
            first_checkpoint_sha256=home.digest(self.first),final_checkpoint_sha256=home.digest(checkpoint),idle_sha256=home.digest(self.idle))
        if self.mode in ['request_sha256','finish_request_sha256','first_checkpoint_sha256','final_checkpoint_sha256','idle_sha256']:
            receipt[self.mode]='foreign'
        if self.mode!='missing_receipt':(self.docs/'home-task-home.json').write_bytes(encoded(receipt))
    def finish(self):
        with patch.object(home.shared,'save',side_effect=self.publish):return home.finish(self.collector,self.folder,self.rows,100)
    def test_complete_inventory_precedes_finish_and_final_inventory_is_revalidated(self):
        self.assertEqual(self.finish(),self.rows);self.assertEqual(self.publications,1)
        ack=json.loads((self.folder/'home-finish-request.json').read_bytes())
        self.assertEqual(ack['home']['terminal_sha256'],home.digest(self.initial))
        self.assertEqual(json.loads((self.folder/'home-completion.json').read_bytes())['state'],'FINAL_INVENTORY_REVALIDATED')
    def test_incomplete_first_inventory_does_not_publish_finish(self):
        (self.folder/'background-collected-events.jsonl').write_bytes(self.prefix)
        with self.assertRaises(Rejected):self.finish()
        self.assertEqual(self.publications,0)
    def test_finish_is_one_shot(self):
        self.finish()
        with self.assertRaises(Rejected):self.finish()
        self.assertEqual(self.publications,1)
    def test_later_active_view_action_foreign_owner_and_snapshot_cannot_pass(self):
        for mode in ['active','action','foreign','snapshot','after_checkpoint_active']:
            with self.subTest(mode=mode):
                self.setUp();self.mode=mode
                with self.assertRaises((Rejected,ValueError)):self.finish()
                self.assertFalse((self.folder/'home-completion.json').exists())
    def test_expiration_missing_receipt_and_missing_writer_barrier_reject(self):
        for mode in ['expired','missing_receipt','missing_checkpoint']:
            with self.subTest(mode=mode):
                self.setUp();self.mode=mode
                with self.assertRaises(Rejected):self.finish()
    def test_before_finish_writer_and_idle_hashes_are_bound(self):
        for mode in ['request_sha256','finish_request_sha256','first_checkpoint_sha256','final_checkpoint_sha256','idle_sha256']:
            with self.subTest(mode=mode):
                self.setUp();self.mode=mode
                with self.assertRaises(Rejected):self.finish()
    def test_foreign_ready_or_missing_sidecar_cannot_release_the_collector(self):
        good=dict(schema_version=1,state='READY',run_id='run',pid=42,request_id='home',request_sha256=home.digest(self.before),
            checkpoint_sha256=home.digest(self.first),idle_sha256=home.digest(self.idle))
        self.assertEqual(home.ready(encoded(good),self.before,self.first,self.idle,run='run',pid=42),good)
        for name in ['state','run_id','pid','request_id','request_sha256','checkpoint_sha256','idle_sha256']:
            bad=dict(good);bad[name]='foreign'
            with self.subTest(name=name),self.assertRaises(Rejected):home.ready(encoded(bad),self.before,self.first,self.idle,run='run',pid=42)
        (self.docs/'home-ready-home.json').write_bytes(encoded(good))
        with self.assertRaises(Rejected):home.await_ready(self.collector,self.folder,'background-5',100)

class OriginalBuildReuse(unittest.TestCase):
    def test_refresh_allows_only_the_rendered_observer_helper(self):
        import human_sessions as sessions
        expected={'tools/multi-scene/automatic-coverage/human_variant.py':'old','unchanged-build.py':'same'}
        actual={'human_variant.py':'new','unchanged-build.py':'same'}
        runner=SimpleNamespace(require=home.require,shared=SimpleNamespace(REPO=Path('/unused'),sha=lambda p:actual[p.name]))
        with self.assertRaises(Rejected):sessions.verify_build_helpers(expected,runner)
        sessions.verify_build_helpers(expected,runner,allow_fixture_refresh=True)
        actual['unchanged-build.py']='changed'
        with self.assertRaises(Rejected):sessions.verify_build_helpers(expected,runner,allow_fixture_refresh=True)


if __name__=='__main__':unittest.main()
