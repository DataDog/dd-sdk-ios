"""Human physical input; unchanged public transition and mapper oracles."""
import hashlib
import json
from pathlib import Path
import time
import uuid
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'app-acceptance'))
import driver
import physical_io as io
import physical_release
import physical_transition
import physical_background
import physical_cleanup
import local_event_collection
from capture_io import atomic, encoded

shared=io.shared
require=io.require


def interactive_progress(rows, before, *, expected_screen):
    """Report actual appearance separately; only a callback advances collection."""
    selected = [row for row in rows if row['sequence'] > before['sequence'] and
                row['payload'].get('request_id') == before['payload']['request_id']]
    completed = [row for row in selected if row['kind'] == 'transition_complete']
    require(len(completed) <= 1, 'duplicate physical completion')
    appeared = any(row['kind'] == 'human_appearance' and row['payload'].get('screen') == expected_screen
                   for row in selected)
    return (completed[0] if completed else None), appeared


class Collector(driver.Collector):
    def __init__(self,*,remote,bundle,require_finalization=False,**kwargs):
        super().__init__(device=remote.identifier,local_process=False,**kwargs)
        self.remote=remote;self.bundle=bundle;self.downloads=self.output.parent/'downloads';self.downloads.mkdir()
        self.transfer_sequence=0;self.last_process=None;self.process_checked=0;self.process_path=None
        require(type(require_finalization) is bool, 'invalid physical finalization option')
        self.require_finalization=require_finalization
        self.prompt_issued=False
    def fresh(self,label):
        self.transfer_sequence+=1
        return self.downloads/(str(self.transfer_sequence).zfill(5)+'-'+label)
    def process_live(self):
        rows=self.remote.processes('live-process',self.deadline)
        values=[r for r in rows if r.get('processIdentifier')==self.pid]
        if len(values)!=1:return False
        path=values[0].get('executable')
        require(isinstance(path,str) and path.endswith('/'+self.framework+'Transitions.app/'+self.framework+'Transitions'),
                'physical PID executable changed')
        if self.process_path is None:self.process_path=path
        return path==self.process_path
    def live(self,deadline):
        require(time.time()<min(deadline,self.deadline),'physical collector deadline expired')
        if time.time()-self.process_checked>=2:
            require(self.process_live(),'original physical process ended or changed');self.process_checked=time.time()
    def download(self,name,deadline,*,optional=False):
        for attempt in range(2):
            require(time.time()<deadline,'physical read deadline expired')
            destination=self.fresh(Path(name).name)
            raw,receipt=self.remote.pull(self.bundle,'Documents/'+name,destination,'read-'+Path(name).name,deadline,check=False)
            require(time.time()<deadline,'physical read returned after deadline')
            if receipt['returncode']==0:break
            info=(raw or {}).get('info',{});args=info.get('arguments',[])
            transient=(raw or {}).get('errorSignature')=='(com.apple.dt.CoreDeviceError 7000 (NSPOSIXErrorDomain 60))'
            bound=(info.get('outcome')=='failed' and info.get('commandType')=='devicectl.device.copy.from' and
                   isinstance(args,list) and args.count('--device')==1 and
                   args.index('--device')+1<len(args) and args[args.index('--device')+1]==self.device)
            repeat=attempt==0 and transient and bound and time.time()+1<deadline
            atomic(destination.with_suffix('.failed-read.json'),encoded(dict(response=raw,receipt=receipt,
                repeated_operation='read-only copy once' if repeat else None,deadline=deadline)))
            if not repeat:break
        if receipt['returncode']!=0:
            require(optional,'required native file unavailable');return None
        io.returned(raw,self.device,'devicectl.device.copy.from')
        require(destination.is_file() and not destination.is_symlink() and destination.stat().st_size<=driver.MAX_BYTES,
                'missing/oversized physical evidence')
        data=destination.read_bytes();atomic(self.documents/name,data,exclusive=False)
        return data
    def wait(self,condition,deadline):
        while True:
            self.live(deadline);value=condition();self.live(deadline)
            if value is not None:return value
            time.sleep(.5)
    def pending(self):
        data=self.download('events.jsonl',self.deadline,optional=not (self.documents/'events.jsonl').exists())
        return driver.shared_capture.pending_rows(data,self.run) if data is not None else []
    def snapshot(self,phase,deadline):
        require(phase not in self.phases,'consumed physical snapshot phase');self.phases.add(phase);self.live(deadline)
        folder=self.output/phase;folder.mkdir();limit=min(deadline,time.time()+self.budget['snapshot_seconds'])
        if self.binding is None:self.wait(lambda:driver.shared_capture.initial_ready(self.pending(),self.framework),limit)
        request=dict(schema_version=1,run_id=self.run,request_id=str(uuid.uuid4()),phase=phase)
        raw=encoded(request);atomic(folder/'request.json',raw);fingerprint=hashlib.sha256(raw).hexdigest()
        self.remote.push(self.bundle,folder/'request.json','Documents/snapshot-'+fingerprint+'.json','snapshot-payload',limit)
        marker=folder/'marker';atomic(marker,fingerprint.encode())
        self.remote.push(self.bundle,marker,'Documents/human-snapshot-request.json','snapshot-publish',limit)
        name='events-checkpoint-'+request['request_id']+'.json'
        committed=self.wait(lambda:self.download(name,limit,optional=True),limit)
        data=self.download('events.jsonl',limit);receipt=json.loads(committed)
        rows=driver.capture_contract.checkpoint(data,receipt,self.run,request['request_id'])
        atomic(folder/'events.jsonl',data[:receipt['byte_count']]);atomic(folder/'writer-checkpoint.json',committed)
        snapshot,binding=driver.capture_contract.snapshot(rows,raw,self.run)
        require(self.binding is None or self.binding==binding,'physical fixture binding changed')
        self.binding=binding;self.evidence=rows;self.live(limit)
        atomic(folder/'capture.json',encoded(dict(state='DURABLE_PHYSICAL_SNAPSHOT',request_id=request['request_id'],
            sequence=snapshot['sequence'],captured_at=time.time(),deadline=limit,events_sha256=shared.sha(folder/'events.jsonl'))))
        return snapshot,folder
    def display(self,folder,label,deadline):
        raw,_=self.remote.command(['device','info','displays'],label,deadline)
        atomic(folder/(label+'.json'),encoded(raw));return io.display(raw,self.device)
    def screen(self,before,display):
        scene,window=driver.capture_contract.topology(before['payload']['topology'],self.binding)
        scale=scene['screen_scale'];pixels=display['bounds'][1]
        require(scale==display['pointScale'] and [n*scale for n in scene['screen_bounds'][2:]]==pixels and
                [n*scale for n in window['bounds'][2:]]==pixels,'physical stack app must fill the measured display')
    def prompt(self,phase,instruction,folder,deadline,before):
        actual=self.display(folder,'display',deadline);self.screen(before,actual)
        self.remote.command(['device','capture','screenshot','--destination',str(folder/'ready.png')],'screenshot',deadline)
        require((folder/'ready.png').is_file(),'physical screenshot missing')
        require(not driver.consumed(self.pending(),before),'physical readiness consumed before prompt')
        self.live(deadline)
        prompt=dict(kind='HUMAN_INPUT_REQUEST',phase=phase,run_id=self.run,request_id=before['payload']['request_id'],
            instruction=instruction,device=self.device,issued_at=time.time(),deadline=deadline,
            screenshot=str(folder/'ready.png'),screenshot_sha256=shared.sha(folder/'ready.png'),native_before_sequence=before['sequence'])
        atomic(folder/'prompt.json',encoded(prompt));self.prompt_issued=True
        print(json.dumps(dict(human_input=prompt)),flush=True)
        return actual
    def cleanup_idle(self,folder,identity,deadline):
        prepared=physical_cleanup.prepare(self,folder,identity,deadline)
        limit=prepared["deadline"]
        request=dict(schema_version=1,run_id=self.run,request_id=str(uuid.uuid4()),phase='cleanup.idle')
        raw=encoded(request);atomic(folder/'native-request.json',raw);fingerprint=hashlib.sha256(raw).hexdigest()
        self.remote.push(self.bundle,folder/'native-request.json','Documents/snapshot-'+fingerprint+'.json','cleanup-idle-payload',limit)
        atomic(folder/'native-marker',fingerprint.encode())
        self.remote.push(self.bundle,folder/'native-marker','Documents/human-snapshot-request.json','cleanup-idle-publish',limit)
        name='events-checkpoint-'+request['request_id']+'.json';committed=None
        while committed is None:
            require(time.time()<limit,'native cleanup idle checkpoint unavailable; defer teardown')
            committed=self.download(name,limit,optional=True)
            if committed is None:time.sleep(.2)
        data=self.download('events.jsonl',limit);checkpoint=json.loads(committed)
        atomic(folder/'native-checkpoint.json',committed);atomic(folder/'native-events.jsonl',data)
        proof=physical_release.native_idle(data,checkpoint,raw,identity,self.binding)
        require(time.time()<limit,'late native cleanup idle proof; defer teardown')
        physical_cleanup.finish(self,folder,prepared,data,proof)
        return proof
    def interactive(self,phase):
        cancelled=phase.endswith('.cancel');pop=phase.startswith('pop.')
        screen='detail' if pop else 'sheet';after_screen=screen if cancelled else 'home' if pop else 'detail'
        deadline=min(self.deadline,time.time()+self.budget['human_step_seconds'])
        before,folder=self.snapshot(phase+'.before',deadline)
        driver.journey.visible(before,screen,self.binding);driver.ownership.owners(self.evidence,before)
        instruction=('Begin a slow swipe from the left edge of the app' if pop else 'Begin pulling the sheet down from its top')
        instruction+=('; move a short distance, then return to the starting position and release to cancel.' if cancelled else
                      '; continue across/down far enough and release to complete it.')
        instruction+=' Perform one gesture, then wait. Do not use Back or Dismiss.'
        actual=self.prompt(phase,instruction,folder,deadline,before)
        progress_reported = False
        def finished():
            nonlocal progress_reported
            completed, appeared = interactive_progress(self.pending(), before, expected_screen=after_screen)
            if appeared and completed is None and not progress_reported:
                print(json.dumps(dict(human_status=dict(instruction=
                    'View appearance captured. Waiting for transition callback evidence; do not repeat the gesture.'))), flush=True)
                progress_reported = True
            return completed
        completion=self.wait(finished,deadline)
        print(json.dumps(dict(human_status=dict(instruction='Gesture observed. Wait while its ownership is captured.'))),flush=True)
        # The native completion is already retained. Mapper serialization can
        # arrive later; no additional gesture or fixed settling delay is needed.
        deadline=min(self.deadline,time.time()+self.budget.get('event_collection_seconds',120))
        def callback_ready():
            rows=self.pending()
            values=[r for r in rows if r['kind']=='rum' and r['payload'].get('type')=='action'
                    and r['payload'].get('context',{}).get('transition_callback')==completion['payload']['callback_id']]
            require(len(values)<=1,'duplicate mapped callback action')
            if not values:return None
            return driver.ownership.native.callback_work(rows,dict(callback_id=completion['payload']['callback_id'],
                completion_sequence=completion['sequence']))
        self.wait(callback_ready,deadline)
        after,after_folder=self.snapshot(phase+'.effect',deadline);driver.journey.visible(after,after_screen,self.binding)
        require(not any(r['kind'] in ['human_callback','native_input','native_background'] for r in self.evidence
            if before['sequence']<r['sequence']<after['sequence']),'unplanned input inside interactive boundary')
        result=physical_transition.transition(self.evidence,before,after,cancelled=cancelled,binding=self.binding)
        front=driver.geometry.visible_transition(before,after,self.binding,result)
        changed=self.display(after_folder,'display',deadline);require(actual==changed,'physical display changed during gesture');self.screen(after,changed)
        owner=driver.ownership.transition_owners(self.evidence,before,after,result)
        record=dict(native=result,foremost=front,ownership=owner,phase=phase,deadline=deadline,finished_at=time.time(),
            before_events_sha256=shared.sha(folder/'events.jsonl'),after_events_sha256=shared.sha(after_folder/'events.jsonl'))
        self.live(deadline);atomic(after_folder/'transition-result.json',encoded(record));self.transition_results[phase]=record
    def home(self):
        deadline=min(self.deadline,time.time()+self.budget['human_step_seconds'])
        before,folder=self.snapshot('background.before',deadline)
        self.prompt('background','Swipe up from the bottom once to go Home; do not terminate the app.',folder,deadline,before)
        def background():
            values=[r for r in self.pending() if r['kind']=='native_background' and r['sequence']>before['sequence']]
            require(len(values)<=1,'duplicate physical background');return values[0] if values else None
        event=self.wait(background,deadline);print(json.dumps(dict(human_status=dict(instruction='Home observed. Wait for telemetry collection and cleanup.'))),flush=True)
        name='events-checkpoint-background-'+str(event['sequence'])+'.json'
        committed=self.wait(lambda:self.download(name,deadline,optional=True),deadline);data=self.download('events.jsonl',deadline)
        receipt=json.loads(committed);rows=driver.capture_contract.checkpoint(data,receipt,self.run,'background-'+str(event['sequence']))
        geometry=[r for r in rows if r['kind']=='geometry' and r['sequence']>event['sequence']]
        require(event in rows and len([r for r in rows if r['kind']=='native_background'])==1 and geometry and
            len(geometry[-1]['payload']['scenes'])==1 and geometry[-1]['payload']['scenes'][0]['id']==self.binding['scene'] and
            geometry[-1]['payload']['scenes'][0]['activation']!=0,'physical scene did not leave foreground')
        atomic(folder/'background-checkpoint.json',committed);atomic(folder/'background-events.jsonl',data[:receipt['byte_count']])
        if self.require_finalization:
            proof_name='background-finalization-background-'+str(event['sequence'])+'.json'
            proof=self.wait(lambda:self.download(proof_name,deadline,optional=True),deadline)
            physical_background.validate_receipt(json.loads(proof),run_id=self.run,pid=self.pid,
                checkpoint='background-'+str(event['sequence']))
            atomic(folder/'finalization-receipt.json',proof)
        # A background writer checkpoint binds native Home, not SDK queue drain.
        # View stops and their counted Actions can be appended after that prefix.
        prefix=data[:receipt['byte_count']]
        collection_deadline=min(self.deadline,time.time()+self.budget.get('event_collection_seconds',120))
        callbacks=[r['native']['callback_id'] for r in self.transition_results.values()]
        def complete():
            observed=self.download('events.jsonl',collection_deadline)
            return local_event_collection.terminal_rows(observed,run_id=self.run,prefix=prefix,callbacks=callbacks)
        self.evidence=self.wait(complete,collection_deadline)
        atomic(folder/'collection.json',encoded(dict(state='LOCAL_HOME_INVENTORY_COLLECTED',
            prefix_sha256=hashlib.sha256(prefix).hexdigest(),sequence=self.evidence[-1]['sequence'],
            deadline=collection_deadline,finished_at=time.time())))
        self.live(collection_deadline);return self.evidence
