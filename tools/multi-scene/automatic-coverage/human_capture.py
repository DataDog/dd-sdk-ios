"""Human prompts and passive evidence capture inside the existing acceptance lane.

This module never sends native input. A reviewed runtime admission owns launch,
fixed cell/stage deadlines, source/build checks and task-only cleanup.
"""
import hashlib
import json
from pathlib import Path
import time
import uuid
import human_contract as oracle
import human_journey as journey
import human_fold
import human_build
from acceptance_common import require
import s2_hosting_workflow as shared
import s2_webview_driver as transport
import s2_webview_runtime as displays
import local_event_collection
import human_release
import human_home


def pending_rows(raw,run):
    """Read complete lines only to detect an effect; this is never acceptance."""
    raw=raw[:raw.rfind(b'\n')+1]
    result=[json.loads(line) for line in raw.splitlines()]
    require(all(r.get('run_id')==run for r in result),'foreign/restored native run')
    require([r.get('sequence') for r in result]==list(range(1,len(result)+1)),'missing/reordered pending native sequence')
    require(not any(r['kind']=='human_failure' for r in result),'native observer rejected request')
    return result


def initial_ready(rows,framework):
    launches=[r for r in rows if r['kind']=='launch']
    if not launches:return None
    launch=oracle.one(launches,'initial launch')
    require(launch['payload'].get('framework')==framework,'wrong initial fixture framework')
    require(not any(r['kind']=='native_background' for r in rows),'background occurred before initial readiness')
    appearances=[r for r in rows if r['kind']=='native_appear']
    geometry=[r for r in rows if r['kind']=='geometry']
    if not appearances or not geometry:return None
    scenes=geometry[-1]['payload']['scenes']
    require(len(scenes)<=1,'multiple initial native scenes')
    if not scenes or scenes[0]['activation']!=0 or not scenes[0]['windows']:return None
    require(all(w['width']>0 and w['height']>0 for w in scenes[0]['windows']),'invalid initial geometry')
    return geometry[-1]


