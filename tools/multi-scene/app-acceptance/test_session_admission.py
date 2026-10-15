"""Preflight failures must not consume an unlaunched native arm."""
import json
from pathlib import Path
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import journey_session as session
import journey_workflow as workflow
from acceptance_common import Rejected


class SessionAdmissionControls(unittest.TestCase):
    def fixture(self, root):
        def write(name,value):(root/name).write_text(json.dumps(value))
        write('plan.json',{'mode':'signed-in-smoke'})
        choices={'organization':'selected','service_label':'service','dashboard_label':'dashboard',
                 'browser_control_label':'1h','browser_result_label':'15m'}
        write('selection.json',choices)
        review={'state':'PASS','reviewer':'/root/c06_runtime_plan','plan_sha256':workflow.builds.sha(root/'plan.json')}
        write('review.json',review)
        admission={'state':'ADMITTED','plan_sha256':workflow.builds.sha(root/'plan.json'),
                   'review_sha256':workflow.builds.sha(root/'review.json'),'selection_sha256':workflow.builds.sha(root/'selection.json'),
                   'device':'selected-device','operator_ready':True,'expires_at':time.time()+60}
        write('native-admission.json',admission)
        return admission,choices

    def test_exact_current_admission_returns_selected_routes(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);_,choices=self.fixture(root)
            self.assertEqual(workflow.validate_native_admission(root,'selected-device'),choices)

    def test_invalid_admission_stops_before_product_checks_page_or_supervisor(self):
        for mode in ['missing','expired','plan','review','device','operator','selection']:
            with tempfile.TemporaryDirectory() as directory:
                root=Path(directory);admission,_=self.fixture(root)
                if mode=='missing':(root/'native-admission.json').unlink()
                else:
                    if mode=='expired':admission['expires_at']=0
                    if mode=='plan':admission['plan_sha256']='foreign'
                    if mode=='review':admission['review_sha256']='foreign'
                    if mode=='device':admission['device']='foreign'
                    if mode=='operator':admission['operator_ready']=False
                    if mode=='selection':admission['selection_sha256']='foreign'
                    (root/'native-admission.json').write_text(json.dumps(admission))
                initial={p.name:p.read_bytes() for p in root.iterdir()}
                args=SimpleNamespace(root=root,device='selected-device',arm='baseline')
                with patch.object(workflow,'verify',return_value={}),patch.object(workflow.builds,'verify') as products, \
                     patch.object(session.operator,'publish') as page,patch.object(session.supervisor,'supervise') as worker:
                    with self.subTest(mode=mode),self.assertRaises((Rejected,FileNotFoundError)):session.run(args)
                    products.assert_not_called();page.assert_not_called();worker.assert_not_called()
                self.assertEqual({p.name:p.read_bytes() for p in root.iterdir()},initial)


if __name__=='__main__':unittest.main()
