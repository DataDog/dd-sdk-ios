import copy
import json
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch

import journey_workflow as workflow
import journey_session as session
from capture_io import atomic, encoded
from acceptance_common import Rejected


class AdmissionControls(unittest.TestCase):
    def setUp(self):
        self.temporary=tempfile.TemporaryDirectory();self.root=Path(self.temporary.name).resolve()
        self.folder=self.root/'cells/baseline';self.folder.mkdir(parents=True)
        atomic(self.root/'plan.json',encoded(dict(prepared=True)))
        self.now=time.time();self.plan_sha=workflow.builds.sha(self.root/'plan.json')
        self.summary=dict(state='INVALID',scenario='PASS',evidence='SOURCE_CLASSIFICATION_REQUIRED',cleanup='PASS',
                          execution_deadline=self.now+30,cleanup_deadline=self.now+90,
                          cleanup_details=dict(deadline=self.now+60),evidence_errors=[],
                          backend_join_sha256='joined',plan_sha256=self.plan_sha)
        self.joined=dict(state='JOINED_FINAL_SOURCE_CLASSIFICATION_REQUIRED',completed_at=self.now-2,deadline=self.now+20)
    def tearDown(self):self.temporary.cleanup()
    def finish(self):
        self.assertTrue(workflow.publish_outcome(self.folder,self.summary,self.joined))
        atomic(self.root/'baseline-driver.supervisor.json',encoded(dict(state='PASS',before=[],remaining=[],finished_at=time.time()-1)))
        self.assertTrue(session.qualify(self.root,'baseline'))
        return json.loads((self.folder/'summary.json').read_text())
    def test_complete_mechanism_permits_planned_pair_but_not_release_acceptance(self):
        result=self.finish();workflow.candidate_ready(result,self.plan_sha,self.folder)
        self.assertEqual(result['state'],'INVALID');self.assertFalse(result['mechanism']['release_acceptance'])
    def test_missing_evidence_failed_cleanup_and_late_backend_cannot_qualify_mechanism(self):
        for mode in ['scenario','evidence','cleanup','reason','evidence_errors','backend_late','missing_join','cleanup_late']:
            row=copy.deepcopy(self.summary);joined=copy.deepcopy(self.joined);now=self.now
            if mode in ['scenario','evidence','cleanup']:row[mode]='INCOMPLETE'
            if mode=='reason':row['reason']='original failure'
            if mode=='evidence_errors':row['evidence_errors']=['missing raw receipt']
            if mode=='backend_late':joined['completed_at']=joined['deadline']
            if mode=='missing_join':joined=None
            if mode=='cleanup_late':now=row['cleanup_details']['deadline']
            with self.subTest(mode=mode):self.assertEqual(workflow.mechanism(row,joined,now=now)['state'],'UNQUALIFIED')
    def test_late_summary_keeps_original_bytes_and_never_qualifies(self):
        real=workflow.atomic;clock=[self.now]
        def slow(path,raw,**kwargs):
            real(path,raw,**kwargs)
            if path.name=='summary-publication.json':clock[0]=self.summary['cleanup_details']['deadline']+1
        with patch.object(workflow.time,'time',side_effect=lambda:clock[0]),patch.object(workflow,'atomic',side_effect=slow):
            self.assertFalse(workflow.publish_outcome(self.folder,self.summary,self.joined))
        self.assertTrue((self.folder/'late-summary-publication.json').is_file())
        result=json.loads((self.folder/'summary.json').read_text())
        with self.assertRaisesRegex(Rejected,'publication'):workflow.candidate_ready(result,self.plan_sha,self.folder)
    def test_changed_summary_cannot_reuse_prior_worker_qualification(self):
        result=self.finish();changed=dict(result,unapproved='changed')
        atomic(self.folder/'summary.json',encoded(changed),exclusive=False)
        with self.assertRaisesRegex(Rejected,'publication'):workflow.candidate_ready(result,self.plan_sha,self.folder)
    def test_worker_left_running_cannot_qualify_even_with_complete_scenario(self):
        self.assertTrue(workflow.publish_outcome(self.folder,self.summary,self.joined))
        atomic(self.root/'baseline-driver.supervisor.json',encoded(dict(state='INVALID',before=[3],remaining=[3],finished_at=time.time())))
        self.assertFalse(session.qualify(self.root,'baseline'))
        self.assertEqual(json.loads((self.folder/'summary.json').read_text())['scenario'],'PASS')
    def test_late_supervisor_receipt_is_not_relabelled_as_timely_cleanup(self):
        result=self.finish()
        path=self.root/'baseline-driver.supervisor.json';worker=json.loads(path.read_text());worker['finished_at']=self.summary['cleanup_deadline']+1
        atomic(path,encoded(worker),exclusive=False)
        with self.assertRaisesRegex(Rejected,'worker absence'):workflow.candidate_ready(result,self.plan_sha,self.folder)


if __name__=='__main__':unittest.main()
