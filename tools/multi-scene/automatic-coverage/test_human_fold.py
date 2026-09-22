"""Actual-display controls without window-count or private-class shortcuts."""
import copy
import json
import unittest
import human_fold as fold
import test_human_contract as fixtures


class HumanFoldControls(unittest.TestCase):
    def setUp(self):
        f=fixtures.NativeInputControls();f.setUp();self.binding=f.binding
        self.before=copy.deepcopy(f.evidence[2]);self.after=copy.deepcopy(f.evidence[-1]);self.after['sequence']=8
        self.after['payload']['topology']['scene_inventory'][0]['windows'][0]['bounds']=[0,0,800,800]
        self.after['payload']['topology']['scene_inventory'][0]['screen_bounds']=[0,0,800,800]
        self.after['payload']['topology']['scene_inventory'][0]['coordinate_bounds']=[0,0,800,800]
        self.a=self.display('11111111-1111-4111-8111-111111111111',[1200,2400],True)
        self.b=self.display('22222222-2222-4222-8222-222222222222',[2400,2400],False)
    def display(self,identifier,size,primary):
        return json.dumps({'info':{'outcome':'success','commandType':'devicectl.device.info.displays','arguments':['devicectl','--device','fixture']},
            'result':{'displays':[{'uniqueId':identifier,'active':True,'backlightState':'activeOn','nativeSize':size,'pointScale':3,'currentOrientation':'rot0','primary':primary}]}}).encode()
    def evaluate(self,**kwargs):
        return fold.transition(self.before,self.after,self.binding,self.a,self.b,device='fixture',sdk=kwargs.pop('sdk','27.1'),phase='open',
            before_rows=kwargs.pop('before_rows',[]),after_rows=kwargs.pop('after_rows',[]),**kwargs)
    def test_actual_display_and_owned_geometry_transition(self):self.assertEqual(self.evaluate(),'resized')
    def test_sidebar_like_pose_label_without_display_effect_rejected(self):
        self.b=self.a
        with self.assertRaises(Exception):self.evaluate()
    def test_more_windows_without_owned_resize_rejected(self):
        self.after['payload']['topology']=copy.deepcopy(self.before['payload']['topology'])
        self.after['payload']['topology']['scene_inventory'][0]['windows'].append({'id':'aux','root':'aux-root','key':False,'owned':False,'window_bundle':'runtime/UIKitCore','root_bundle':'runtime/UIKitCore'})
        with self.assertRaises(Exception):self.evaluate()
    def test_foreign_root_cannot_keep_geometry_credit(self):
        self.after['payload']['topology']['scene_inventory'][0]['windows'][0]['root']='foreign'
        with self.assertRaises(ValueError):self.evaluate()
    def test_genuine_old_build_retains_original_legacy_trait_discriminator(self):
        for snapshot in [self.before,self.after]:
            scene=snapshot['payload']['topology']['scene_inventory'][0]
            scene['windows'][0]['bounds']=scene['screen_bounds']=scene['coordinate_bounds']=[0,0,375,667]
        geometry={'kind':'geometry','sequence':2,'payload':{'scenes':[{'id':'scene','activation':0,'windows':[{'width':375,'height':667,'horizontal_size_class':1,'vertical_size_class':2}]}]}}
        self.assertEqual(self.evaluate(sdk='26.5',before_rows=[geometry],after_rows=[geometry]),'legacy_viewport_unchanged')
        with self.assertRaises(Exception):self.evaluate(sdk='27.1',before_rows=[geometry],after_rows=[geometry])
        geometry['payload']['scenes'][0]['windows'][0]['horizontal_size_class']=2
        with self.assertRaises(Exception):self.evaluate(sdk='26.5',before_rows=[geometry],after_rows=[geometry])

if __name__=='__main__':unittest.main()
