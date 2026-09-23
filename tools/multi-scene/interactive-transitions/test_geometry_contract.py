import copy
import unittest
import geometry_contract as c


def snapshot(visible='detail',sheet=False):
    nodes=[dict(id='root',window='window',presented='sheet' if sheet else 'nil',children=['home','detail'],
                navigation_stack=['home','detail'],visible=visible),
           dict(id='home',window='window',presented='nil',children=[]),
           dict(id='detail',window='window',presented='nil',children=[])]
    if sheet:nodes.append(dict(id='sheet',window='window',presented='nil',children=[]))
    return dict(payload=dict(transition=dict(controllers=nodes)))
BINDING=dict(root='root',window='window',scene='scene')

class FrontmostOwnership(unittest.TestCase):
    def test_attached_hidden_navigation_owner_is_not_foremost(self):
        self.assertEqual(c.front_controllers(snapshot(),BINDING),{'root','detail'})
    def test_presented_sheet_excludes_underlying_content(self):
        self.assertEqual(c.front_controllers(snapshot(sheet=True),BINDING),{'sheet'})
    def test_cancel_and_completion_follow_actual_hierarchy(self):
        a=snapshot();b=snapshot(visible='home')
        result=dict(cancelled=False,**{'from':'detail','result':'home'})
        c.visible_transition(a,b,BINDING,result)
        with self.assertRaises(ValueError):c.visible_transition(a,a,BINDING,result)
        result.update(cancelled=True,result='detail');c.visible_transition(a,a,BINDING,result)
    def test_missing_or_detached_result_rejected(self):
        value=snapshot();value['payload']['transition']['controllers'][2]['window']='nil'
        with self.assertRaises(ValueError):c.front_controllers(value,BINDING)
    def test_foreign_visible_navigation_owner_rejected(self):
        value=snapshot();value['payload']['transition']['controllers'][0]['visible']='foreign'
        with self.assertRaises(ValueError):c.front_controllers(value,BINDING)
    def test_cyclic_public_hierarchy_rejected(self):
        value=snapshot();value['payload']['transition']['controllers'][2]['children']=['root']
        with self.assertRaises(ValueError):c.front_controllers(value,BINDING)



class AdaptiveGeometry(unittest.TestCase):
    def value(self,sequence,width):
        value=snapshot();value['sequence']=sequence
        value['payload']['transition']['model']=dict(selection='detail',selection_occurrence='same',path=[],sheet=False)
        value['payload']['topology']=dict(scene_inventory=[dict(id='scene',windows=[dict(id='window',bounds=[0,0,width,800])])])
        return value
    def test_real_swiftui_selection_does_not_assume_uikit_split_implementation(self):
        a,b=self.value(1,400),self.value(2,800);value=c.adaptive(a,b,BINDING,'SwiftUI')
        self.assertEqual(value['state'],'ADAPTIVE_SELECTION_AND_NATIVE_GEOMETRY_QUALIFIED')
    def test_same_name_new_selection_occurrence_rejected(self):
        a,b=self.value(1,400),self.value(2,800);b['payload']['transition']['model']['selection_occurrence']='new'
        with self.assertRaises(ValueError):c.adaptive(a,b,BINDING,'SwiftUI')
    def test_unchanged_size_foreign_scene_or_reversed_boundary_rejected(self):
        for mode in ['size','scene','clock']:
            a,b=self.value(1,400),self.value(2,800)
            if mode=='size':b['payload']['topology']=copy.deepcopy(a['payload']['topology'])
            if mode=='scene':b['payload']['topology']['scene_inventory'][0]['id']='foreign'
            if mode=='clock':b['sequence']=0
            with self.subTest(mode=mode),self.assertRaises(ValueError):c.adaptive(a,b,BINDING,'SwiftUI')

class ExactRestoration(unittest.TestCase):
    def value(self,sequence,width):
        value=AdaptiveGeometry().value(sequence,width);scene=value['payload']['topology']['scene_inventory'][0]
        scene.update(activation=0,screen_bounds=[0,0,width,800],coordinate_bounds=[0,0,width,800],screen_scale=3)
        scene['windows'][0].update(root='root',key=True,root_attached=True,hidden=False,alpha=1,level=0)
        return value
    def test_restored_state_must_match_original_not_merely_be_smaller(self):
        a,b=self.value(1,400),self.value(4,400)
        display=dict(uniqueId='actual-display',displayId=1,nativeSize=[1200,2400],pointScale=3,currentOrientation='rot0',bounds=[0,0,400,800],primary=True)
        c.restored(a,b,BINDING,'SwiftUI',display,display)
        for key,value in [('uniqueId','another-closed-display'),('currentOrientation','rot180'),('primary',False)]:
            with self.subTest(key=key),self.assertRaises(ValueError):c.restored(a,b,BINDING,'SwiftUI',display,dict(display,**{key:value}))
        b['payload']['topology']['scene_inventory'][0]['windows'][0]['bounds']=[0,0,390,800]
        with self.assertRaises(ValueError):c.restored(a,b,BINDING,'SwiftUI',display,display)

if __name__=='__main__':unittest.main()
