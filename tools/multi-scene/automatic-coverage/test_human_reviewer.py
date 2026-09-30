"""Replacement review provenance must be checked at admission and predecessor reuse."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import human_runtime as runner
from acceptance_common import Rejected
from reviewer_assignment import LEGACY_REVIEWER, ROLE


class HumanReviewerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name); self.runtime = self.root / 'runtime'; self.runtime.mkdir()
        self.plan = {'helpers': {}}
        self.write('runtime-plan.json', self.plan)
        self.plan_sha = runner.shared.sha(self.runtime / 'runtime-plan.json')
        self.write('controls.json', dict(state='PASS', plan_sha256=self.plan_sha, helpers={}))
        self.review = dict(state='PASS', reviewer=LEGACY_REVIEWER, plan_sha256=self.plan_sha,
                           controls_sha256=runner.shared.sha(self.runtime / 'controls.json'))

    def write(self, name, value):
        (self.runtime / name).write_text(json.dumps(value))

    def verify_both(self):
        self.write('review.json', self.review)
        with patch.object(runner, 'verify', return_value=self.plan):
            runner.reviewed(self.root)
        runner.human_sessions.reviewed(self.root, self.plan, runner)

    def replacement(self):
        self.write('reviewer-assignment.json', dict(schema_version=1, role=ROLE, plan_sha256=self.plan_sha,
            reviewer='replacement', implementer='implementer', coordinator='coordinator',
            assigned_at='2026-09-30T10:00:00Z', reason='Old session ended', previous_reviewer_available=False,
            availability_evidence='Fresh available-agent inventory', scope='REVIEW_ONLY_NO_NATIVE_OWNERSHIP'))
        self.review.update(reviewer='replacement', reviewer_role=ROLE,
                           reviewer_assignment=dict(path='reviewer-assignment.json',
                            sha256=runner.shared.sha(self.runtime / 'reviewer-assignment.json')))

    def test_original_and_replacement_both_keep_plan_and_controls_checks(self):
        self.assertIn('tools/multi-scene/acceptance/reviewer_assignment.py', runner.helper_members())
        self.verify_both(); self.replacement(); self.verify_both()
        self.write('controls.json', dict(state='FAIL', plan_sha256=self.plan_sha, helpers={}))
        with self.assertRaises(Rejected):
            self.verify_both()

    def test_replacement_cannot_skip_assignment_on_either_path(self):
        self.replacement(); self.review.pop('reviewer_assignment'); self.write('review.json', self.review)
        with patch.object(runner, 'verify', return_value=self.plan), self.assertRaises(RuntimeError):
            runner.reviewed(self.root)
        with self.assertRaises(RuntimeError): runner.human_sessions.reviewed(self.root, self.plan, runner)


if __name__ == '__main__':
    unittest.main()
