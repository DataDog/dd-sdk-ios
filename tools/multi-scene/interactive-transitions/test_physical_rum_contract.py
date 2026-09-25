"""Finite RUM gate scope and exact ingestion controls; no runtime calls."""
import copy
import unittest

import physical_rum_contract as contract
import test_physical_witness as witness_fixtures
import test_runtime_contract as fixtures
from acceptance_common import Rejected


class RequiredRUMFields(unittest.TestCase):
    def setUp(self):
        base = witness_fixtures.ExactWitness(); base.setUp()
        self.native, self.rows = base.native, base.rows
        for row in self.native:
            if row['kind'] == 'rum':
                key = contract.projection.contract.event_key(row['payload'])
                row['payload'] = copy.deepcopy(base.local['accepted'][key]['event'])
        self.identity = dict(fixtures.IDENTITY, os='27.0')
        self.native[0]['payload'].update(build_sdk='iphoneos27.1', os='27.0')
        self.view = next(r for r in self.rows if r['attributes']['custom']['type'] == 'view')

    def assess(self, pending=True):
        return contract.assess(self.rows, self.rows, self.native, self.identity, fixtures.EXPECTED, pending=pending)

    def add_unassessed_replay(self):
        for row in self.native:
            if row['kind'] == 'rum' and row['payload']['type'] == 'view':row['payload']['session']['has_replay'] = False

    def earlier_view(self):
        original = next(r['payload'] for r in self.native if r['kind'] == 'rum' and r['payload']['type'] == 'view')
        submitted = copy.deepcopy(original)
        self.view['attributes']['client_time'] = submitted.pop('date')
        self.view['attributes']['source'] = submitted.pop('source')
        submitted.pop('version'); submitted.pop('ddtags')
        self.view['attributes']['custom'] = submitted
        self.view['attributes']['custom']['_dd']['document_version'] = 77

    def test_terminal_required_payload_qualifies_only_named_offline_contract(self):
        before = copy.deepcopy((self.rows, self.native))
        result = self.assess(pending=False)
        self.assertEqual(result['state'], 'RUM_FIELDS_QUALIFIED')
        self.assertTrue(result['gate_payload_qualified'])
        self.assertFalse(result['runtime_acceptance']); self.assertFalse(result['release_acceptance'])
        self.assertEqual(result['gate_closures'], [])
        self.assertTrue(all(v['terminal'] for v in result['view_matches']))
        self.assertEqual((self.rows, self.native), before)

    def test_missing_replay_is_explicitly_unassessed_full_projection_stays_unqualified(self):
        self.add_unassessed_replay()
        result = self.assess(pending=False)
        self.assertEqual(result['state'], 'RUM_FIELDS_QUALIFIED')
        self.assertEqual(result['full_projection']['qualification'], 'UNQUALIFIED')
        self.assertIn('session.has_replay', {c['path'] for c in result['full_projection']['unresolved']})
        metadata = result['replay_metadata'][0]
        self.assertFalse(metadata['actual_present']); self.assertNotIn('actual', metadata)
        self.assertIs(metadata['submitted'], False)
        self.assertEqual(metadata['disposition'], 'NOT_ASSESSED_REPLAY_METADATA')
        self.assertEqual(result['replay_content_correctness'], 'NOT_ASSESSED')

    def test_present_replay_difference_is_retained_without_false_substitution(self):
        self.add_unassessed_replay(); self.view['attributes']['custom']['session']['has_replay'] = True
        result = self.assess(pending=False)
        self.assertEqual(result['state'], 'RUM_FIELDS_QUALIFIED')
        self.assertIs(result['replay_metadata'][0]['actual'], True)
        self.assertIs(result['replay_metadata'][0]['submitted'], False)
        self.assertEqual(result['full_projection']['qualification'], 'UNQUALIFIED')

    def test_malformed_replay_types_are_not_a_general_schema_escape(self):
        for value in [0, None, 'false', []]:
            self.view['attributes']['custom']['session']['has_replay'] = value
            with self.subTest(value=value), self.assertRaises(Rejected):self.assess()

    def test_exact_earlier_revision_is_pending_and_invalid_at_final_boundary(self):
        self.add_unassessed_replay(); self.earlier_view()
        result = self.assess()
        self.assertEqual(result['state'], 'PENDING'); self.assertFalse(result['gate_payload_qualified'])
        self.assertEqual(result['pending'][0]['kind'], 'EXACT_EARLIER_MAPPER_REVISION')
        match = result['view_matches'][0]
        self.assertEqual(match['backend_revision'], 77)
        self.assertEqual([m['mapper_revision'] for m in match['matched_mapper_revisions']], [1])
        self.assertFalse(match['terminal'])
        final = self.assess(pending=False)
        self.assertEqual(final['state'], 'INVALID'); self.assertFalse(final['gate_payload_qualified'])
        self.assertEqual(final['full_projection']['qualification'], 'UNQUALIFIED')

    def test_an_unknown_or_mixed_old_payload_is_invalid_not_pending(self):
        for path, value in [('view.name','wrong'), ('view.url','wrong'), ('view.time_spent',999),
                            ('view.action.count',99), ('device.brightness_level',.7)]:
            if path=='device.brightness_level':
                for row in self.native:
                    if row['kind']=='rum' and row['payload']['type']=='view':row['payload']['device']=dict(brightness_level=.5)
            self.earlier_view();target=self.view['attributes']['custom']
            for key in path.split('.')[:-1]:target=target.setdefault(key,{})
            target[path.split('.')[-1]]=value
            with self.subTest(path=path):
                result=self.assess();self.assertEqual(result['state'],'INVALID')
                self.assertEqual(result['required_failures'][0]['kind'],'VIEW_HAS_NO_EXACT_CAPTURED_REVISION')

    def test_old_active_and_terminal_duration_cannot_be_combined(self):
        self.earlier_view();self.view['attributes']['custom']['view']['time_spent']=1000
        result=self.assess();self.assertEqual(result['state'],'INVALID')
        self.assertFalse(result['gate_payload_qualified'])

    def test_date_and_event_payload_mismatch_remain_invalid(self):
        self.view['attributes']['client_time']+=1
        self.assertEqual(self.assess()['state'],'INVALID')
        self.setUp()
        action=next(r for r in self.rows if r['attributes']['custom']['type']=='action')
        action['attributes']['custom']['action']['target']['name']='wrong'
        result=self.assess();self.assertEqual(result['state'],'INVALID')
        self.assertEqual(result['required_failures'][0]['kind'],'REQUIRED_EVENT_VALUE_DIFFERS')

    def test_wrong_owner_source_crash_ttid_and_duplicates_reject(self):
        original=copy.deepcopy(self.rows)
        for mode in ['owner','source','crash','ttid','duplicate']:
            self.rows=copy.deepcopy(original)
            if mode=='owner':self.rows[0]['attributes']['custom']['view']['id']=fixtures.uid(99)
            elif mode=='source':self.rows[0]['attributes']['source']='browser'
            elif mode=='crash':self.rows[0]['attributes']['custom']['error']=dict(is_crash=True)
            elif mode=='ttid':self.rows[-1]['attributes']['custom']['vital']['duration']+=1
            else:self.rows.append(copy.deepcopy(self.rows[0]))
            with self.subTest(mode=mode),self.assertRaises(Rejected):self.assess()

    def test_missing_ingestion_never_qualifies_and_cannot_outlive_final_boundary(self):
        original=copy.deepcopy(self.rows)
        for index in range(len(original)):
            self.rows=copy.deepcopy(original[:index]+original[index+1:])
            with self.subTest(index=index):
                self.assertEqual(self.assess()['state'],'PENDING')
                final=self.assess(pending=False)
                self.assertEqual(final['state'],'INVALID');self.assertFalse(final['gate_payload_qualified'])

    def test_counts_above_expected_negative_or_wrong_type_fail_immediately(self):
        reducer=next(r['attributes']['custom'] for r in self.rows if r['attributes']['custom']['type']=='session')
        for value in [2,-1,True,'1']:
            reducer['session']['view']['count']=value
            with self.subTest(value=value):self.assertEqual(self.assess()['state'],'INVALID')
        reducer['session']['view']['count']=0
        self.assertEqual(self.assess()['state'],'PENDING');self.assertEqual(self.assess(pending=False)['state'],'INVALID')

    def test_missing_ttid_registration_or_foreign_run_never_qualifies(self):
        for mode in ['missing','foreign']:
            native=copy.deepcopy(self.native)
            if mode=='missing':self.native[1]['kind']='missing'
            else:self.native[6]['run_id']=fixtures.uid(99)
            with self.subTest(mode=mode),self.assertRaises((Rejected,ValueError)):self.assess()
            self.native=native

    def test_gate_entry_requires_complete_native_witness_even_for_matching_backend(self):
        for evidence in [None, [], {}, ()]:
            with self.subTest(evidence=evidence), self.assertRaises(Rejected):
                contract.assess(self.rows,self.rows,evidence,self.identity,fixtures.EXPECTED,pending=False)
        self.native=[r for r in self.native if r['kind']!='ttid-message']
        for i,row in enumerate(self.native,1):row['sequence']=i
        with self.assertRaises(Rejected):self.assess(pending=False)

    def test_missing_non_replay_field_is_not_excluded(self):
        for row in self.native:
            if row['kind']=='rum' and row['payload']['type']=='view':row['payload']['device']=dict(brightness_level=.5)
        result=self.assess();self.assertEqual(result['state'],'INVALID')
        self.assertIn('device', {c['path'] for c in result['required_failures'][0]['required_differences']})

    def action_projection(self):
        for row in self.native:
            if row['kind'] == 'rum' and row['payload']['type'] == 'action':
                row['payload']['context'] = {}
                row['payload']['device'] = dict(type='tablet', brightness_level=.5)
        action = next(r['attributes']['custom'] for r in self.rows if r['attributes']['custom']['type'] == 'action')
        action.pop('context', None)
        action['device'] = dict(type='Tablet', brightness_level=.5)
        return action

    def test_empty_action_context_and_documented_device_value_preserve_actual_rows(self):
        self.action_projection()
        before = copy.deepcopy((self.rows, self.native))
        result = self.assess(pending=False)
        self.assertEqual(result['state'], 'RUM_FIELDS_QUALIFIED')
        changes = next(c['differences'] for c in result['full_projection']['comparisons'] if c['event'][0] == 'action')
        self.assertEqual({(c['path'], c['disposition']) for c in changes},
                         {('context', 'EMPTY_OPTIONAL_OBJECT_OMITTED'), ('device.type', 'SOURCE_DEVICE_ENUM')})
        self.assertEqual((self.rows, self.native), before)
        self.assertFalse(result['runtime_acceptance']); self.assertFalse(result['release_acceptance'])
        self.assertEqual(result['gate_closures'], [])

    def test_action_projection_cannot_hide_lost_nonempty_context_or_malformed_values(self):
        original = copy.deepcopy((self.rows, self.native))
        for mode in ['nonempty-missing', 'null', 'false', 'list', 'brightness', 'device', 'required-context']:
            self.rows, self.native = copy.deepcopy(original)
            action = self.action_projection()
            if mode == 'nonempty-missing':
                for row in self.native:
                    if row['kind'] == 'rum' and row['payload']['type'] == 'action':row['payload']['context'] = dict(owner='expected')
            elif mode in ['null', 'false', 'list']:action['context'] = {'null':None, 'false':False, 'list':[]}[mode]
            elif mode == 'brightness':action['device']['brightness_level'] = .6
            elif mode == 'device':action['device']['type'] = 'TABLET'
            else:
                for row in self.native:
                    if row['kind'] == 'rum' and row['payload']['type'] == 'action':row['payload']['action']['context'] = {}
            with self.subTest(mode=mode):self.assertEqual(self.assess()['state'], 'INVALID')

    def test_action_projection_cannot_qualify_a_pending_terminal_view(self):
        self.action_projection(); self.earlier_view()
        result = self.assess()
        self.assertEqual(result['state'], 'PENDING')
        self.assertEqual(result['required_failures'], [])
        self.assertEqual(result['pending'][0]['kind'], 'EXACT_EARLIER_MAPPER_REVISION')
        final = self.assess(pending=False)
        self.assertEqual(final['state'], 'INVALID'); self.assertFalse(final['gate_payload_qualified'])

    def test_only_source_bound_projection_rules_apply(self):
        self.add_unassessed_replay()
        payload=self.view['attributes']['custom']
        for path in [('feature_flags',),('_dd','replay_stats'),('view','custom_timings')]:
            target=payload
            for key in path[:-1]:target=target[key]
            del target[path[-1]]
        payload['_dd']['document_version']=91
        result=self.assess(pending=False);self.assertEqual(result['state'],'RUM_FIELDS_QUALIFIED')
        self.assertEqual(result['view_matches'][0]['backend_revision'],91)
        self.assertEqual(result['full_projection']['qualification'],'UNQUALIFIED')


if __name__ == '__main__':unittest.main()
