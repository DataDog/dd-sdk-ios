"""Human input only; actual native/mapper effects and display receipts stay local."""
import json
import re
from pathlib import Path
import sys
import time
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'automatic-coverage'))
import human_capture as shared_capture
import human_contract as capture_contract
import human_journey as journey
import human_fold
import s2_hosting_workflow as shared
import s2_webview_driver as transport
import s2_webview_runtime as displays
from acceptance_common import require
import transition_contract as native
import ownership_contract as ownership
import geometry_contract as geometry

MAX_BYTES=32*1024*1024


def process_identity(pid):
    raw=shared.capture(['ps','-p',str(pid),'-o','pid=,lstart=,comm='],check=False).stdout.decode()
    if not raw.strip():return None
    found=re.fullmatch(r'\s*'+str(pid)+r'\s+(.+?)\s+(/[^\n]+)\n?',raw)
    require(found is not None,'actual process launch identity unavailable')
    return dict(pid=pid,start=found[1],executable=str(Path(found[2]).resolve()))


def consumed(rows,before):
    kinds={'human_callback','native_input','human_scroll_begin','human_scroll_end','native_background',
           'native_model','native_appear','native_disappear','transition_begin','transition_complete'}
    return [row for row in rows if row['sequence']>before['sequence'] and row['kind'] in kinds]


def tap(phase,target,screen,after):
    return dict(phase=phase,target=target,kind='navigate',screen=screen,after_screen=after)


