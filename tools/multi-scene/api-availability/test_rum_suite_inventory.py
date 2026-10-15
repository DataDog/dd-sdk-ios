import copy
from pathlib import Path
import tempfile
import unittest
import rum_suite_inventory as suite

CASE='DatadogRUMTests/Fixture/testCase()'


class InventoryTests(unittest.TestCase):
    def discovery(self,rows):
        return dict(errors=[],values=[dict(enabledTests=[dict(identifier=v) for v in rows])])

    def test_exact_placeholder_is_reported_separately(self):
        value=self.discovery([CASE,suite.PLACEHOLDER]);before=copy.deepcopy(value)
        result=suite.classify(value)
        self.assertEqual(result,dict(raw_count=2,identifiers=[CASE],non_cases=[suite.PLACEHOLDER]))
        self.assertEqual(value,before)

    def test_absent_placeholder_requires_no_exclusion(self):
        self.assertEqual(suite.classify(self.discovery([CASE]))['non_cases'],[])

    def test_unknown_class_foreign_disabled_duplicate_and_empty_rejected(self):
        for rows in [[CASE,'DatadogRUMTests/Unknown'],[CASE,'Foreign/Case/test()'],[CASE,suite.PLACEHOLDER,suite.PLACEHOLDER],
                     [suite.PLACEHOLDER],[]]:
            with self.subTest(rows=rows),self.assertRaises(ValueError):suite.classify(self.discovery(rows))
        value=self.discovery([CASE]);value['values'][0]['disabledTests']=[dict(identifier=CASE)]
        with self.assertRaises(ValueError):suite.classify(value)

    def test_method_under_helper_is_never_filtered(self):
        method=suite.PLACEHOLDER+'/testRegression()'
        self.assertEqual(suite.classify(self.discovery([CASE,method]))['identifiers'],sorted([CASE,method]))

    def test_malformed_executable_identifier_is_not_a_test(self):
        for item in ['DatadogRUMTests/Case/name','DatadogRUMTests/Case/nested/test()','DatadogRUMTests/test()']:
            with self.subTest(item=item),self.assertRaises(ValueError):suite.classify(self.discovery([CASE,item]))

    def test_offline_receipt_needs_zero_exit_actual_log_and_timely_quiescence(self):
        for corruption in [None,'nonzero','failure','cleanup','late','remaining','group','log']:
            with self.subTest(corruption=corruption),tempfile.TemporaryDirectory() as tmp:
                root=Path(tmp);(root/'execute.log').write_text('actual')
                value=dict(returncode=0,failure=None,cleanup_failure=None,finished_at=99,pid=7,
                           log_sha256=suite.shared.sha(root/'execute.log'),quiescence=dict(state='PASS',remaining=[],group=7))
                if corruption=='nonzero':value['returncode']=65
                elif corruption in ['failure','cleanup']:value['failure' if corruption=='failure' else 'cleanup_failure']='failed'
                elif corruption=='late':value['finished_at']=100
                elif corruption=='remaining':value['quiescence']['remaining']=[7]
                elif corruption=='group':value['quiescence']['group']=8
                elif corruption=='log':value['log_sha256']='changed'
                suite.shared.save(root/'execute-receipt.json',value)
                if corruption is None:suite.timely_receipt(root,'execute',100)
                else:
                    with self.assertRaises(ValueError):suite.timely_receipt(root,'execute',100)


if __name__=='__main__':unittest.main()
