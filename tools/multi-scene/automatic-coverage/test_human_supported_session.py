"""Offline controls for the supported-session boundary; no device calls."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import uuid

import human_supported_session as h


class SupportedSessionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.binding = dict(owner='/root/device_owner',device='Duo',bundle='fixture',run_id=str(uuid.uuid4()),
                            product_sha256='a'*64,plan_sha256='b'*64)
        self.key = 'actual-returned-key'

    def request(self, phase, binding=None, *, issued=100, deadline=220):
        folder=self.root/phase;folder.mkdir()
        value=dict(kind='SUPPORTED_SESSION_REQUEST',schema_version=1,phase=phase,
                   request_id=str(uuid.uuid4()),binding=copy.deepcopy(binding or self.binding),
                   session_key=None if phase=='start' else self.key,
                   start_response_sha256=None if phase=='start' else h.sha(self.root/'start/response.json'),
                   tool=h.TOOLS[phase],issued_at=issued,deadline=deadline)
        value['arguments']=h.arguments(phase,value['binding'],value['session_key'])
        h.save(folder/'request.json',value)
        return folder/'request.json'

    def response(self, path, value, *, started=101, finished=104, published=105, error=False):
        raw=dict(structuredContent=value)
        if error:raw['isError']=True
        return h.publish_response(path,raw,owner=self.binding['owner'],started_at=started,
                                  finished_at=finished,published_at=published)

    def started(self):
        request=self.request('start')
        self.response(request,dict(deviceIsSimulator=True,deviceUUID='Duo',interactionSessionKey=self.key))
        return request

    def capture(self):
        self.started()
        return self.request('capture',dict(self.binding,pid=123),issued=110)

    def test_start_joins_actual_returned_device_and_key(self):
        path=self.started();request,value=h.validate_response(path,now=106)
        self.assertEqual(h.start_value(request,value),self.key)

    def test_wrong_device_and_physical_device_rejected(self):
        path=self.started();request,value=h.validate_response(path,now=106)
        for field,bad in [('deviceUUID','Other'),('deviceIsSimulator',False),('interactionSessionKey','')]:
            with self.subTest(field=field), self.assertRaises(ValueError):
                h.start_value(request,dict(value,**{field:bad}))

    def test_raw_tool_error_retained_and_rejected(self):
        path=self.request('start');self.response(path,{'message':'Session not found'},error=True)
        with self.assertRaises(ValueError):h.validate_response(path,now=106)
        self.assertTrue(h.read(path.with_name('tool-result.json'))['isError'])

    def test_foreign_response_joins_rejected(self):
        path=self.started();response=h.read(path.with_name('response.json'))
        changes={'owner':'/root/other','request_id':str(uuid.uuid4()),'request_sha256':'c'*64,
                 'binding':dict(self.binding,run_id='other'),'tool':h.CAPTURE,'arguments':{'interactionCommand':'t 1 2'}}
        for key,value in changes.items():
            with self.subTest(key=key):
                path.with_name('response.json').write_text(json.dumps(dict(response,**{key:value})))
                with self.assertRaises(ValueError):h.validate_response(path,now=106)

    def test_late_and_reordered_clocks_are_not_salvaged(self):
        path=self.started();response=h.read(path.with_name('response.json'))
        for change in [dict(started_at=99),dict(finished_at=100),dict(published_at=103),
                       dict(published_at=225),dict(started_at=float('nan'))]:
            with self.subTest(change=change):
                path.with_name('response.json').write_text(json.dumps(dict(response,**change)))
                with self.assertRaises(ValueError):h.validate_response(path,now=230 if change.get('published_at')==225 else 106)

    def test_capture_cannot_add_input_or_activation(self):
        path=self.capture();request=h.read(path)
        for change in [dict(interactionCommand='t 1 2'),dict(activationBundleId='fixture'),dict(interactSessionKey='foreign')]:
            with self.subTest(change=change),self.assertRaises(ValueError):
                h.validate_request(dict(request,arguments=dict(request['arguments'],**change)))

    def test_foreign_start_session_cannot_be_substituted(self):
        path=self.capture();request=h.read(path)
        request['session_key']='foreign';request['arguments']['interactSessionKey']='foreign'
        path.write_text(json.dumps(request));self.response(path,{},started=111,finished=114,published=115)
        with self.assertRaisesRegex(ValueError,'detached'):h.validate_response(path,now=116)

    def test_capture_cannot_precede_launch_or_start(self):
        path=self.capture();request=h.read(path)
        for change in [dict(binding=self.binding),dict(start_response_sha256=None)]:
            with self.subTest(change=change),self.assertRaises(ValueError):h.validate_request(dict(request,**change))
        self.response(path,{},started=111,finished=114,published=115)
        start=h.read(self.root/'start/response.json');start['finished_at']=120
        (self.root/'start/response.json').write_text(json.dumps(start))
        with self.assertRaises(ValueError):h.validate_response(path,now=116)

    def test_published_request_and_raw_response_are_immutable(self):
        path=self.started();expected=h.read(path)
        path.write_text(json.dumps(dict(expected,deadline=221)))
        with self.assertRaisesRegex(ValueError,'request changed'):h.validate_response(path,now=106,expected_request=expected)
        path.write_text(json.dumps(expected,indent=2)+'\n')
        path.with_name('tool-result.json').write_text('{}')
        with self.assertRaises(ValueError):h.validate_response(path,now=106)
        with self.assertRaises(FileExistsError):self.response(path,{})

    def hierarchy(self,bundle='fixture',pid=123,ids=h.HOME_IDS):
        return f'Application bundle identifier: {bundle}\nApplication UI orientation: Portrait\nApplication, pid: {pid}, label: "fixture"\n'+''.join(f" Button, identifier: '{name}'\n" for name in ids)

    def test_hierarchy_owner_and_source_controls(self):
        self.assertEqual(h.hierarchy_owner(self.hierarchy(),'fixture',123)['identifiers'],list(h.HOME_IDS))
        for raw in [self.hierarchy(pid=124),self.hierarchy(bundle='other'),self.hierarchy()*2,
                    self.hierarchy(ids=h.HOME_IDS[1:]),self.hierarchy(ids=())+self.hierarchy(bundle='other')]:
            with self.subTest(raw=raw),self.assertRaises(ValueError):h.hierarchy_owner(raw,'fixture',123)

    def test_actual_paths_and_bytes_preserved_even_when_owner_fails(self):
        path=self.capture();request=h.read(path)
        original=self.root/'actual.txt';original.write_text(self.hierarchy(pid=999))
        screenshot=self.root/'actual.png';screenshot.write_bytes(b'\x89PNG\r\n\x1a\nactual')
        value=dict(hierarchyPath=str(original),screenshotPath=str(screenshot),applicationState='NotRun')
        with self.assertRaises(ValueError):h.capture_value(request,value,path.parent)
        self.assertEqual((path.parent/'returned-hierarchy.txt').read_bytes(),original.read_bytes())
        self.assertEqual((path.parent/'returned-screenshot.png').read_bytes(),screenshot.read_bytes())

    def test_missing_artifacts_do_not_use_saved_observations(self):
        path=self.capture();request=h.read(path)
        (path.parent/'old-hierarchy.txt').write_text(self.hierarchy())
        with self.assertRaises(ValueError):h.capture_value(request,{},path.parent)

    def test_terminal_application_states_are_preserved_but_not_ready(self):
        path=self.capture();request=h.read(path)
        for state in ('Stopped','Crashed','Disconnected','Hanging','RunningInBackground'):
            with self.subTest(state=state),self.assertRaises(ValueError):
                h.capture_value(request,dict(applicationState=state),path.parent)

    def test_application_state_is_not_rewritten(self):
        path=self.capture();request=h.read(path)
        original=self.root/'actual.txt';original.write_text(self.hierarchy())
        screenshot=self.root/'actual.png';screenshot.write_bytes(b'\x89PNG\r\n\x1a\nactual')
        proof=h.capture_value(request,dict(hierarchyPath=str(original),screenshotPath=str(screenshot),applicationState='NotRun'),path.parent)
        self.assertEqual(proof['application_state'],'NotRun')
        self.assertEqual(proof['artifacts']['hierarchy']['source_path'],str(original))

    def test_session_start_capture_end_order_and_one_end(self):
        session=h.Session(self.root,self.binding,seconds=120,deadline=1000)
        with self.assertRaises(ValueError):session.capture(123)
        with patch.object(session,'exchange') as exchange:
            session.key=self.key;session.start_sha='a'*64
            exchange.return_value=({},dict(userMessage="Session doesn't exist anymore"))
            with self.assertRaises(ValueError):session.end(1000)
            self.assertEqual(exchange.call_count,1)
            with self.assertRaises(ValueError):session.end(1000)
            self.assertEqual(exchange.call_count,1)

    def test_wrong_device_start_cannot_close_its_returned_key(self):
        session=h.Session(self.root,self.binding,seconds=120,deadline=1000)
        request=self.request('start')
        self.response(request,dict(deviceIsSimulator=True,deviceUUID='Foreign',interactionSessionKey='foreign-key'))
        with patch.object(session,'exchange') as exchange:
            with self.assertRaisesRegex(ValueError,'wrong supported session device'):session.end(1000)
            exchange.assert_not_called()

    def test_unpublished_start_cannot_close_a_session(self):
        session=h.Session(self.root,self.binding,seconds=120,deadline=1000)
        with patch.object(session,'exchange') as exchange:
            with self.assertRaisesRegex(ValueError,'creation unresolved'):session.end(1000)
            exchange.assert_not_called()
            with self.assertRaises(ValueError):session.end(1000)
            exchange.assert_not_called()

    def test_future_start_cannot_close_a_session(self):
        session=h.Session(self.root,self.binding,seconds=120,deadline=1000)
        self.started()
        with patch.object(h.time,'time',return_value=100),patch.object(session,'exchange') as exchange:
            with self.assertRaisesRegex(ValueError,'publication is in the future'):session.end(1000)
            exchange.assert_not_called()


if __name__=='__main__':unittest.main()
