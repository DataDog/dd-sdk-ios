"""Physical admission reviewer provenance; synthetic files, no native execution."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import physical_runtime as runtime
from acceptance_common import Rejected


class PhysicalReviewerTests(unittest.TestCase):
    def setUp(self):
        temp=tempfile.TemporaryDirectory(prefix='physical-reviewer-controls-');self.addCleanup(temp.cleanup)
        self.root=Path(temp.name).resolve();self.plan={'helpers':{'synthetic-helper':'a'*64}}
        self.write('plan.json',self.plan);self.digest=runtime.shared.sha(self.root/'plan.json')
        self.controls={'state':'PASS','plan_sha256':self.digest,'helpers':self.plan['helpers']}
        self.write('controls.json',self.controls)
        self.review={'state':'PASS','reviewer':'/root/c06_runtime_plan','plan_sha256':self.digest,
                     'controls_sha256':runtime.shared.sha(self.root/'controls.json'),'findings':[]}

    def write(self,name,value):
        (self.root/name).write_text(json.dumps(value,sort_keys=True)+'\n')

    def replacement(self):
        value={'schema_version':1,'role':'rum-runtime-reviewer','plan_sha256':self.digest,
               'reviewer':'/root/actual-reviewer','implementer':'/root','coordinator':'/root',
               'assigned_at':'2026-10-01T00:00:00Z','reason':'Historical reviewer absent',
               'previous_reviewer_available':False,'availability_evidence':'Synthetic inventory; no native authority',
               'scope':'REVIEW_ONLY_NO_NATIVE_OWNERSHIP'}
        self.write('reviewer-assignment.json',value)
        self.review.update(reviewer=value['reviewer'],reviewer_role=value['role'],
            reviewer_assignment={'path':'reviewer-assignment.json','sha256':runtime.shared.sha(self.root/'reviewer-assignment.json')})
        return value

    def check(self):
        self.write('review.json',self.review)
        with patch.object(runtime,'verify',return_value=copy.deepcopy(self.plan)):
            return runtime.reviewed(self.root)

    def rejected(self):
        with self.assertRaises(Rejected):self.check()

    def test_historical_receipt_preserves_original_reviewer(self):
        self.assertEqual(self.check(),self.plan)

    def test_bound_independent_replacement_is_accepted(self):
        self.replacement();self.assertEqual(self.check(),self.plan)

    def test_unassigned_replacement_is_rejected(self):
        self.review['reviewer']='/root/actual-reviewer';self.rejected()

    def test_changed_assignment_is_rejected(self):
        value=self.replacement();value['reason']='Changed after review';self.write('reviewer-assignment.json',value);self.rejected()

    def test_foreign_plan_assignment_is_rejected(self):
        value=self.replacement();value['plan_sha256']='f'*64;self.write('reviewer-assignment.json',value)
        self.review['reviewer_assignment']['sha256']=runtime.shared.sha(self.root/'reviewer-assignment.json');self.rejected()

    def test_self_review_is_rejected(self):
        value=self.replacement();value['implementer']=value['reviewer'];self.write('reviewer-assignment.json',value)
        self.review['reviewer_assignment']['sha256']=runtime.shared.sha(self.root/'reviewer-assignment.json');self.rejected()

    def test_replacement_does_not_waive_control_binding(self):
        self.replacement();self.review['controls_sha256']='f'*64;self.rejected()

    def test_replacement_does_not_waive_exact_helper_closure(self):
        self.replacement();self.controls['helpers']={'foreign':'b'*64};self.write('controls.json',self.controls)
        self.review['controls_sha256']=runtime.shared.sha(self.root/'controls.json');self.rejected()

    def test_replacement_does_not_waive_failed_verdict(self):
        self.replacement();self.review['state']='INVALID';self.rejected()


if __name__=='__main__':unittest.main()
