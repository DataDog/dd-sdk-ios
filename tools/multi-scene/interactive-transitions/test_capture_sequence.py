"""Finite sequence controls use actual publication validation and no native input."""
import copy
import json
from pathlib import Path
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch
import capture_sequence as s
from acceptance_common import Rejected
from capture_io import encoded
from test_capture_input import sample


class Sequence(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);self.cell=self.root/'cells/UIKit';(self.cell/'input').mkdir(parents=True)
        self.session=self.root/'sessions/UIKit';self.session.mkdir(parents=True)
        self.identity=dict(run_id='run',pid=123,bundle='owned.app',source='source',fixture='fixture',framework='UIKit')
        self.process=dict(pid=123,start='original',executable='/owned/task')
        self.summary=dict(state='RUNNING',scenario='NOT_EXECUTED',evidence='INCOMPLETE',cleanup='NOT_STARTED',
                          identity=self.identity,native_deadline=time.time()+120,cleanup_deadline=time.time()+180)
        self.save(self.cell/'summary.json',self.summary)
        self.helper=self.root/'helper.py';self.helper.write_text('frozen helper')
        self.save(self.root/'plan.json',dict(helpers={'helper.py':s.q.shared.sha(self.helper)}))
        patch.object(s.q.shared,'REPO',self.root).start()
        self.save(self.session/'start.json',dict(actual_return=dict(structuredContent=dict(
            interactionSessionKey='session',deviceUUID='device',deviceIsSimulator=True))))
        self.save(self.session/'qualified.json',dict(state='PASS'))
        self.process_mock=patch.object(s.q.driver,'process_identity',return_value=self.process).start()
        self.addCleanup(patch.stopall)
        with patch.object(s.q,'reviewed',return_value=(dict(device=dict(udid='device')),
             dict(arms={'A-simulator':dict(source='source',fixture='fixture')}),
             dict(products={'UIKit':dict(bundle='owned.app')}))):
            self.bound=s.start(self.root,'UIKit')
        self.folder=self.session/'sequence'

    @staticmethod
    def save(path,value):path.write_bytes(encoded(value))

    def payload(self,index=0,**extra):
        return dict(binding_sha256=self.bound['binding_sha256'],index=index,**extra)

    def prompt(self,index=0):
        phase=s.PHASES[index];request,raw,before=sample(phase)
        folder=self.cell/'input'/(phase+'.before');folder.mkdir()
        path=folder/'prompt.json';native=folder/'native.jsonl'
        native.write_text(json.dumps(before)+'\n')
        request.update(native_events_path=str(native),process_identity=self.process)
        self.save(path,request);path.with_name('events.jsonl').write_bytes(native.read_bytes())
        (folder/'actual.txt').write_text(raw);(folder/'actual.png').write_bytes(b'actual screenshot')
        observation=dict(command='',interaction_session_key='session',started_at=time.time()-1,finished_at=time.time(),
            actual_return=dict(structuredContent=dict(applicationState='NotRun',hierarchyPath=str(folder/'actual.txt'),
                                                     screenshotPath=str(folder/'actual.png'))))
        return path,observation

    def publish(self,path,before):
        selection=s.c.plan(path,dict(observation=before));self.assertEqual(selection['state'],'READY')
        action=copy.deepcopy(before);action.update(command=selection['command'],started_at=time.time(),finished_at=time.time())
        if json.loads(path.read_bytes())['phase']=='background':
            folder=path.parent; raw=(folder/'actual.txt').read_text();raw=raw[raw.index('Application bundle identifier: com.apple.springboard'):]
            (folder/'after.txt').write_text(raw);action['actual_return']['structuredContent']['hierarchyPath']=str(folder/'after.txt')
        result=s.c.publish(path,dict(observation=action));self.assertEqual(result['state'],'PUBLISHED')
        return dict(state='PUBLISHED',dispatch_attempted=True,before=before,action=action,result=result)

    def test_order_matches_executed_stack_driver(self):
        calls=[]
        class Stack:
            def ensure_root(self,*args):pass
            def perform(self,step):calls.append(step['phase'])
            def interactive(self,phase):calls.append(phase)
            def home(self):calls.append('background')
        s.q.driver.Collector.stack(Stack())
        self.assertEqual(tuple(calls),s.PHASES)

    def test_complete_sequence_requires_actual_durable_publication(self):
        for index,phase in enumerate(s.PHASES):
            path,before=self.prompt(index)
            ready=s.next_request(self.root,'UIKit',self.payload(index))
            self.assertEqual((ready['state'],ready['phase']),('REQUEST',phase))
            result=self.publish(path,before)
            recorded=s.record(self.root,'UIKit',self.payload(index,result=result))
            self.assertEqual((recorded['state'],recorded['next_index']),('RECORDED',index+1))
        self.summary.update(state='INVALID',cleanup='APP_REMOVED_SESSION_RESTORE_PENDING')
        self.save(self.cell/'summary.json',self.summary)
        self.assertEqual(s.next_request(self.root,'UIKit',self.payload(11))['state'],'TERMINAL')
        self.assertFalse((self.folder/'stop.json').exists())

    def test_skipped_replayed_and_boolean_indices_rejected(self):
        self.prompt()
        for value in [1,-1,True,'0']:
            with self.subTest(index=value),self.assertRaises(Rejected):s.next_request(self.root,'UIKit',self.payload(value))

    def test_next_phase_before_durable_exchange_rejected(self):
        path,before=self.prompt();self.publish(path,before);self.prompt(1)
        with self.assertRaises(Rejected):s.next_request(self.root,'UIKit',self.payload(1))
        with self.assertRaises(Rejected):s.next_request(self.root,'UIKit',self.payload(0))

    def test_reordered_or_duplicate_native_prompt_rejected(self):
        path,_=self.prompt(1)
        with self.assertRaises(Rejected):s.next_request(self.root,'UIKit',self.payload())
        path.unlink();path,_=self.prompt(0)
        duplicate=self.cell/'input/duplicate';duplicate.mkdir();(duplicate/'prompt.json').write_bytes(path.read_bytes())
        with self.assertRaises(Rejected):s.next_request(self.root,'UIKit',self.payload())

    def test_changed_run_pid_and_deadlines_rejected(self):
        self.prompt()
        for field,value in [('run_id','restored'),('pid',999),('native_deadline',self.summary['native_deadline']+1),
                            ('cleanup_deadline',self.summary['cleanup_deadline']+1)]:
            changed=copy.deepcopy(self.summary)
            if field in changed:changed[field]=value
            else:changed['identity'][field]=value
            self.save(self.cell/'summary.json',changed)
            with self.subTest(field=field),self.assertRaises(Rejected):s.next_request(self.root,'UIKit',self.payload())

    def test_changed_process_or_session_rejected(self):
        self.prompt();self.process_mock.return_value=dict(self.process,start='reused PID')
        with self.assertRaises(Rejected):s.next_request(self.root,'UIKit',self.payload())
        self.process_mock.return_value=self.process
        self.save(self.session/'start.json',dict(foreign='session'))
        with self.assertRaises(Rejected):s.next_request(self.root,'UIKit',self.payload())

    def test_foreign_binding_and_foreign_prompt_rejected(self):
        path,_=self.prompt()
        with self.assertRaises(Rejected):s.next_request(self.root,'UIKit',dict(index=0,binding_sha256='old'))
        request=json.loads(path.read_bytes())
        for field,value in [('run_id','foreign'),('app_pid',999),('app_bundle','foreign'),('device','foreign'),
                            ('process_identity',dict(self.process,start='new'))]:
            self.save(path,dict(request,**{field:value}))
            with self.subTest(field=field),self.assertRaises(Rejected):s.next_request(self.root,'UIKit',self.payload())

    def test_changed_helper_rejected_before_input(self):
        self.prompt();self.helper.write_text('changed helper')
        with self.assertRaises(Rejected):s.next_request(self.root,'UIKit',self.payload())

    def test_consumed_native_readiness_rejected(self):
        path,_=self.prompt();native=Path(json.loads(path.read_bytes())['native_events_path'])
        with native.open('a') as f:f.write(json.dumps(dict(sequence=2,kind='native_input',run_id='run',payload={}))+'\n')
        with self.assertRaises(Rejected):s.next_request(self.root,'UIKit',self.payload())

    def test_late_phase_and_original_native_bound_rejected(self):
        path,_=self.prompt();request=json.loads(path.read_bytes());request['deadline']=time.time()-1;self.save(path,request)
        with self.assertRaises(Rejected):s.next_request(self.root,'UIKit',self.payload())
        with patch.object(s.time,'time',return_value=self.bound['native_deadline']+1),self.assertRaises(Rejected):
            s.next_request(self.root,'UIKit',self.payload())

    def test_cleanup_and_stop_forbid_next_effect(self):
        self.prompt();self.summary['cleanup']='INCOMPLETE';self.save(self.cell/'summary.json',self.summary)
        with patch.object(s.c,'pending') as pending:
            self.assertEqual(s.next_request(self.root,'UIKit',self.payload())['state'],'TERMINAL');pending.assert_not_called()
        stopped=s.stop(self.root,'UIKit',self.payload(reason='stop'))
        before=Path(stopped['receipt']).read_bytes();s.stop(self.root,'UIKit',self.payload(reason='cannot replace'))
        self.assertEqual(Path(stopped['receipt']).read_bytes(),before)
        with self.assertRaises(Rejected):s.next_request(self.root,'UIKit',self.payload())

    def test_missing_publication_keeps_full_actual_failure_and_stops(self):
        self.prompt();raw=dict(state='STOP',dispatch_attempted=True,action=dict(actual_return=dict(content=['actual failure'])))
        result=s.record(self.root,'UIKit',self.payload(result=raw))
        self.assertEqual(result['state'],'STOPPED')
        self.assertEqual(json.loads(Path(result['receipt']).read_bytes())['payload']['result'],raw)
        self.assertNotIn('input_complete',json.loads((self.folder/'stop.json').read_bytes()))
        with self.assertRaises(Rejected):s.next_request(self.root,'UIKit',self.payload(1))

    def test_duplicate_and_malformed_record_retained_without_overwrite(self):
        path,before=self.prompt();raw=self.publish(path,before)
        self.assertEqual(s.record(self.root,'UIKit',self.payload(result=raw))['state'],'RECORDED')
        original=(self.folder/'exchanges/0.json').read_bytes()
        for payload in [self.payload(result=raw),self.payload(99,result={'actual':'late'}),dict(index=0,actual='foreign')]:
            result=s.record(self.root,'UIKit',payload);self.assertEqual(result['state'],'STOPPED')
            self.assertEqual(json.loads(Path(result['receipt']).read_bytes())['payload'],payload)
        self.assertEqual((self.folder/'exchanges/0.json').read_bytes(),original)

    def test_session_change_does_not_erase_failed_exchange(self):
        self.prompt();self.save(self.session/'start.json',dict(changed=True))
        result=s.record(self.root,'UIKit',self.payload(result=dict(actual='retained')))
        self.assertEqual(result['state'],'STOPPED');self.assertTrue(Path(result['receipt']).is_file())
        self.assertTrue((self.folder/'stop.json').is_file())

    def test_actual_response_substitution_stops(self):
        path,before=self.prompt();raw=self.publish(path,before);raw['before']['actual_return']={'substituted':True}
        self.assertEqual(s.record(self.root,'UIKit',self.payload(result=raw))['state'],'STOPPED')


