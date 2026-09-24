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


if __name__ == '__main__': unittest.main()
