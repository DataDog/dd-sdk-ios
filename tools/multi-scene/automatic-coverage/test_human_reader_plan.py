"""Offline preparation guards; these controls never admit native work."""
import copy
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import human_reader_plan as p


class PlanControls(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.skill = self.root/'SKILL.md'; self.skill.write_text('Synthetic offline instructions')
        self.tools = self.root/'tools.json'
        p.c.s.save(self.tools,dict(kind='AVAILABLE_XCODE_TOOL_DESCRIPTIONS',
            tools=[dict(name='mcp__xcode__'+n) for n in p.c.s.TOOLS.values()]))

    def test_exact_regular_exports_are_bound(self):
        a,b=p.instructions(self.skill,self.tools)
        self.assertEqual(a,p.c.s.reference(self.skill));self.assertEqual(b,p.c.s.reference(self.tools))

    def test_missing_empty_relative_or_symlink_skill_rejects(self):
        empty=self.root/'empty';empty.touch()
        link=self.root/'link';link.symlink_to(self.skill)
        for value in (self.root/'missing',empty,link,Path('relative.md')):
            with self.subTest(value=value),self.assertRaises(ValueError):p.instructions(value,self.tools)

    def test_redirected_inventory_rejects(self):
        link=self.root/'linked.json';link.symlink_to(self.tools)
        with self.assertRaises(ValueError):p.instructions(self.skill,link)

    def test_incomplete_or_foreign_tool_inventory_rejects(self):
        for value in (dict(kind='OTHER',tools=[]),dict(kind='AVAILABLE_XCODE_TOOL_DESCRIPTIONS',tools=[])):
            self.tools.unlink()
            p.c.s.save(self.tools,value)
            with self.assertRaises(ValueError):p.instructions(self.skill,self.tools)

    def test_missing_instructions_cannot_allocate_output(self):
        output=self.root/'new'
        args=SimpleNamespace(root=output,skill=self.root/'missing',tool_contract=self.tools)
        with patch.object(p,'component_review') as review:
            with self.assertRaises(ValueError):p.prepare(args)
            review.assert_not_called()
        self.assertFalse(output.exists())

    def test_existing_output_is_not_consumed_again(self):
        args=SimpleNamespace(root=self.root)
        with patch.object(p,'instructions') as instructions:
            with self.assertRaises(ValueError):p.prepare(args)
            instructions.assert_not_called()
        self.assertTrue(self.skill.exists())

    def test_component_controls_and_review_join_actual_sources(self):
        controls=dict(state='PASS',source_bindings={str(self.skill):p.c.s.sha(self.skill)})
        control_path=self.root/'controls.json';p.c.s.save(control_path,controls)
        ref=p.c.s.reference(control_path)
        review=dict(state='PASS',findings=[],native_admitted=False,human_invitation=False,
                    controls_sha256=ref['sha256'],bindings=dict(controls=ref,source_bindings=controls['source_bindings']))
        review_path=self.root/'review.json';p.c.s.save(review_path,review)
        self.assertEqual(p.component_review(p.c.s.reference(review_path)),review)
        self.skill.write_text('changed after review')
        with self.assertRaises(ValueError):p.component_review(p.c.s.reference(review_path))

    def test_component_rejects_findings_native_credit_and_wrong_control_join(self):
        control_path=self.root/'controls.json';p.c.s.save(control_path,dict(state='PASS',source_bindings={}))
        ref=p.c.s.reference(control_path)
        review=dict(state='PASS',findings=[],native_admitted=False,human_invitation=False,
                    controls_sha256=ref['sha256'],bindings=dict(controls=ref,source_bindings={}))
        for field,value in (('state','BLOCKED'),('findings',['unresolved']),('native_admitted',True),
                            ('human_invitation',True),('controls_sha256','wrong')):
            bad=copy.deepcopy(review);bad[field]=value
            review_path=self.root/('review-'+field+'.json');p.c.s.save(review_path,bad)
            with self.subTest(field=field),self.assertRaises(ValueError):p.component_review(p.c.s.reference(review_path))

    def publication_fixture(self):
        plan={name:p.c.s.reference(self.skill) for name in ('component_review','compiler_review',
             'plan_factory','reader_review','reader_refresh','skill','tool_contract')}
        path=self.root/'prepared-plan.json';p.c.s.save(path,plan)
        return plan,path,p.c.s.reference(path)

    def test_validated_review_replacement_is_rejected_at_publication(self):
        plan,path,reference=self.publication_fixture()
        with patch.object(p,'component_review') as reviewed:
            p.publication_join(plan,reference);reviewed.assert_called_once_with(plan['component_review'])
            self.skill.write_text('replacement after validation')
            with self.assertRaises(ValueError):p.publication_join(plan,reference)
            self.assertEqual(reviewed.call_count,1)

    def test_plan_replacement_during_operator_publication_is_rejected(self):
        plan,path,reference=self.publication_fixture()
        with patch.object(p,'component_review'):
            p.publication_join(plan,reference)
            path.write_text('{}')
            with self.assertRaises(ValueError):p.publication_join(plan,reference)


if __name__ == '__main__':unittest.main()
