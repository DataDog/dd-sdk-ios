"""Negative controls for complete XCTest inventories and immutable run receipts."""
import copy
import json
from pathlib import Path
import tempfile
import subprocess
import sys
import time
import unittest
from unittest.mock import patch
import rum_suite as suite

TARGET='DatadogRUMTests'
PLAIN=TARGET+'/Example/testPlain()'
PARAM=next(iter(suite.PARAMETER_ARGUMENTS))


def tree():
    arguments=[dict(nodeType='Arguments',name=name,result='Passed',nodeIdentifierURL='test://com.apple.xcode/Datadog/'+PARAM+'?args='+format(i,'064x'))
               for i,name in enumerate(suite.PARAMETER_ARGUMENTS[PARAM])]
    return dict(testNodes=[dict(nodeType='Test Plan',children=[dict(nodeType='Unit test bundle',name=TARGET,children=[
        dict(nodeType='Test Suite',children=[
            dict(nodeType='Test Case',nodeIdentifier=PLAIN.split('/',1)[1],result='Passed'),
            dict(nodeType='Test Case',nodeIdentifier=PARAM.split('/',1)[1],result='Passed',children=arguments)])])])])


def cases(value):return value['testNodes'][0]['children'][0]['children'][0]['children']


def summary():return dict(totalTestCount=2,passedTests=2,skippedTests=0,failedTests=0,expectedFailures=0,result='Passed')