class Collector(shared_capture.Collector):
    transition_oracle = native
    select_display = staticmethod(displays.active_display)
    read_display = staticmethod(transport.display)
    def __init__(self,**kwargs):
        super().__init__(**kwargs);self.transition_results={};self.adaptive_results=[];self.executable=None;self.process_started=None
    def live(self,deadline):
        require(time.time()<min(deadline,self.deadline),'original collector deadline expired')
        require(self.process_live(),'original task process replaced or ended')
    def process_live(self):
        if self.process_started is not None:return process_identity(self.pid)==self.process_started
        return bool(shared.process(self.pid)) and (self.executable is None or Path(shared.process(self.pid)).resolve()==self.executable)
    def pending(self):
        path=self.documents/'events.jsonl'
        require(not path.exists() or path.stat().st_size<=MAX_BYTES,'native evidence bound exceeded')
        return super().pending()
    def prompt_fields(self):
        return {}
    def prompt(self,phase,instruction,folder,deadline,before):
        actual=self.read_display(self.device,folder,'display',deadline)
        active=self.select_display(json.loads(actual),self.device)
        human_fold.screen(before,self.binding,active,'27.1',self.evidence)
        shared.command(['xcrun','devicectl','device','capture','screenshot','--device',self.device,
            '--display-unique-id',active['uniqueId'],'--destination',str(folder/'ready.png')],folder,'screenshot',
            deadline=min(deadline,time.time()+30))
        require(not consumed(self.pending(),before),'transition readiness consumed before prompt')
        self.live(deadline)
        prompt=dict(kind='HUMAN_INPUT_REQUEST',phase=phase,run_id=self.run,request_id=before['payload']['request_id'],
            instruction=instruction,device=self.device,issued_at=time.time(),deadline=deadline,
            screenshot=str(folder/'ready.png'),screenshot_sha256=shared.sha(folder/'ready.png'),native_before_sequence=before['sequence'],**self.prompt_fields())
        shared.save(folder/'prompt.json',prompt,exclusive=True)
        print(json.dumps(dict(human_input=prompt)),flush=True)
        return actual
    def interactive(self,phase):
        cancelled=phase.endswith('.cancel');pop=phase.startswith('pop.')
        screen='detail' if pop else 'sheet';after_screen=screen if cancelled else 'home' if pop else 'detail'
        deadline=min(self.deadline,time.time()+self.budget['human_step_seconds'])
        before,folder=self.snapshot(phase+'.before',deadline)
        journey.visible(before,screen,self.binding);ownership.owners(self.evidence,before)
        instruction=('Begin a slow swipe from the left screen edge' if pop else 'Begin pulling the sheet down from its top')
        instruction+=('; move it a short distance, then return to the starting position and release to cancel.' if cancelled else
                      '; continue across/down far enough and release to complete it.')
        instruction+=' Perform one gesture, then wait. Do not use a Back or Dismiss button.'
        actual=self.prompt(phase,instruction,folder,deadline,before)
        def finished():
            rows=self.pending();values=[r for r in rows if r['kind']=='transition_complete' and r['payload']['request_id']==before['payload']['request_id']]
            require(len(values)<=1,'duplicate native completion')
            return values[0] if values else None
        self.wait(finished,deadline)
        print(json.dumps(dict(human_status=dict(instruction='Native completion observed. Capturing its owner; wait.'))),flush=True)
        require(time.time()+self.budget['settle_seconds']<deadline,'native completion left no evidence reserve')
        time.sleep(self.budget['settle_seconds'])
        after,after_folder=self.snapshot(phase+'.effect',deadline)
        journey.visible(after,after_screen,self.binding)
        require(not any(r['kind'] in ['human_callback','native_input','native_background'] for r in self.evidence
            if before['sequence']<r['sequence']<after['sequence']),'unplanned input inside interactive boundary')
        result=self.transition_oracle.transition(self.evidence,before,after,cancelled=cancelled,binding=self.binding)
        front=geometry.visible_transition(before,after,self.binding,result)
        changed=self.read_display(self.device,after_folder,'display',deadline)
        before_display=self.select_display(json.loads(actual),self.device);after_display=self.select_display(json.loads(changed),self.device)
        require(displays.display_signature(before_display)==displays.display_signature(after_display),'display changed during navigation gesture')
        human_fold.screen(after,self.binding,after_display,'27.1',self.evidence)
        owner=ownership.transition_owners(self.evidence,before,after,result)
        record=dict(native=result,foremost=front,ownership=owner,phase=phase,deadline=deadline,finished_at=time.time(),
            before_events_sha256=shared.sha(folder/'events.jsonl'),after_events_sha256=shared.sha(after_folder/'events.jsonl'))
        self.live(deadline);shared.save(after_folder/'transition-result.json',record,exclusive=True)
        self.transition_results[phase]=record
        self.receipts.append(dict(run_id=self.run,phase=phase+'.effect',timestamp=after['timestamp'],payload=result))
    def stack(self):
        self.ensure_root('stack','initial')
        self.perform(tap('setup.detail','home.next','home','detail'))
        self.interactive('pop.finish')
        self.perform(tap('setup.detail-again','home.next','home','detail'))
        self.interactive('pop.cancel')
        self.perform(tap('setup.sheet','detail.sheet','detail','sheet'))
        self.interactive('dismiss.finish')
        self.perform(tap('setup.sheet-again','detail.sheet','detail','sheet'))
        self.interactive('dismiss.cancel')
        self.perform(tap('return.dismiss','sheet.close','sheet','detail'))
        self.perform(tap('return.home','detail.back','detail','home'))
        return self.home()
    def fold_step(self,label,pose):
        require(pose in ['open','close','reopen'],'unadmitted fold pose')
        deadline=min(self.deadline,time.time()+self.budget['human_fold_seconds'])
        input_deadline=deadline-self.budget['fold_input_reserve_seconds']
        before,folder=self.snapshot(label+'.before',deadline);before_rows=list(self.evidence)
        actual=self.prompt(label,'Set the selected Duo to '+('Closed' if pose=='close' else 'Open')+' once, then wait.',folder,input_deadline,before)
        active=displays.active_display(json.loads(actual),self.device);index=0;changed=None
        while time.time()+30<input_deadline:
            self.live(input_deadline);time.sleep(1)
            observed_raw=transport.display(self.device,folder,'observed-'+str(index),input_deadline);index+=1
            observed=displays.active_display(json.loads(observed_raw),self.device)
            if observed['uniqueId']!=active['uniqueId']:
                changed=observed_raw;break
        require(changed is not None,'human input did not change the actual display before its deadline')
        print(json.dumps(dict(human_status=dict(instruction='Display change observed. Capturing selection and ownership; wait.'))),flush=True)
        require(time.time()+self.budget['settle_seconds']<deadline,'fold left no observation reserve')
        time.sleep(self.budget['settle_seconds'])
        after,after_folder=self.snapshot(label+'.effect',deadline)
        mode=human_fold.transition(before,after,self.binding,actual,changed,device=self.device,sdk='27.1',phase=pose,
                                   before_rows=before_rows,after_rows=self.evidence)
        (after_folder/'actual-display.json').write_bytes(changed)
        result=dict(state='ACTUAL_FOLD_QUALIFIED',phase=label,pose=pose,mode=mode,deadline=deadline,input_deadline=input_deadline,
                    finished_at=time.time(),actual_display_sha256=shared.sha(after_folder/'actual-display.json'),
                    actual_capture_command=str(folder/('observed-'+str(index-1)+'.json')))
        self.live(deadline);shared.save(after_folder/'fold.json',result,exclusive=True)
        return before,after,dict(result,before_display=json.loads(actual),after_display=json.loads(changed)),after_folder
    def split_duo(self):
        self.ensure_root('split','initial')
        self.perform(tap('setup.detail','sidebar.next','sidebar','detail'))
        original=initial_display=None
        for phase in ['open','close','reopen']:
            before,after,proof,after_folder=self.fold_step(phase,phase)
            if phase=='open':original=before;initial_display=displays.active_display(proof['before_display'],self.device)
            native_result=geometry.adaptive(before,after,self.binding,self.framework)
            before_owners=ownership.owners(self.evidence,before);after_owners=ownership.owners(self.evidence,after)
            value=dict(phase=phase,fold=proof,native=native_result,ownership=ownership.adaptive_owners(before_owners,after_owners))
            shared.save(after_folder/'selection-ownership.json',value,exclusive=True);self.adaptive_results.append(value)
        before,after,proof,after_folder=self.fold_step('restore.close','close')
        geometry.adaptive(before,after,self.binding,self.framework)
        restored=geometry.restored(original,after,self.binding,self.framework,initial_display,displays.active_display(proof['after_display'],self.device))
        shared.save(self.output/'restored-pose.json',dict(restored,proof=proof),exclusive=True)
        return self.home()
