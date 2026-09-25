import copy
import unittest
import journey_phases as phases
from acceptance_common import Rejected
from test_capture_contract import payload
from test_journey_contract import topology, EXPECTED, event, mapped, uid


def rows_for_phase():
    state=topology();state['controllers'].append(dict(id='list',label='List of Services',window='window',scene='scene',transition={}))
    entries=[('owned_window',dict(window='window',scene='scene')),('navigation_callback',dict(callback='didShow-exit',controller={'id':'list'},stack=['list'])),
             ('snapshot',dict(topology=state))]
    rows,_=payload(entries)
    return rows,rows[-2]


class JourneyPhaseTests(unittest.TestCase):
    def test_label_alone_is_not_source_or_native_navigation_ownership(self):
        rows,snapshot=rows_for_phase();binding=phases.foreground_binding(rows,snapshot)
        value=phases.visible(rows,snapshot,'list',binding)
        self.assertEqual(value['controller'],'list')
        for mode in ['stack','callback','window','transition','source-window']:
            changed=copy.deepcopy(rows);last=changed[-2]
            if mode=='stack':changed[2]['fields']['stack']=['foreign']
            if mode=='callback':changed[2]['fields']['callback']='willShow-exit'
            if mode=='window':last['fields']['topology']['controllers'][-1]['window']='nil'
            if mode=='transition':last['fields']['topology']['controllers'][-1]['transition']={'interactive':True}
            if mode=='source-window':changed[0]['fields']['window']='foreign'
            with self.subTest(mode=mode),self.assertRaises(Rejected):
                selected=phases.foreground_binding(changed,last);phases.visible(changed,last,'list',selected)
    def test_root_may_change_only_at_declared_authenticated_transition(self):
        rows,snapshot=rows_for_phase();original=phases.foreground_binding(rows,snapshot)
        snapshot['fields']['topology']['scene_inventory'][0]['windows'][0]['root']='authenticated-root'
        with self.assertRaisesRegex(Rejected,'root changed'):phases.foreground_binding(rows,snapshot,original)
        self.assertEqual(phases.foreground_binding(rows,snapshot,original,authenticated_transition=True)['root'],'authenticated-root')
        snapshot['fields']['topology']['scene_inventory'][0]['id']='foreign'
        with self.assertRaises(Rejected):phases.foreground_binding(rows,snapshot,original,authenticated_transition=True)
    def test_cancelled_or_repeated_lifecycle_pairs_are_not_complete(self):
        rows,_=payload([('scene_callback',dict(callback=phase,scene='scene')) for phase in ['didEnterBackground-enter','didEnterBackground-exit']])
        self.assertEqual(phases.lifecycle(rows,0,4,'scene','didEnterBackground'),[1,3])
        for mode in ['missing','repeat','foreign','late']:
            changed=copy.deepcopy(rows);end=4
            if mode=='missing':changed.pop(2)
            if mode=='repeat':changed.append(dict(changed[2]))
            if mode=='foreign':changed[2]['fields']['scene']='other'
            if mode=='late':end=2
            with self.subTest(mode=mode),self.assertRaises(Rejected):phases.lifecycle(changed,0,end,'scene','didEnterBackground')
    def test_login_back_target_requires_actual_form_and_adjacent_geometry(self):
        tree=[dict(type='StaticText',AXLabel='Enter Subdomain',frame=dict(x=100,y=50,width=200,height=40)),
              dict(type='TextField',enabled=True,AXValue='subdomain'),
              dict(type='Button',AXLabel='Back',enabled=True,frame=dict(x=40,y=50,width=50,height=40))]
        self.assertTrue(phases.login(tree,True));self.assertEqual(phases.back_target(tree),tree[-1])
        self.assertFalse(phases.home(tree))
        for mode in ['missing-form','foreign-button','duplicate']:
            changed=copy.deepcopy(tree)
            if mode=='missing-form':changed.pop(1)
            if mode=='foreign-button':changed[-1]['frame']['x']=400
            if mode=='duplicate':changed.append(copy.deepcopy(changed[-1]))
            with self.subTest(mode=mode),self.assertRaises(Rejected):phases.back_target(changed)


    def test_home_process_identity_does_not_overwrite_command_receipt(self):
        from pathlib import Path
        import tempfile
        from unittest.mock import patch
        import journey_driver
        with tempfile.TemporaryDirectory() as name:
            folder=Path(name)
            def command(argv,out,label,**kwargs):
                (out/(label+'.json')).write_text('command receipt')
                (out/(label+'.log')).write_text('7 /sim/RuntimeRoot/System/Library/CoreServices/SpringBoard.app/SpringBoard')
            with patch.object(journey_driver.shared,'command',side_effect=command),patch.object(phases,'home',return_value=True):
                self.assertTrue(journey_driver.home_observation([dict(pid=7)],folder,12345678900))
            self.assertEqual((folder/'home-process.json').read_text(),'command receipt')
            self.assertTrue((folder/'home-process-identity.json').is_file())

    def test_home_requires_system_process_and_actual_active_screen_geometry(self):
        frame=dict(x=0,y=0,width=466,height=678)
        tree=[dict(type='Application',pid=7,frame=frame,children=[
            dict(type='Group',pid=7,AXUniqueId='Home screen icons',enabled=True,frame=frame),
            dict(type='Slider',pid=7,AXUniqueId='Page control',enabled=True,frame=dict(x=100,y=640,width=50,height=35))])]
        process=dict(pid=7,executable='/sim/RuntimeRoot/System/Library/CoreServices/SpringBoard.app/SpringBoard')
        self.assertTrue(phases.home(tree,process))
        for mode in ['foreign-pid','app-process','mixed-pid','missing-icons','offscreen-page','wrong-display','missing-process','label-only']:
            changed=copy.deepcopy(tree);observed=copy.deepcopy(process)
            if mode=='foreign-pid':observed['pid']=8
            if mode=='app-process':observed['executable']='/app/DatadogApp.app/DatadogApp'
            if mode=='mixed-pid':changed[0]['children'][0]['pid']=8
            if mode=='missing-icons':changed[0]['children'].pop(0)
            if mode=='offscreen-page':changed[0]['children'][1]['frame']['x']=600
            if mode=='wrong-display':changed[0]['children'][0]['frame']=dict(x=0,y=0,width=669,height=951)
            if mode=='missing-process':observed=None
            if mode=='label-only':changed=[dict(type='Button',AXLabel='Home')]
            with self.subTest(mode=mode):self.assertFalse(phases.home(changed,observed))


if __name__=='__main__':unittest.main()