class Collector:
    def __init__(self, *, documents, output, run, device, pid, framework, deadline, budget, local_process=True):
        self.documents=Path(documents);self.output=Path(output);self.run=run
        self.device=device;self.pid=pid;self.framework=framework;self.deadline=deadline;self.budget=budget
        self.phases=set();self.binding=None;self.receipts=[];self.evidence=[];self.prompt_issued=False
        self.process_identity=human_release.process_identity(pid) if local_process else None
        require(self.output.is_dir() and self.documents.is_dir(),'collector directories not preflighted')
        require(set(budget)>={'human_step_seconds','snapshot_seconds','settle_seconds'},'collector limits absent')
    def live(self,deadline):
        require(time.time()<min(deadline,self.deadline),'original collector deadline expired')
        require(bool(shared.process(self.pid)),'original app process ended')
        require(self.process_identity and human_release.process_identity(self.pid)==self.process_identity,'original app process replaced')
    def pending_for_cleanup(self):
        raw=(self.documents/'events.jsonl').read_bytes()
        rows=[json.loads(line) for line in raw[:raw.rfind(b'\n')+1].splitlines()]
        require(all(r['run_id']==self.run for r in rows),'foreign cleanup run')
        return rows
    def cleanup_idle(self,folder,identity,deadline):
        return human_release.capture_idle(self,folder,identity,deadline)
    def wait(self,condition,deadline):
        while True:
            self.live(deadline)
            value=condition()
            if value is not None:return value
            time.sleep(.1)
    def pending(self):
        path=self.documents/'events.jsonl'
        return pending_rows(path.read_bytes(),self.run) if path.exists() else []
    def snapshot(self,phase,deadline):
        require(phase not in self.phases,'consumed snapshot phase');self.phases.add(phase)
        self.live(deadline);folder=self.output/phase;folder.mkdir()
        if self.binding is None:
            self.wait(lambda:initial_ready(self.pending(),self.framework),min(deadline,time.time()+self.budget['snapshot_seconds']))
        request={'schema_version':1,'run_id':self.run,'request_id':str(uuid.uuid4()),'phase':phase}
        shared.save(folder/'request.json',request,exclusive=True);raw=(folder/'request.json').read_bytes()
        # This same atomic publisher and its filesystem preflight serve other S2 families.
        shared.save(self.documents/'human-snapshot-request.json',request)
        path=self.documents/('events-checkpoint-'+request['request_id']+'.json')
        self.wait(lambda:path if path.exists() else None,min(deadline,time.time()+self.budget['snapshot_seconds']))
        committed=path.read_bytes();receipt=json.loads(committed);event_bytes=(self.documents/'events.jsonl').read_bytes()
        rows=oracle.checkpoint(event_bytes,receipt,self.run,request['request_id'])
        prefix=event_bytes[:receipt['byte_count']]
        (folder/'events.jsonl').write_bytes(prefix);(folder/'writer-checkpoint.json').write_bytes(committed)
        snapshot,binding=oracle.snapshot(rows,raw,self.run)
        require(self.binding is None or self.binding==binding,'fixture source binding replaced');self.binding=binding
        self.evidence=rows;self.live(deadline)
        shared.save(folder/'capture.json',{'state':'DURABLE_NATIVE_SNAPSHOT','request_id':request['request_id'],
            'sequence':snapshot['sequence'],'captured_at':time.time(),'deadline':deadline,
            'events_sha256':shared.sha(folder/'events.jsonl'),'writer_sha256':shared.sha(folder/'writer-checkpoint.json')},exclusive=True)
        return snapshot,folder
    def prompt(self,phase,instruction,folder,deadline,before):
        actual=transport.display(self.device,folder,'display',deadline)
        active=displays.active_display(json.loads(actual),self.device)
        shared.command(['xcrun','devicectl','device','capture','screenshot','--device',self.device,
            '--display-unique-id',active['uniqueId'],'--destination',str(folder/'ready.png')],folder,'screenshot',
            deadline=min(deadline,time.time()+30))
        # Input during evidence preparation cannot be credited to a later prompt.
        intervening=[r for r in self.pending() if r['sequence']>before['sequence'] and
            r['kind'] in ['human_callback','native_input','human_scroll_begin','human_scroll_end','native_background']]
        require(not intervening,'readiness consumed before human prompt')
        self.live(deadline)
        prompt={'kind':'HUMAN_INPUT_REQUEST','phase':phase,'run_id':self.run,'request_id':before['payload']['request_id'],
            'instruction':instruction,'device':self.device,'issued_at':time.time(),'deadline':deadline,
            'screenshot':str(folder/'ready.png'),'screenshot_sha256':shared.sha(folder/'ready.png'),
            'native_before_sequence':before['sequence']}
        shared.save(folder/'prompt.json',prompt,exclusive=True)
        self.prompt_issued=True
        print(json.dumps({'human_input':prompt}),flush=True)
        return actual
    def ensure_root(self,layout,prefix):
        deadline=min(self.deadline,time.time()+self.budget['human_step_seconds'])
        initial,_=self.snapshot(prefix+'.root.readiness',deadline)
        root='sidebar' if layout=='split' else 'home'
        try:
            journey.visible(initial,root,self.binding);return
        except ValueError:
            require(self.framework=='UIKit' and layout=='split','expected root is not observable')
        journey.visible(initial,'empty',self.binding)
        before,folder=self.snapshot(prefix+'.revealSidebar.before',deadline)
        actual=self.prompt(prefix+'.revealSidebar','Use the visible native Back control to show Sidebar once.',folder,deadline,before)
        def appeared():
            values=[r for r in self.pending() if r['sequence']>before['sequence'] and r['kind']=='native_appear' and r['payload']['screen']=='sidebar']
            return values if values else None
        self.wait(appeared,deadline)
        require(time.time()+self.budget['settle_seconds']<deadline,'sidebar left no observation interval')
        time.sleep(self.budget['settle_seconds'])
        after,after_folder=self.snapshot(prefix+'.revealSidebar.effect',deadline)
        selected=journey.interval(self.evidence,before,after)
        require(not any(r['kind'] in ['human_callback','native_input'] for r in selected),'unexpected fixture action while revealing Sidebar')
        native=oracle.one([r for r in selected if r['kind']=='native_appear' and r['payload']['screen']=='sidebar'],'native Sidebar appearance')
        timed=oracle.one([r for r in selected if r['kind']=='human_appearance' and r['payload']['screen']=='sidebar'],'timed Sidebar appearance')
        require(timed['payload']['request_id']==before['payload']['request_id'] and timed['sequence']<native['sequence']
                and before['payload']['uptime_ns']<=timed['payload']['uptime_ns']<=after['payload']['uptime_ns'],'stale Sidebar effect')
        journey.visible(after,'sidebar',self.binding)
        observed=transport.display(self.device,after_folder,'display',deadline)
        require(displays.display_signature(displays.active_display(json.loads(actual),self.device))==
                displays.display_signature(displays.active_display(json.loads(observed),self.device)),'fold cannot qualify a native Back effect')
        self.receipts += [{'run_id':self.run,'phase':prefix+'.revealSidebar.before','timestamp':before['timestamp'],'payload':{}},
                          {'run_id':self.run,'phase':prefix+'.revealSidebar.effect','timestamp':after['timestamp'],'payload':{'native_sequence':native['sequence']}}]
    def perform(self,step):
        deadline=min(self.deadline,time.time()+self.budget['human_step_seconds']);phase=step['phase']
        before,folder=self.snapshot(phase+'.before',deadline)
        journey.visible(before,step['screen'],self.binding);oracle.target(before,step['target'],self.binding)
        if step['kind'] in ['tap','toggle']:journey.counter(before,step['screen'],self.binding,self.framework)
        self.receipts.append({'run_id':self.run,'phase':phase+'.before','timestamp':before['timestamp'],'payload':{'target':step['target']}})
        control=step['target'].split('.')[-1]
        label={'tap':'Tap','toggle':'Enable','scroll':'the rows','next':'Open detail','sheet':'Present sheet','back':'Return home','close':'Dismiss sheet'}[control]
        instruction='On '+step['screen']+', '+('scroll ' if control=='scroll' else 'tap ')+label+' once, then wait.'
        self.prompt(phase,instruction,folder,deadline,before)
        def observed():
            selected=[r for r in self.pending() if r['sequence']>before['sequence']]
            if step['kind']=='scroll':ready=[r for r in selected if r['kind']=='human_scroll_end']
            elif self.framework=='SwiftUI' and step['target'].endswith('.next'):
                ready=[r for r in selected if r['kind']=='native_appear' and r['payload']['screen']==step['after_screen']]
            else:ready=[r for r in selected if r['kind']=='native_input']
            return ready if ready else None
        self.wait(observed,deadline)
        print(json.dumps({"human_status":{"instruction":"Input observed. Capturing its effect; wait for the next ready step."}}),flush=True)
        require(time.time()+self.budget['settle_seconds']<deadline,'effect left no settled observation interval')
        time.sleep(self.budget['settle_seconds'])
        after,after_folder=self.snapshot(phase+'.effect',deadline)
        effect=journey.effect(self.evidence,before,after,step,self.binding,self.framework)
        self.live(deadline)
        self.receipts.append({'run_id':self.run,'phase':phase+'.effect','timestamp':after['timestamp'],'payload':effect})
        shared.save(after_folder/'effect.json',{'state':'NATIVE_EFFECT_QUALIFIED','phase':phase,'effect':effect,
            'before_events_sha256':shared.sha(folder/'events.jsonl'),'after_events_sha256':shared.sha(after_folder/'events.jsonl'),
            'finished_at':time.time(),'deadline':deadline},exclusive=True)
        return effect
    def fold(self,phase,sdk):
        deadline=min(self.deadline,time.time()+self.budget['human_fold_seconds'])
        input_deadline=deadline-self.budget['fold_input_reserve_seconds']
        before,folder=self.snapshot(phase+'.before',deadline);before_rows=list(self.evidence)
        self.receipts.append({'run_id':self.run,'phase':'await-'+phase,'timestamp':before['timestamp'],'payload':{}})
        before_display=self.prompt(phase,'Set the selected Duo to '+('Closed' if phase=='close' else 'Open')+' once.',
                                   folder,input_deadline,before)
        active=displays.active_display(json.loads(before_display),self.device)
        index=0;after_display=None
        while time.time()+30<input_deadline:
            self.live(input_deadline);time.sleep(1)
            current=transport.display(self.device,folder,'observed-'+str(index),input_deadline);index+=1
            observed=displays.active_display(json.loads(current),self.device)
            if observed['uniqueId']!=active['uniqueId']:
                after_display=current;break
        require(after_display is not None,'human fold did not change the actual display in time')
        print(json.dumps({'human_status':{'instruction':'Display transition observed. Capturing ownership evidence; wait.'}}),flush=True)
        require(time.time()+self.budget['settle_seconds']<deadline,'fold left no native observation reserve')
        time.sleep(self.budget['settle_seconds'])
        after,after_folder=self.snapshot(phase+'.effect',deadline)
        mode=human_fold.transition(before,after,self.binding,before_display,after_display,device=self.device,
            sdk=sdk,phase=phase,before_rows=before_rows,after_rows=self.evidence)
        # Retain the response that established this transition, never an earlier
        # observation with a matching signature.
        (after_folder/'actual-display.json').write_bytes(after_display)
        proof={'state':'FOLD_QUALIFIED','run_id':self.run,'phase':phase,'mode':mode,'deadline':deadline,
            'input_deadline':input_deadline,'finished_at':time.time(),'before_sequence':before['sequence'],
            'after_sequence':after['sequence'],'actual_display_sha256':shared.sha(after_folder/'actual-display.json'),
            'actual_capture_command':str(folder/('observed-'+str(index-1)+'.json'))}
        self.live(deadline);shared.save(after_folder/'fold.json',proof,exclusive=True)
        self.receipts.append({'run_id':self.run,'phase':'received-'+phase,'timestamp':after['timestamp'],'payload':proof})
        return proof
    def home(self):
        deadline=min(self.deadline,time.time()+self.budget['human_step_seconds'])
        before,folder=self.snapshot('background.before',deadline)
        self.receipts.append({'run_id':self.run,'phase':'background.before','timestamp':before['timestamp'],'payload':{}})
        self.prompt('background','Use Home once to background this app; do not terminate it.',folder,deadline,before)
        def background():
            values=[r for r in self.pending() if r['kind']=='native_background' and r['sequence']>before['sequence']]
            if not values:return None
            require(len(values)==1,'duplicate native background');return values[0]
        event=self.wait(background,deadline)
        print(json.dumps({'human_status':{'instruction':'Background observed. Capturing final events and cleanup; wait.'}}),flush=True)
        identifier='background-'+str(event['sequence']);path=self.documents/('events-checkpoint-'+identifier+'.json')
        human_home.await_ready(self,folder,identifier,deadline)
        raw=(self.documents/'events.jsonl').read_bytes();checkpoint=path.read_bytes()
        rows=oracle.checkpoint(raw,json.loads(checkpoint),self.run,identifier)
        require(event in rows and len([r for r in rows if r['kind']=='native_background'])==1,'background writer receipt is stale')
        geometry=[r for r in rows if r['kind']=='geometry' and r['sequence']>event['sequence']]
        require(geometry and len(geometry[-1]['payload']['scenes'])==1
                and geometry[-1]['payload']['scenes'][0]['id']==self.binding['scene']
                and geometry[-1]['payload']['scenes'][0]['activation']!=0,'actual scene did not leave foreground')
        (folder/'background-events.jsonl').write_bytes(raw[:json.loads(checkpoint)['byte_count']])
        (folder/'background-checkpoint.json').write_bytes(checkpoint)
        prefix=raw[:json.loads(checkpoint)['byte_count']]
        collection_deadline=min(self.deadline,time.time()+self.budget.get('event_collection_seconds',120))
        def complete():
            observed=(self.documents/'events.jsonl').read_bytes()
            result=local_event_collection.terminal_rows(observed,run_id=self.run,prefix=prefix)
            if result is not None:
                (folder/'background-collected-events.jsonl').write_bytes(observed)
            return result
        self.evidence=self.wait(complete,collection_deadline);self.live(collection_deadline)
        proof_path=self.documents/('home-input-idle-'+before['payload']['request_id']+'.json')
        self.wait(lambda:True if proof_path.exists() else None,collection_deadline)
        shared.save(folder/'home-idle-proof.json',human_release.home_idle(self),exclusive=True)
        self.evidence=human_home.finish(self,folder,self.evidence,collection_deadline)
        shared.save(folder/'collection.json',{'state':'LOCAL_HOME_INVENTORY_COLLECTED',
            'prefix_sha256':hashlib.sha256(prefix).hexdigest(),'sequence':self.evidence[-1]['sequence'],
            'deadline':collection_deadline,'finished_at':time.time()},exclusive=True)
        self.receipts.append({'run_id':self.run,'phase':'background.effect','timestamp':event['timestamp'],'payload':{'native_sequence':event['sequence']}})
        self.receipts.append({'run_id':self.run,'phase':'complete','timestamp':event['timestamp'],'payload':{'proof':'LOCAL_HOME_INVENTORY_COLLECTED'}})
        shared.save(self.output/'receipts.json',self.receipts,exclusive=True)
        return self.evidence