class AwaitedSequence(unittest.TestCase):
    def test_real_connector_finite_order_and_failure_preservation(self):
        script=r'''
const fs=require('fs');const source=fs.readFileSync(process.argv[1],'utf8');
async function run(mode) {
 let index=0, dispatched=0, events=[], saved=[], clock=Date.now(), stopCalls=0;
 const original=Date.now;Date.now=()=>clock;
 const bound={state:'BOUND',binding_sha256:'bound',session_key:'live',phase_count:11,native_deadline:clock/1000+60,cleanup_deadline:clock/1000+90};
 function reply(value){return {exit_code:0,output:JSON.stringify(value)};}
 const tools={exec_command:async x=>{
  const stage=x.cmd.match(/'\/sequence' (\w+)/)?.[1];
  if(stage) {
   const payload=JSON.parse(x.cmd.split("<<'CAPTURE_SEQUENCE_JSON'\n")[1].split('\nCAPTURE_SEQUENCE_JSON')[0]);
   events.push(stage);
   if(stage==='bind')return reply(bound);
   if(stage==='next')return reply(index===11?{state:'TERMINAL',completed:11,cleanup:'PENDING'}:
     {state:'REQUEST',index,phase:'phase'+index,request:'/request',session_key:'live',deadline:bound.native_deadline});
   if(stage==='record'){
    saved.push(payload);if(payload.index!==index)throw Error('skipped record');
    if(['persist-fail','late-preserve'].includes(mode))return {exit_code:1,output:'publication unavailable'};
    if(payload.result.state==='PUBLISHED'){index++;return reply({state:'RECORDED',next_index:index});}
    return reply({state:'STOPPED'});
   }
   if(stage==='stop'){stopCalls++;return mode==='late-preserve'?{session_id:7,output:''}:reply({state:'STOPPED',receipt:'/stop'});}
  }
  if(x.cmd.includes(' plan '))return reply({state:'READY',command:'t 5 6',deadline:bound.native_deadline});
  if(x.cmd.includes(' publish ')) {
   if(mode==='late-preserve'){clock+=61000;return {exit_code:1,output:'late actual response'};}
   return reply({state:'PUBLISHED'});
  }
  throw Error('unexpected command');
 },write_stdin:async x=>{if(x.session_id!==7)throw Error('wrong pending');return reply({state:'STOPPED',receipt:'/stop'});},
 mcp__xcode__DeviceInteractionSynthesize:async x=>{
  events.push(x.interactionCommand?'action':'capture');
  if(x.interactionCommand){dispatched++;if(mode==='disconnect')throw Error('provider disconnected after dispatch');}
  return {structuredContent:{exact:events.length,command:x.interactionCommand}};
 }};
 try {
  const result=await new Function('tools','settings','return (async()=>{'+source+'})()')(tools,
   {helper:'/phase',sequenceHelper:'/sequence',sequenceRoot:'/root',framework:'UIKit'});
  if(mode==='pass'){
   if(result.state!=='TERMINAL'||index!==11||dispatched!==11||stopCalls!==1)throw Error(JSON.stringify({mode,result,index,dispatched}));
   for(let i=0;i<11;i++)if(!saved[i].result.before.actual_return||!saved[i].result.action.actual_return)throw Error('raw lost');
   if(events.filter(x=>x==='record').length!==11)throw Error('missing persistence');
   for(let i=0;i<events.length;i++)if(events[i]==='record'&&events[i+1]!=='next')throw Error('order differs');
  }else{
   if(result.state!=='STOP'||dispatched!==1||saved.length!==1)throw Error(JSON.stringify({mode,result,dispatched}));
   if(saved[0].result.dispatch_attempted!==true)throw Error('uncertainty treated as no input');
   if(mode!=='disconnect'&&!saved[0].result.action.actual_return)throw Error('actual result erased');
   if(['persist-fail','late-preserve'].includes(mode)&&!result.stop)throw Error('failed record not preserved in stop');
  }
 } finally {Date.now=original;}
}
(async()=>{for(const mode of ['pass','disconnect','persist-fail','late-preserve'])await run(mode)})();
'''
        result=subprocess.run(['node','-e',script,str(Path(s.c.__file__).with_suffix('.js'))],capture_output=True,text=True,timeout=20)
        self.assertEqual(result.returncode,0,result.stderr)


if __name__=='__main__':unittest.main()
