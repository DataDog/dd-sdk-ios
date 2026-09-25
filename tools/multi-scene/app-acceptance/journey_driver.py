"""F08 native observations and prompts in the existing single-owner harness.

The operator performs gestures. This module never injects touch, Home or fold
input and never launches a replacement process to satisfy foreground continuity.
"""
import hashlib
import json
from pathlib import Path
import time
import uuid

from capture_io import Collector, atomic, encoded, bounded_read
from capture_contract import prefix, MAX_BYTES, loads, STRICT_COST_POLICY
import journey_contract as contract
import journey_phases as phases
import browser_contract
import journey_readiness
from acceptance_common import require, Rejected
import s2_hosting_workflow as shared
from s2_webview_driver import display
from s2_webview_runtime import active_display, display_signature


def emit(key, value):print(json.dumps({key:value}),flush=True)


def home_observation(tree, folder, deadline):
    if not isinstance(tree,list) or len(tree)!=1 or type(tree[0].get('pid'))!=int:return False
    pid=tree[0]['pid']
    shared.command(['ps','-p',str(pid),'-o','pid=,comm='],folder,'home-process',deadline=min(deadline,time.time()+15))
    values=(folder/'home-process.log').read_text().strip().split(maxsplit=1)
    if len(values)!=2 or not values[0].isdigit():return False
    process=dict(pid=int(values[0]),executable=values[1])
    atomic(folder/'home-process-identity.json',encoded(process))
    return phases.home(tree,process)


