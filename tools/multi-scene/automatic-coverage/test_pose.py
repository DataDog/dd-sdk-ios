import copy
import unittest
from pose import transition_valid


def fixture():
    def geometry(seq, timestamp, width, height):
        return {'sequence': seq, 'timestamp': timestamp, 'kind': 'geometry', 'payload': {'scenes': [
            {'id': 'scene', 'activation': 0, 'windows': [{'width': width, 'height': height}]}]}}
    before = {'display': {'observed_at': 2, 'active': {'primary': True, 'uniqueId': 'outer', 'backlightState': 'activeOn'}},
              'geometry': geometry(1, 0.5, 466, 678)}
    after = {'display': {'observed_at': 4, 'active': {'primary': False, 'uniqueId': 'inner', 'backlightState': 'activeOn'}},
             'geometry': geometry(2, 3, 669, 951)}
    return before, after


class PoseReceiptTests(unittest.TestCase):
    def test_real_open_control(self): transition_valid(*fixture(), 'open', 1)
    def test_real_reopen_control(self): transition_valid(*fixture(), 'reopen', 1)
    def test_real_close_control(self):
        before, after = fixture()
        before['display']['active'], after['display']['active'] = after['display']['active'], before['display']['active']
        transition_valid(before, after, 'close', 1)
    def rejects(self, mutate):
        before, after = fixture(); mutate(before, after)
        with self.assertRaises(AssertionError): transition_valid(before, after, 'open', 1)
    def test_stale_precondition(self): self.rejects(lambda b,a: b['display'].update(observed_at=0))
    def test_stale_display(self): self.rejects(lambda b,a: a['display'].update(observed_at=1))
    def test_wrong_initial_display(self): self.rejects(lambda b,a: b['display']['active'].update(primary=False))
    def test_wrong_final_display(self): self.rejects(lambda b,a: a['display']['active'].update(primary=True))
    def test_same_display(self): self.rejects(lambda b,a: a['display']['active'].update(uniqueId='outer'))
    def test_inactive_display(self): self.rejects(lambda b,a: a['display']['active'].update(backlightState='off'))
    def test_stale_geometry(self): self.rejects(lambda b,a: a['geometry'].update(timestamp=0.9))
    def test_late_geometry(self): self.rejects(lambda b,a: a['geometry'].update(timestamp=5))
    def test_reused_sequence(self): self.rejects(lambda b,a: a['geometry'].update(sequence=1))
    def test_replaced_scene(self): self.rejects(lambda b,a: a['geometry']['payload']['scenes'][0].update(id='other'))
    def test_background_geometry(self): self.rejects(lambda b,a: a['geometry']['payload']['scenes'][0].update(activation=2))
    def test_no_geometry_change(self): self.rejects(lambda b,a: a['geometry']['payload'].update(scenes=copy.deepcopy(b['geometry']['payload']['scenes'])))
    def test_empty_windows(self): self.rejects(lambda b,a: a['geometry']['payload']['scenes'][0].update(windows=[]))
    def test_late_precondition_geometry(self): self.rejects(lambda b,a: b['geometry'].update(timestamp=2))

    def duplicate_legacy_windows(self):
        before, after = fixture()
        window = {'width': 375, 'height': 667, 'horizontal_size_class': 1, 'vertical_size_class': 2}
        before['geometry']['payload']['scenes'][0]['windows'] = [window]
        after['geometry']['payload']['scenes'][0]['windows'] = [window.copy(), window.copy()]
        return before, after
    def test_duplicate_windows_do_not_prove_spatial_resize(self):
        with self.assertRaisesRegex(AssertionError, 'duplicate windows'):
            transition_valid(*self.duplicate_legacy_windows(), 'open', 1)
    def test_fresh_legacy_inventory_and_display_change_are_labeled_honestly(self):
        self.assertEqual(transition_valid(*self.duplicate_legacy_windows(), 'open', 1,
                                        allow_legacy_viewport=True), 'legacy_viewport_unchanged')
    def test_legacy_mode_still_requires_fresh_geometry(self):
        before, after = self.duplicate_legacy_windows(); after['geometry']['timestamp'] = 0.5
        with self.assertRaisesRegex(AssertionError, 'stale native geometry'):
            transition_valid(before, after, 'open', 1, allow_legacy_viewport=True)
    def test_legacy_mode_does_not_allow_other_stable_geometry(self):
        before, after = self.duplicate_legacy_windows()
        for state in [before, after]:
            for window in state['geometry']['payload']['scenes'][0]['windows']: window['width'] = 466
        with self.assertRaisesRegex(AssertionError, 'duplicate windows'):
            transition_valid(before, after, 'open', 1, allow_legacy_viewport=True)
    def test_legacy_mode_still_requires_actual_display_change(self):
        before, after = self.duplicate_legacy_windows(); after['display']['active']['uniqueId'] = 'outer'
        with self.assertRaisesRegex(AssertionError, 'active display did not change'):
            transition_valid(before, after, 'open', 1, allow_legacy_viewport=True)

if __name__ == '__main__': unittest.main()