class InventoryTests(unittest.TestCase):
    def test_full_parameter_inventory_and_case_level_summary(self):
        result=suite.assess(sorted([PLAIN,PARAM]),tree(),summary(),[])
        self.assertEqual((result['cases'],result['executions']),(2,16))

    def test_argument_corruptions_are_rejected(self):
        for corruption in ['missing','duplicate_name','duplicate_hash','missing_hash','foreign_owner','wrong_type','nested','failed','skipped']:
            with self.subTest(corruption=corruption):
                value=tree();args=cases(value)[1]['children']
                if corruption=='missing':args.pop()
                elif corruption=='duplicate_name':args[-1]['name']=args[0]['name']
                elif corruption=='duplicate_hash':args[-1]['nodeIdentifierURL']=args[0]['nodeIdentifierURL']
                elif corruption=='missing_hash':args[-1]['nodeIdentifierURL']=args[-1]['nodeIdentifierURL'].split('?')[0]
                elif corruption=='foreign_owner':args[-1]['nodeIdentifierURL']=args[-1]['nodeIdentifierURL'].replace('DatadogRUMTests','OtherTests')
                elif corruption=='wrong_type':args[-1]['nodeType']='Test Case'
                elif corruption=='nested':args[-1]['children']=[dict(nodeType='Arguments')]
                elif corruption=='failed':args[-1]['result']='Failed'
                else:args[-1]['result']='Skipped'
                with self.assertRaises(ValueError):suite.assess(sorted([PLAIN,PARAM]),value,summary(),[])

    def test_case_corruptions_are_rejected(self):
        for corruption in ['duplicate','missing','extra','parameter_children_absent','parent_failed','unclassified_warning','foreign_target','unknown_node','empty']:
            with self.subTest(corruption=corruption):
                value=tree();counts=summary()
                if corruption=='duplicate':cases(value).append(copy.deepcopy(cases(value)[0]))
                elif corruption=='missing':cases(value).pop(0)
                elif corruption=='extra':cases(value).append(dict(nodeType='Test Case',nodeIdentifier='Example/extra()',result='Passed'))
                elif corruption=='parameter_children_absent':cases(value)[1].pop('children')
                elif corruption=='parent_failed':cases(value)[1]['result']='Failed'
                elif corruption=='unclassified_warning':counts['runtimeWarnings']=[dict(message='warning')]
                elif corruption=='foreign_target':value['testNodes'][0]['children'][0]['name']='OtherTests'
                elif corruption=='unknown_node':value['testNodes'][0]['nodeType']='Unrecognized'
                else:value['testNodes']=[]
                with self.assertRaises(ValueError):suite.assess(sorted([PLAIN,PARAM]),value,counts,[])

    def test_summary_disagreements_are_rejected(self):
        for field,value in [('totalTestCount',16),('passedTests',1),('skippedTests',1),('failedTests',1),('expectedFailures',1),('result','Failed'),('testFailures',[{}])]:
            with self.subTest(field=field):
                counts=summary();counts[field]=value
                with self.assertRaises(ValueError):suite.assess(sorted([PLAIN,PARAM]),tree(),counts,[])

    def test_skip_must_be_predetermined(self):
        value=tree();cases(value)[0]['result']='Skipped';counts=summary();counts.update(passedTests=1,skippedTests=1)
        self.assertEqual(suite.assess(sorted([PLAIN,PARAM]),value,counts,[PLAIN])['skipped'],[PLAIN])
        with self.assertRaises(ValueError):suite.assess(sorted([PLAIN,PARAM]),value,counts,[])

    def test_discovery_rejects_missing_disabled_duplicate_foreign(self):
        good=dict(errors=[],values=[dict(enabledTests=[dict(identifier=PLAIN)])])
        self.assertEqual(suite.enumerate_inventory(good),[PLAIN])
        for corrupt in ['errors','empty','duplicate','disabled','foreign','multiple']:
            with self.subTest(corrupt=corrupt):
                value=copy.deepcopy(good);target=value['values'][0]
                if corrupt=='errors':value['errors']=['oops']
                elif corrupt=='empty':target['enabledTests']=[]
                elif corrupt=='duplicate':target['enabledTests']*=2
                elif corrupt=='disabled':target['disabledTests']=[dict(identifier=PLAIN)]
                elif corrupt=='foreign':target['enabledTests'][0]['identifier']='OtherTests/test()'
                else:value['values']*=2
                with self.assertRaises(ValueError):suite.enumerate_inventory(value)

    def test_result_runtime_and_configuration_are_bound(self):
        expected=dict(architecture='arm64',deviceId='selected',deviceName='Fixture',modelName='Fixture',osBuildNumber='build',osVersion='27.0',platform='iOS Simulator')
        config=dict(configurationId='1',configurationName='Test Scheme Action')
        counts=dict(devicesAndConfigurations=[dict(device=expected,testPlanConfiguration=config,passedTests=1,skippedTests=0,failedTests=0,expectedFailures=0)])
        value=dict(devices=[expected],testPlanConfigurations=[config]);runs=[(PLAIN,None,'Passed')]
        suite.result_environment(counts,value,expected,runs)
        for key in expected:
            with self.subTest(field=key):
                modified=copy.deepcopy(value);modified['devices'][0][key]='foreign'
                with self.assertRaises(ValueError):suite.result_environment(counts,modified,expected,runs)
        for key in ['device','testPlanConfiguration','passedTests','skippedTests','failedTests','expectedFailures']:
            with self.subTest(field=key):
                modified=copy.deepcopy(counts);modified['devicesAndConfigurations'][0][key]='foreign'
                with self.assertRaises(ValueError):suite.result_environment(modified,value,expected,runs)

    def test_consumed_build_is_rejected_before_inputs_or_execution(self):
        for name in ['stage-admission.json','build-admission.json','built.json']:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as tmp:
                root=Path(tmp);(root/name).write_text('{}')
                with patch.object(suite,'reviewed',side_effect=AssertionError('must not reach review')):
                    with self.assertRaisesRegex(ValueError,'already consumed'):suite.build_tests(root)

    def test_external_symlink_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);(root/'outside').write_text('x');inside=root/'inside';inside.mkdir();(inside/'link').symlink_to('../outside')
            with self.assertRaises(ValueError):suite.inventory(inside)

    def test_command_exception_preserves_receipt_and_quiescence(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);deadline=time.time()+.05
            with self.assertRaises(subprocess.TimeoutExpired):
                suite.command([sys.executable,'-c','import time; time.sleep(20)'],root,'attempt',deadline=deadline)
            receipt=json.loads((root/'attempt-receipt.json').read_text())
            self.assertIn('TimeoutExpired',receipt['failure']);self.assertEqual(receipt['deadline'],deadline)
            self.assertEqual(receipt['cleanup_deadline'],deadline+10)
            self.assertEqual(receipt['quiescence']['state'],'PASS');self.assertFalse(receipt['quiescence']['remaining'])

    def test_completed_command_reaps_its_group(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            suite.command([sys.executable,'-c','print("complete")'],root,'attempt',deadline=time.time()+5)
            receipt=json.loads((root/'attempt-receipt.json').read_text())
            self.assertEqual(receipt['returncode'],0);self.assertIsNone(receipt['failure'])
            self.assertEqual(receipt['quiescence']['state'],'PASS')

    def test_nonzero_command_keeps_original_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            with self.assertRaises(ValueError):suite.command([sys.executable,'-c','raise SystemExit(3)'],root,'attempt',deadline=time.time()+5)
            receipt=json.loads((root/'attempt-receipt.json').read_text())
            self.assertEqual(receipt['returncode'],3);self.assertEqual(receipt['quiescence']['state'],'PASS')


if __name__=='__main__':unittest.main()