class Driver:
    cost_policy = STRICT_COST_POLICY

    def __init__(self, documents, out, identity, expected, device, executable, deadline, initial, selection):
        self.documents,self.out=Path(documents),Path(out)
        self.identity,self.expected,self.device=identity,expected,device
        self.executable,self.deadline,self.initial=Path(executable),deadline,initial
        self.selection=selection
        (self.out/'capture').mkdir();(self.out/'phases').mkdir()
        self.collector=Collector(documents,self.out/'capture',identity,expected['pid'],self.process_live,deadline=deadline,cost_policy=self.cost_policy)
        self.binding=None;self.observations={};self.inputs=[];self.backgrounds=[];self.polls=0;self.last_result=None
        self.monotonic_deadline=time.monotonic()+max(0,deadline-time.time())

    def process_live(self):
        value=shared.process(self.expected['pid'])
        return bool(value) and Path(value).resolve()==self.executable.resolve()

    def live(self, deadline):
        require(time.time()<min(deadline,self.deadline) and time.monotonic()<self.monotonic_deadline
                and self.process_live(), 'original native deadline/process no longer valid')

    def ax(self, label, deadline):
        self.live(deadline)
        path=self.out/'phases'/label;path.mkdir()
        shared.command(['/opt/homebrew/bin/axe','describe-ui','--udid',self.device],path,'ax',deadline=min(deadline,time.time()+15))
        raw=(path/'ax.log').read_bytes()
        return loads(raw),path

    def ready(self, label, screen, *, subdomain=False, authenticated_transition=False, seconds=30, deadline=None):
        end=min(self.deadline,time.time()+seconds,deadline if deadline is not None else self.deadline)
        last_reason=None
        for index in range(600):
            self.live(end);self.polls+=1
            tree,folder=self.ax(label+'-'+str(index),end)
            if screen=='login' and not phases.login(tree,subdomain):time.sleep(.2);continue
            if screen=='detail' and not phases.matches(tree,self.selection['service_label']):time.sleep(.5);continue
            if screen=='list' and not phases.service_list_loaded(tree,self.selection['service_label']):time.sleep(.5);continue
            if screen=='dashboard' and not phases.matches(tree,self.selection['dashboard_label']):time.sleep(.5);continue
            result,row,capture_folder=self.collector.snapshot(label+'-'+str(index),deadline=end)
            try:
                binding=phases.foreground_binding(result['rows'],row,self.binding,authenticated_transition=authenticated_transition)
                raw=display(self.device,folder,'display',end)
                require(display_signature(active_display(loads(raw),self.device))==display_signature(active_display(loads(self.initial),self.device)),
                        'F08 display changed outside any admitted fold')
                owner=contract.snapshot_owner(result['rows'],row,self.expected,binding,raw,self.device,names=phases.NAMES[screen])
                visible=phases.visible(result['rows'],row,screen,binding) if screen in phases.LABELS else None
                if subdomain:phases.back_target(tree)
            except Rejected as error:
                # Readiness observation can settle; no input is repeated. Every
                # actual snapshot and rejection stays under the same short clock.
                last_reason=str(error)
                atomic(folder/'not-ready.json',encoded(dict(reason=last_reason,at=time.time(),deadline=end)))
                time.sleep(.2);continue
            self.binding=binding;self.last_result=result
            value=dict(label=label,screen=screen,snapshot=row,owner=owner,binding=binding,visible=visible,
                       subdomain=subdomain,ax=tree,folder=str(folder),capture_folder=str(capture_folder),captured_at=time.time())
            atomic(folder/'ready.json',encoded(value))
            self.observations[label]=value
            return value
        require(False,'native phase did not settle: '+str(last_reason))

    def dashboard_for_prompt(self, rows, snapshot, owner):
        return browser_contract.attached_dashboard(rows, snapshot, owner)

    def validate_prompt_ready(self, ready, label):
        pass

    def prompt(self, ready, label, instruction, *, seconds=180):
        end=min(self.deadline,time.time()+seconds);self.live(end)
        original_label=ready['label'] if 'label' in ready else label
        for attempt in range(4):
            folder=Path(ready['folder'])
            raw=display(self.device,folder,'prompt-display',end)
            active=active_display(loads(raw),self.device)
            require(display_signature(active)==display_signature(active_display(loads(self.initial),self.device)), 'prompt display changed')
            screenshot=folder/'prompt.png'
            shared.command(['xcrun','devicectl','device','capture','screenshot','--device',self.device,
                            '--display-unique-id',active['uniqueId'],'--destination',str(screenshot)],folder,'screenshot',
                           deadline=min(end,time.time()+30))
            try:
                receipt=self.collector.assert_ready(ready['snapshot'],deadline=end)
                break
            except ValueError as error:
                if str(error)!='native readiness consumed before prompt':raise
                self.live(end)
                observed=bounded_read(self.collector.directory/'events.jsonl',MAX_BYTES)
                atomic(folder/'pending-observations.jsonl',observed)
                require(observed.startswith(self.collector.last_prefix),'native prefix changed during prompt preparation')
                writer=loads((Path(ready['capture_folder'])/'writer-checkpoint.json').read_bytes())
                rows=journey_readiness.readback(observed,writer,self.identity,cost_policy=self.cost_policy)
                pending=journey_readiness.pending_refresh(rows,ready['snapshot'],self.expected)
                atomic(folder/'pending-observations.json',encoded(pending))
                require(attempt<3,'no quiet readiness within fixed prompt observation bound')
                fresh=self.ready(original_label+'-prompt-'+str(attempt+1),ready['screen'],
                                 subdomain=ready.get('subdomain',False),deadline=end,seconds=max(.001,end-time.time()))
                require(fresh['binding']==ready['binding'] and fresh['owner']['view_id']==ready['owner']['view_id'],
                        'fresh readiness changed the original native owner')
                if ready['screen']=='dashboard':
                    old_web=self.dashboard_for_prompt(rows,ready['snapshot'],ready['owner'])
                    new_web=self.dashboard_for_prompt(self.current_rows(),fresh['snapshot'],fresh['owner'])
                    require(old_web==new_web,'fresh readiness replaced the owned WebView')
                ready=fresh;self.observations[original_label]=fresh
        self.live(end)
        if ready['screen']=='list':
            require(phases.service_list_loaded(ready['ax'],self.selection['service_label']),
                    'selected service is not ready; a heading or permission shell is insufficient')
        self.validate_prompt_ready(ready,label)
        prompt=dict(kind='app-journey',phase=label,instruction=instruction,device=self.device,deadline=end,
                    screenshot=str(screenshot),screenshot_sha256=hashlib.sha256(screenshot.read_bytes()).hexdigest(),
                    request_id=ready['snapshot']['request_id'],native_snapshot_sequence=ready['snapshot']['sequence'])
        atomic(folder/'prompt.json',encoded(dict(prompt=prompt,readiness=receipt,published_at=time.time())))
        self.inputs.append(prompt)
        emit('human_input',prompt)
        return end

    def step(self, ready, label, instruction, screen, *, subdomain=False, authenticated_transition=False, seconds=180):
        end=self.prompt(ready,label,instruction,seconds=seconds)
        # Poll only actual effects, never repeat the requested gesture.
        value=self.await_ready(label,screen,end,subdomain=subdomain,authenticated_transition=authenticated_transition)
        emit('human_status',dict(instruction='Input observed. Capturing the next boundary; wait.'))
        return value

    def await_ready(self,label,screen,end,**options):
        # One original human deadline bounds every local readiness observation.
        return self.ready(label,screen,seconds=max(.001,end-time.time()),deadline=end,**options)

    def background(self, ready, label):
        end=self.prompt(ready,label,'Go to Home once on the selected Duo. Leave the app process running; wait for the return prompt.')
        sequence=ready['snapshot']['sequence'];directory=self.collector.directory
        for index in range(180):
            self.live(end)
            candidates=[]
            for path in directory.glob('checkpoint-background-*.json'):
                suffix=path.stem.removeprefix('checkpoint-background-')
                if suffix.isdigit() and int(suffix)>sequence:candidates.append((int(suffix),path))
            if candidates:
                callback,path=contract.one(candidates,'new background writer checkpoint')
                checkpoint_raw=bounded_read(path,16_384);raw=bounded_read(directory/'events.jsonl',MAX_BYTES)
                folder=self.out/'phases'/(label+'-background');folder.mkdir()
                atomic(folder/'writer-checkpoint.json',checkpoint_raw);atomic(folder/'events.jsonl',raw)
                checkpoint=loads(checkpoint_raw);result=prefix(raw,checkpoint,self.identity,cost_policy=self.cost_policy)
                event=contract.one([r for r in result['rows'] if r['sequence']==callback],'background callback')
                require(event['kind']=='scene_callback' and event['fields']['callback']=='didEnterBackground-exit'
                        and event['fields']['scene']==self.binding['scene'] and event['fields']['app_state']==2
                        and checkpoint['request_id']=='background-'+str(callback), 'wrong background writer boundary')
                tree,home_folder=self.ax(label+'-home',end)
                require(home_observation(tree,home_folder,end),'Home not observed after background callback')
                value=dict(sequence=callback,checkpoint=checkpoint,checkpoint_path=str(folder/'writer-checkpoint.json'),
                           raw_path=str(folder/'events.jsonl'),at=time.time(),deadline=end,home=tree)
                atomic(folder/'background.json',encoded(value));self.backgrounds.append(value)
                emit('human_status',dict(instruction='Home and the original process are verified. Wait for the return prompt.'))
                return value
            time.sleep(.5)
        require(False,'background writer checkpoint missing within original human step')

    def reactivate(self, background, label, screen):
        end=min(self.deadline,time.time()+180);self.live(end)
        # This prompt is bound to actual Home plus the preserved background receipt.
        tree,folder=self.ax(label+'-before-return',end);require(home_observation(tree,folder,end),'Home readiness consumed')
        actual=display(self.device,folder,'display',end)
        require(display_signature(active_display(loads(actual),self.device))==display_signature(active_display(loads(self.initial),self.device)), 'return display changed')
        instruction='Open the same Datadog app from Home once. Do not force quit or relaunch it from Xcode.'
        prompt=dict(kind='app-journey',phase=label,instruction=instruction,device=self.device,deadline=end,
                    background_sequence=background['sequence'])
        atomic(folder/'prompt.json',encoded(dict(prompt=prompt,published_at=time.time(),background=background)))
        self.inputs.append(prompt);emit('human_input',prompt)
        value=self.await_ready(label,screen,end)
        emit('human_status',dict(instruction='The original process is foreground again. Capturing evidence; wait.'))
        return value

    def run(self):
        ready=self.ready('login-initial','login')
        ready=self.step(ready,'login-subdomain','Tap Log In with Subdomain once. Do not enter credentials.','login',subdomain=True)
        ready=self.step(ready,'login-returned','Tap the Back button beside Enter Subdomain once.','login')
        background=self.background(ready,'j01-home')
        ready=self.reactivate(background,'login-reactivated','login')
        j01=phases.j01(self.current_rows(),self.observations,self.expected,background)
        ready=self.step(ready,'service-list','Sign in to the frozen organization '+self.selection['organization']+
                        ', then open the Services list. Do not select a service yet.','list',authenticated_transition=True,seconds=600)
        ready=self.step(ready,'service-detail','Open the existing service '+self.selection['service_label']+' once. Do not edit or favorite it.','detail')
        ready=self.step(ready,'service-list-returned','Use Back once to return to the Services list.','list')
        ready=self.step(ready,'dashboard-begin','Open the existing dashboard '+self.selection['dashboard_label']+'. Wait on its detail page.','dashboard')
        begin=ready
        browser_contract.attached_dashboard(self.current_rows(),ready['snapshot'],ready['owner'])
        # Qualify the actual Browser identity schema before the critical wait.
        browser_contract.local_inventory(self.current_rows(),self.expected)
        emit('human_status',dict(instruction='Leave this dashboard open. The runner will wait beyond the three-minute retention interval.'))
        start=ready['snapshot']['monotonic_ns'];wait_end=time.monotonic()+181
        while time.monotonic()<wait_end:
            self.live(self.deadline);time.sleep(min(.5,wait_end-time.monotonic()))
        ready=self.ready('dashboard-before-input','dashboard')
        require(ready['snapshot']['monotonic_ns']-start>=181_000_000_000,'native retained interval is short')
        before=ready
        require(phases.matches(ready['ax'],self.selection['browser_control_label'])
                and not phases.matches(ready['ax'],self.selection['browser_result_label']),
                'Browser control/effect readiness not independently established')
        end=self.prompt(ready,'dashboard-interaction','Use the frozen read-only Browser control once: '+self.selection['browser_control_label'])
        # The observable resulting control value is frozen before admission.
        observed=False
        for index in range(180):
            self.live(end);tree,_=self.ax('browser-effect-'+str(index),end)
            if phases.matches(tree,self.selection['browser_result_label']):observed=True;break
            time.sleep(.5)
        require(observed,'frozen Browser control effect missing')
        effect=dict(observed_at=time.time(),ax=tree,prompt=self.inputs[-1],deadline=end)
        atomic(self.out/'phases/browser-interaction-effect.json',encoded(effect))
        ready=self.ready('dashboard-after-input','dashboard',deadline=end)
        interval=browser_contract.retained_interval(self.current_rows(),begin['snapshot'],before['snapshot'],ready['snapshot'],
                                                    [begin['owner'],before['owner'],ready['owner']],self.expected)
        interval['human_effect_receipt']=str(self.out/'phases/browser-interaction-effect.json')
        interval['human_effect_sha256']=hashlib.sha256((self.out/'phases/browser-interaction-effect.json').read_bytes()).hexdigest()
        interval['browser_causality_claim']=False
        ready=self.step(ready,'service-list-after-dashboard','Return to the Services list; do not open a service detail.','list')
        authenticated_background=self.background(ready,'j04-home')
        ready=self.reactivate(authenticated_background,'service-list-reactivated','list')
        j04=phases.j04(self.current_rows(),self.observations,self.expected,authenticated_background)
        terminal=self.background(ready,'terminal-home')
        rows=self.current_rows(terminal['checkpoint'])
        return dict(j01=j01,j03=interval,j04=j04,terminal=terminal,phases=self.observations,inputs=self.inputs,
                    backgrounds=self.backgrounds,native_launches=1,process_id=self.expected['pid'])

    def current_rows(self, checkpoint=None):
        if checkpoint is None:
            require(self.last_result is not None, 'actual writer-backed snapshot unavailable')
            return self.last_result['rows']
        raw=bounded_read(self.collector.directory/'events.jsonl',MAX_BYTES)
        return prefix(raw,checkpoint,self.identity,cost_policy=self.cost_policy)['rows']
