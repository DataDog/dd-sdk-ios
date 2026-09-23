import copy
import unittest
from contract import Invalid
from physical_contract import app_absence, display, ready_admission
import test_trace_contract as trace_controls


class PhysicalControls(unittest.TestCase):
    def test_real_physical_display_shape(self):
        f=trace_controls.TraceControls().fixture();value=display(f[5],f[7]);self.assertEqual(value['displayId'],1)
        self.assertNotIn('uniqueId',value)

    def test_foreign_inactive_external_or_ambiguous_display(self):
        for change in ['foreign','inactive','external','ambiguous','zero-size']:
            f=trace_controls.TraceControls().fixture();raw=f[5];screen=raw['result']['displays'][0]
            if change=='foreign':raw['info']['arguments'][-1]='other'
            elif change=='inactive':screen['backlightState']='inactiveOn'
            elif change=='external':screen['type']={'external':{}}
            elif change=='ambiguous':raw['result']['displays'].append(copy.deepcopy(screen))
            else:screen['nativeSize']=[0,1]
            with self.subTest(change=change),self.assertRaises(Invalid):display(raw,f[7])

    def test_complete_apps_absence(self):
        raw={'info':{'outcome':'success','commandType':'devicectl.device.info.apps','arguments':['--device','device']},
             'result':{'deviceIdentifier':'device','matchingBundleIdentifier':'bundle','apps':[]}}
        self.assertTrue(app_absence(raw,'device','bundle'))
        for field,value in [('deviceIdentifier','other'),('matchingBundleIdentifier','other'),('apps',[{}])]:
            bad=copy.deepcopy(raw);bad['result'][field]=value
            with self.subTest(field=field),self.assertRaises(Invalid):app_absence(bad,'device','bundle')

    def test_ready_payload_cannot_use_stale_identity(self):
        identity=dict(run_id='run',nonce='nonce',pid=123,source='a',fixture='b',framework='UIKit')
        self.assertTrue(ready_admission(dict(state='TRACE_READY',**identity),identity))
        for field in identity:
            bad=dict(state='TRACE_READY',**identity);bad[field]='stale'
            with self.subTest(field=field),self.assertRaises(Invalid):ready_admission(bad,identity)
