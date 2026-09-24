"""Input selectors and one-sequence transport fail closed; no native effects."""
import copy
import json
from pathlib import Path
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch
import capture_input as c
from acceptance_common import Rejected
from capture_io import encoded


def sample(phase='setup.detail', framework='UIKit'):
    screen, target = c.PHASES[phase]; target = target or ('sheet.close' if screen == 'sheet' else screen+'.next')
    sheet = screen == 'sheet'; rect = [48, 32, 936, 1312] if sheet else [0, 0, 1032, 1376]
    marker = [rect[0]+20, rect[1]+70, 100, 20]; button = [rect[0]+20, rect[1]+120, rect[2]-40, 48]
    def fmt(r): return '{{'+str(float(r[0]))+', '+str(float(r[1]))+'}, {'+str(float(r[2]))+', '+str(float(r[3]))+'}}'
    raw = "Application bundle identifier: owned.app\nApplication UI orientation: Portrait\nApplication, pid: 123, label: 'fixture'\n"
    raw += " Window, {{0.0, 0.0}, {1032.0, 1376.0}}, hitPoint: {516.0, 688.0}\n"
    raw += "  Other, "+fmt(rect)+(f", identifier: 'controller.{screen}'" if framework == 'UIKit' else '')+"\n"
    raw += "   StaticText, "+fmt(marker)+f", identifier: 'screen.{screen}', label: '{screen}'\n"
    raw += "   Button, "+fmt(button)+f", identifier: '{target}', label: '{c.LABELS.get(target, 'unused')}', hitPoint: {{516.0, {float(button[1]+24)}}}\n"
    # Duplicate-looking content in a different app must never select a target.
    raw += "Application bundle identifier: com.apple.springboard\nApplication UI orientation: Portrait\nApplication, pid: 9, label: 'SpringBoard'\n Button, {{0.0, 0.0}, {10.0, 10.0}}, identifier: 'home.next', hitPoint: {5.0, 5.0}\n"
    request = dict(request_id='request',run_id='run',device='device',phase=phase,app_bundle='owned.app',app_pid=123,
                   issued_at=time.time()-5, deadline=time.time()+60, native_before_sequence=1)
    public = dict(uikit_window='UIKit',uikit_navigation='UIKit',uikit_split='UIKit',swiftui_hosting='SwiftUI')
    topology = dict(app_state=0,root_alive=True,window_alive=True,bound_root_unchanged=True,
        bound_root='root',bound_window='window',bound_scene='scene',framework=framework,public_bundles=public,
        fixture_bundle='fixture',window_framework_bundle='UIKit',controller_framework_bundle='UIKit',
        scene_inventory=[dict(id='scene',activation=0,screen_bounds=[0,0,1032,1376],coordinate_bounds=[0,0,1032,1376],screen_scale=2,
            windows=[dict(id='window',owned=True,key=True,root_attached=True,root='root',hidden=False,alpha=1,level=0,
                          bounds=[0,0,1032,1376],window_bundle='UIKit',root_bundle='UIKit')])],
        accessibility=[dict(identifier='screen.'+screen,frame_in_window=marker,hidden=False,alpha=1),
                       dict(identifier=target,frame_in_window=button,hidden=False,alpha=1)])
    before = dict(sequence=1,kind='human_snapshot',run_id='run',payload=dict(request_id='request',phase=phase+'.before',
        topology=topology,transition=dict(model=dict(sheet=sheet),controllers=[
            dict(id='root',window='window',children=[],presented='sheet' if sheet else 'nil',presenting='nil'),
            *([dict(id='sheet',window='window',children=[],presented='nil',presenting='root')] if sheet else [])])))
    return request, raw, before


