import copy
import unittest
import clean_integration as clean


class CleanIntegrationTests(unittest.TestCase):
    def test_helper_amendment_requires_the_exact_before_after_inventory(self):
        original = dict(helpers={'a':'old', 'b':'same'}, source='sdk')
        self.assertEqual(clean.amended(original, {'a':'new', 'b':'same'}, {'a':dict(before='old', after='new')})['source'], 'sdk')
        for current, changes in [({'a':'new','b':'changed'}, {'a':dict(before='old',after='new')}),
                                 ({'a':'new','b':'same'}, {}), ({'a':'new','b':'same'}, {'a':dict(before='other',after='new')})]:
            with self.assertRaises(ValueError): clean.amended(original, current, changes)

    def test_workspace_binding_is_explicit_and_never_rewrites_original_inputs(self):
        original = dict(helpers={'a': 'same'}, protected={'old': 'snapshot'})
        before = copy.deepcopy(original); transition = {'authority': 'bound'}
        value = clean.amended(original, original['helpers'], {}, transition)
        self.assertEqual(value['workspace_transition'], transition)
        self.assertEqual(value['protected'], original['protected'])
        self.assertEqual(original, before)
        self.assertNotIn('workspace_transition', clean.amended(original, original['helpers'], {}))
        with self.assertRaises(ValueError): clean.amended(value, original['helpers'], {}, transition)

    def test_creation_requires_new_uuid_exact_type_runtime_name_and_state(self):
        identifier = '11111111-1111-4111-8111-111111111111'; spec = dict(runtime_identifier='runtime', device_type='type')
        row = dict(udid=identifier, name='owned', state='Shutdown', isAvailable=True, deviceTypeIdentifier='type')
        before = dict(devices={'runtime':[]}); after = dict(devices={'runtime':[row]})
        self.assertEqual(clean.created_identity(before, after, identifier, 'owned', spec), row)
        for key, value in [('udid','other'), ('name','foreign'), ('state','Booted'), ('isAvailable',False), ('deviceTypeIdentifier','foreign')]:
            changed = copy.deepcopy(after); changed['devices']['runtime'][0][key] = value
            with self.assertRaises(ValueError): clean.created_identity(before, changed, identifier, 'owned', spec)
        with self.assertRaises(ValueError): clean.created_identity(after, after, identifier, 'owned', spec)
        with self.assertRaises(ValueError): clean.created_identity(before, {'devices':{'foreign':[row]}}, identifier, 'owned', spec)

    def test_actual_created_runtime_replaces_the_old_destination_and_label(self):
        base = dict(cells=[dict(id='integration', runtime='26.5')], environments={'26.5': 'old-host'})
        for runtime in ['17.5', '26.5']:
            created = dict(runtime=dict(version=runtime, identifier='com.apple.CoreSimulator.SimRuntime.iOS-' + runtime.replace('.', '-')),
                           device=dict(udid='new-host'))
            fresh, cell = clean.runtime_cell(base, created)
            self.assertEqual(cell['runtime'], runtime)
            self.assertEqual(fresh['environments'], {runtime: created})
            self.assertTrue(cell['require_clean_data'])
            self.assertEqual(fresh['cells'], [cell])
        self.assertEqual(base['environments'], {'26.5': 'old-host'})
        for runtime, identifier in [('27.0', 'com.apple.CoreSimulator.SimRuntime.iOS-27-0'), ('17.5', 'foreign')]:
            with self.assertRaises(ValueError): clean.runtime_cell(base, dict(runtime=dict(version=runtime, identifier=identifier)))
        with self.assertRaises(ValueError): clean.runtime_cell(dict(base, cells=[]), created)


if __name__ == '__main__': unittest.main()
