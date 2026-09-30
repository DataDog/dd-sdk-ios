"""A restarted reviewer cannot inherit a different plan or review their own work."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from acceptance_common import Rejected
from reviewer_assignment import LEGACY_REVIEWER, ROLE, require_reviewer


class ReviewerAssignmentTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.plan = 'a' * 64
        self.assignment = dict(schema_version=1, role=ROLE, plan_sha256=self.plan,
                               reviewer='new-reviewer', implementer='implementer', coordinator='coordinator',
                               assigned_at='2026-09-30T10:00:00Z', reason='Previous reviewer session ended',
                               previous_reviewer_available=False, availability_evidence='Fresh agent inventory',
                               scope='REVIEW_ONLY_NO_NATIVE_OWNERSHIP')

    def receipt(self, assignment=None):
        raw = json.dumps(assignment or self.assignment).encode()
        (self.root / 'reviewer-assignment.json').write_bytes(raw)
        return dict(reviewer='new-reviewer', reviewer_role=ROLE,
                    reviewer_assignment=dict(path='reviewer-assignment.json', sha256=hashlib.sha256(raw).hexdigest()))

    def test_legacy_review_remains_unchanged(self):
        receipt = {'reviewer': LEGACY_REVIEWER, 'state': 'PASS'}
        before = copy.deepcopy(receipt)
        require_reviewer(receipt, self.plan, self.root)
        self.assertEqual(receipt, before)
        self.assertEqual(list(self.root.iterdir()), [])

    def test_replacement_bound_to_exact_plan(self):
        require_reviewer(self.receipt(), self.plan, self.root)

    def test_changed_missing_or_external_assignment_rejects(self):
        review = self.receipt()
        (self.root / 'reviewer-assignment.json').write_text('{}')
        with self.assertRaises(Rejected): require_reviewer(review, self.plan, self.root)
        (self.root / 'reviewer-assignment.json').unlink()
        with self.assertRaises(Rejected): require_reviewer(review, self.plan, self.root)
        review['reviewer_assignment']['path'] = '../reviewer-assignment.json'
        with self.assertRaises(Rejected): require_reviewer(review, self.plan, self.root)

    def test_wrong_plan_self_review_and_unobserved_replacement_reject(self):
        for key, value in [('plan_sha256', 'b' * 64), ('implementer', 'new-reviewer'),
                           ('role', 'other'), ('schema_version', True), ('previous_reviewer_available', True),
                           ('availability_evidence', ''), ('scope', 'NATIVE_OWNER'), ('coordinator', '')]:
            assignment = dict(self.assignment, **{key: value})
            with self.subTest(key=key), self.assertRaises(Rejected):
                require_reviewer(self.receipt(assignment), self.plan, self.root)

    def test_new_identity_or_role_without_assignment_rejects(self):
        for review in [{'reviewer': 'new-reviewer'}, {'reviewer': LEGACY_REVIEWER, 'reviewer_role': ROLE}]:
            with self.subTest(review=review), self.assertRaises(Rejected): require_reviewer(review, self.plan, self.root)

    def test_valid_assignment_cannot_be_used_by_another_reviewer(self):
        review = self.receipt(); review['reviewer'] = 'different-reviewer'
        with self.assertRaises(Rejected): require_reviewer(review, self.plan, self.root)


if __name__ == '__main__':
    unittest.main()