class Selectors(unittest.TestCase):
    def test_all_eleven_declared_phases_on_both_frameworks(self):
        for framework in ['UIKit','SwiftUI']:
            for phase in c.PHASES:
                with self.subTest(framework=framework,phase=phase):
                    result=c.select(*sample(phase,framework));self.assertTrue(result['command'])
                    self.assertEqual(result['provenance']['binding']['window'],'window')
    def test_current_hitpoint_not_label_or_foreign_app(self):
        request,raw,before=sample()
        self.assertEqual(c.select(request,raw,before)['command'],'t 516 144')
        raw=raw.replace('hitPoint: {516.0, 144.0}', 'hitPoint: {520.0, 140.0}')
        self.assertEqual(c.select(request,raw,before)['command'],'t 520 140')
    def test_pid_foreground_duplicate_offscreen_role_and_activation_rejected(self):
        request,raw,before=sample()
        for bad in [raw.replace('pid: 123','pid: 99'),raw.replace('owned.app','foreign.app',1),
                    raw.replace("   Button,", "   StaticText,"),raw.replace("identifier: 'home.next'", "identifier: 'other'",1),
                    raw.replace('hitPoint: {516.0, 144.0}', 'hitPoint: {-100.0, 144.0}'),
                    raw.replace("label: 'Open detail'", "label: 'Open detail', activationBundleId: owned.app"),
                    raw.replace("   Button,", "   Button,",1)+raw.split('Application bundle identifier: com.apple.springboard')[0],
                    raw.replace("   Button,", "   Button,",1).replace("identifier: 'screen.home'", "identifier: 'home.next'",1)]:
            with self.subTest(raw=bad),self.assertRaises(Rejected):c.select(request,bad,before)
    def test_native_foreign_key_root_and_geometry_rejected(self):
        request,raw,before=sample()
        for key,value in [('key',False),('root','foreign'),('bounds',[0,0,400,800]),('owned',False)]:
            changed=copy.deepcopy(before);changed['payload']['topology']['scene_inventory'][0]['windows'][0][key]=value
            with self.subTest(key=key),self.assertRaises(Rejected):c.select(request,raw,changed)
    def test_sheet_surface_is_actual_large_enclosing_geometry(self):
        request,raw,before=sample('dismiss.finish')
        result=c.select(request,raw,before)
        self.assertEqual(result['provenance']['sheet'],[48,32,936,1312])
        self.assertEqual(result['command'],'mt [516 48] 0.9 [516 1180] 0.1')
        for bad in [raw.replace('936.0, 1312.0','200.0, 300.0'),raw.replace("controller.sheet",'other'),
                    raw.replace('48.0, 32.0','48.0, 132.0')]:
            with self.subTest(raw=bad),self.assertRaises(Rejected):c.select(request,bad,before)
    def test_swiftui_sheet_needs_attached_foremost_public_presentation(self):
        for change in ['window', 'presenting', 'absent']:
            request,raw,before=sample('dismiss.finish','SwiftUI')
            graph=before['payload']['transition']['controllers']
            if change=='absent':graph[0]['presented']='nil'
            else:graph[1][change]='foreign'
            with self.subTest(change=change),self.assertRaises((Rejected,ValueError)):c.select(request,raw,before)
    def test_inherited_presentation_getter_is_not_a_second_public_presentation(self):
        request,raw,before=sample('dismiss.cancel','SwiftUI')
        graph=before['payload']['transition']['controllers']
        graph[0]['children']=['contained']
        graph.append(dict(id='contained',window='window',children=[],presented='sheet',presenting='nil'))
        value=c.select(request,raw,before)
        self.assertEqual(value['provenance']['presentation'],dict(presenter='root',presented='sheet'))
    def test_multiple_real_reciprocal_presentations_remain_ambiguous(self):
        request,raw,before=sample('dismiss.cancel','SwiftUI')
        graph=before['payload']['transition']['controllers']
        graph.extend([dict(id='other-presenter',window='window',children=[],presented='other-sheet',presenting='nil'),
                      dict(id='other-sheet',window='window',children=[],presented='nil',presenting='other-presenter')])
        with self.assertRaises(Rejected):c.select(request,raw,before)
    def test_swiftui_small_content_stack_cannot_be_modal_geometry(self):
        request,raw,before=sample('dismiss.cancel','SwiftUI')
        with self.assertRaises(Rejected):c.select(request,raw.replace('936.0, 1312.0','300.0, 200.0'),before)
        before['payload']['transition']['model']['sheet']=False
        with self.assertRaises(Rejected):c.select(request,raw,before)


class Publication(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);root=Path(self.temp.name)
        self.folder=root/'cells/UIKit/input/setup.detail.before';self.folder.mkdir(parents=True)
        self.path=self.folder/'prompt.json';self.request,self.raw,self.snapshot=sample()
        self.native=root/'native.jsonl';self.native.write_text(json.dumps(self.snapshot)+'\n')
        self.request.update(native_events_path=str(self.native),process_identity=dict(pid=123,start='now',executable='/task'))
        self.path.write_bytes(encoded(self.request));self.path.with_name('events.jsonl').write_bytes(self.native.read_bytes())
        (root/'cells/UIKit/summary.json').write_bytes(encoded(dict(state='RUNNING',identity=dict(run_id='run',pid=123,bundle='owned.app'))))
        session=root/'sessions/UIKit';session.mkdir(parents=True);(session/'start.json').write_bytes(encoded(dict(actual_return=dict(structuredContent=dict(interactionSessionKey='current')))))
        (root/'current.txt').write_text(self.raw);(root/'current.png').write_bytes(b'actual screenshot')
        self.observed=dict(command='',interaction_session_key='current',started_at=time.time()-1,finished_at=time.time(),
            actual_return=dict(structuredContent=dict(applicationState='NotRun',hierarchyPath=str(root/'current.txt'),screenshotPath=str(root/'current.png'))))
    def run_plan(self):
        with patch.object(c.q.driver,'process_identity',return_value=self.request['process_identity']):
            return c.plan(self.path,dict(observation=self.observed))
    def test_actual_response_bound_intent_and_artifacts_preserved(self):
        result=self.run_plan();self.assertEqual(result['state'],'READY');self.assertEqual(result['command'],'t 516 144')
        self.assertTrue(self.path.with_name('action-intent.json').is_file())
        self.assertEqual(json.loads(self.path.with_name('worker-before.json').read_bytes()),self.observed)
        self.assertTrue(self.path.with_name('worker-before-screenshot.png').is_file())
    def test_stale_capture_stops_without_intent(self):
        self.observed.update(started_at=time.time()-40,finished_at=time.time()-35)
        self.request['issued_at']=time.time()-45;self.path.write_bytes(encoded(self.request))
        self.assertEqual(self.run_plan()['state'],'STOP');self.assertFalse(self.path.with_name('action-intent.json').exists())
        self.assertEqual(c.q.completed_input(self.path)['kind'],'ZERO_ACTION_CAPTURE_FAILURE')
    def test_consumed_native_readiness_stops_before_action(self):
        with self.native.open('a') as f:f.write(json.dumps(dict(sequence=2,kind='native_input',run_id='run',payload={}))+'\n')
        self.assertEqual(self.run_plan()['state'],'STOP');self.assertFalse(self.path.with_name('action-intent.json').exists())
    def test_foreign_session_and_process_prevent_input(self):
        self.observed['interaction_session_key']='old'
        self.assertEqual(self.run_plan()['state'],'STOP')
    def test_duplicate_plan_cannot_publish_zero_action_after_intent(self):
        self.run_plan()
        with self.assertRaises((FileExistsError,Rejected)):self.run_plan()
        self.assertFalse(self.path.with_name('input-failure.json').exists())
    def test_action_complete_publication_preserves_both_actual_returns(self):
        result=self.run_plan();action=copy.deepcopy(self.observed);action.update(command=result['command'],started_at=time.time(),finished_at=time.time())
        output=c.publish(self.path,dict(observation=action));self.assertEqual(output['state'],'PUBLISHED')
        proof=c.q.completed_input(self.path);self.assertEqual(proof['observations'][1]['actual_return'],action['actual_return'])
    def test_pre_dispatch_expiry_publishes_no_effect_without_erasing_intent(self):
        self.run_plan()
        with self.assertRaises(Rejected):c.abort(self.path, dict(dispatch_attempted=True))
        c.abort(self.path, dict(dispatch_attempted=False))
        self.assertTrue(self.path.with_name('action-intent.json').is_file())
        self.assertEqual(c.q.completed_input(self.path)['kind'], 'ZERO_ACTION_CAPTURE_FAILURE')
    def test_home_requires_primary_actual_springboard_not_background_presence(self):
        with self.assertRaises(Rejected):c.q.hierarchy_owner(self.request, self.raw, background=True)
        primary=self.raw[self.raw.index('Application bundle identifier: com.apple.springboard'):]
        c.q.hierarchy_owner(self.request, primary, background=True)
    def test_different_command_is_not_published_as_admitted_input(self):
        self.run_plan();action=copy.deepcopy(self.observed);action.update(command='b p',started_at=time.time(),finished_at=time.time())
        with self.assertRaises(Rejected):c.publish(self.path,dict(observation=action))
        self.assertTrue(self.path.with_name('worker-action.json').exists());self.assertFalse(self.path.with_name('tool-return.json').exists())


class AwaitedTransport(unittest.TestCase):
    def test_exact_order_and_stop_without_second_native_call(self):
        # Run the real connector with mocked supported tools, not a second copy.
        source=Path(c.__file__).with_suffix('.js')
        script=r'''
const fs=require('fs');const source=fs.readFileSync(process.argv[1],'utf8');
async function test(mode) {
 let order=[],payloads=[];
 const tools={exec_command:async x=>{let stage=x.cmd.includes(' publish ')?'publish':'plan';order.push(stage);payloads.push(x.cmd);if(mode==='yield'&&stage==='publish')return {session_id:7,output:''};return {exit_code:mode==='publish-fail'&&stage==='publish'?1:0,output:JSON.stringify(stage==='plan'?{state:mode==='stop'?'STOP':'READY',command:'t 5 6',deadline:Date.now()/1000+30}:{state:'PUBLISHED'})};},write_stdin:async x=>{if(x.session_id!==7)throw Error('foreign session');order.push('poll');return {exit_code:0,output:'{"state":"PUBLISHED"}'};},mcp__xcode__DeviceInteractionSynthesize:async x=>{order.push(x.interactionCommand?'action':'capture');if(mode==='throw'&&x.interactionCommand)throw Error('transport lost');return {structuredContent:{marker:x.interactionCommand||'actual-before'}};}};
 const result=await new Function('tools','settings','return (async()=>{'+source+'})()')(tools,{helper:'/helper',request:'/request',sessionKey:'current',deadline:Date.now()/1000+60});
 const expected=mode==='stop'?['capture','plan']:mode==='throw'?['capture','plan','action']:mode==='yield'?['capture','plan','action','publish','poll']:['capture','plan','action','publish'];
 if(JSON.stringify(order)!==JSON.stringify(expected))throw Error(JSON.stringify({mode,order,result}));
 if(!payloads[0].includes('actual-before'))throw Error('raw before lost');
 if(mode==='stop'&&result.dispatch_attempted!==false)throw Error('false input');
 if(['throw','publish-fail'].includes(mode)&&(result.state!=='STOP'||result.dispatch_attempted!==true))throw Error('uncertain dispatch hidden');
 if(mode==='publish-fail'&&!result.action.actual_return)throw Error('actual action evidence lost');
 if(['pass','yield'].includes(mode)&&(result.state!=='PUBLISHED'||!payloads[1].includes('t 5 6')))throw Error('raw action lost');
}
(async()=>{for(const m of ['pass','stop','throw','publish-fail','yield'])await test(m);})();
'''
        result=subprocess.run(['node','-e',script,str(source)],capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stderr)


if __name__=='__main__':unittest.main()
