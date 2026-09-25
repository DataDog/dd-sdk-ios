"""One app smoke journey, one lifecycle cycle, then ordinary foreground delivery."""
import hashlib
import time
from pathlib import Path

from journey_driver import Driver as JourneyDriver, emit
import journey_phases as phases
import browser_contract
import smoke_contract
from capture_io import atomic, encoded, bounded_read
from capture_contract import loads, MAX_BYTES
from acceptance_common import require


class Driver(JourneyDriver):
    cost_policy = smoke_contract.COST_POLICY

    def dashboard_for_prompt(self, rows, snapshot, owner):
        return browser_contract.dashboard_attachment(rows, snapshot, owner)

    def validate_prompt_ready(self, ready, label):
        if label=='dashboard-interaction':
            require(phases.matches(ready['ax'],self.selection['browser_control_label'])
                    and not phases.matches(ready['ax'],self.selection['browser_result_label']),
                    'refreshed Browser control/effect readiness changed')

    def run(self):
        smoke_contract.definition(self.definition)
        ready=self.ready('login-initial','login')
        ready=self.step(ready,'login-subdomain','Tap Log In with Subdomain once, then stop. Leave the text field untouched and do not type. Wait for the Back instruction.','login',subdomain=True)
        ready=self.step(ready,'login-returned','Tap the Back button beside Enter Subdomain once.','login')
        ready=self.step(ready,'service-list','Sign in to the frozen organization '+self.selection['organization']+
                        ', then open the Services list. Do not select a service yet.','list',authenticated_transition=True,seconds=600)
        ready=self.step(ready,'service-detail','Open the existing service '+self.selection['service_label']+' once. Do not edit or favorite it.','detail')
        ready=self.step(ready,'service-list-returned','Use Back once to return to the Services list.','list')
        begin=self.step(ready,'dashboard-begin','Open the existing dashboard '+self.selection['dashboard_label']+'. Wait on its detail page.','dashboard')
        browser_contract.dashboard_attachment(self.current_rows(),begin['snapshot'],begin['owner'])
        browser_contract.local_inventory(self.current_rows(),self.expected)
        before=self.ready('dashboard-before-input','dashboard')
        require(phases.matches(before['ax'],self.selection['browser_control_label'])
                and not phases.matches(before['ax'],self.selection['browser_result_label']),
                'Browser control/effect readiness not independently established')
        end=self.prompt(before,'dashboard-interaction','Use the frozen read-only Browser control once: '+self.selection['browser_control_label'])
        observed=False
        for index in range(180):
            self.live(end);tree,_=self.ax('browser-effect-'+str(index),end)
            if phases.matches(tree,self.selection['browser_result_label']):observed=True;break
            time.sleep(.5)
        require(observed,'frozen Browser control effect missing')
        effect=self.out/'phases/browser-interaction-effect.json'
        atomic(effect,encoded(dict(observed_at=time.time(),ax=tree,prompt=self.inputs[-1],deadline=end)))
        after=self.ready('dashboard-after-input','dashboard',deadline=end)
        # prompt() may refresh readiness; use its actual returned observation.
        before=self.observations['dashboard-before-input']
        interval=smoke_contract.dashboard_interval(self.current_rows(),begin['snapshot'],before['snapshot'],after['snapshot'],
                                                   [begin['owner'],before['owner'],after['owner']],self.expected)
        interval.update(human_effect_receipt=str(effect),human_effect_sha256=hashlib.sha256(effect.read_bytes()).hexdigest())
        ready=self.step(after,'service-list-after-dashboard','Return to the Services list; do not open a service detail.','list')
        background=self.background(ready,'j04-home')
        ready=self.reactivate(background,'service-list-reactivated','list')
        checkpoint=loads((Path(ready['capture_folder'])/'writer-checkpoint.json').read_bytes())
        raw=bounded_read(self.collector.directory/'events.jsonl',MAX_BYTES)
        frozen,result=smoke_contract.freeze(raw,checkpoint,self.identity)
        atomic(self.out/'behavior-prefix.jsonl',frozen)
        atomic(self.out/'behavior-checkpoint.json',encoded(checkpoint))
        native=dict(mode='smoke',j03=interval,phases=self.observations,inputs=self.inputs,backgrounds=self.backgrounds,
                    terminal=dict(checkpoint=checkpoint,foreground=True),native_launches=1,process_id=self.expected['pid'],device=self.device)
        native['manifest']=smoke_contract.native_manifest(result['rows'],native,self.expected,self.definition)
        emit('human_status',dict(instruction='The journey is captured. Leave the app on this Services screen without touching it while ordinary uploads finish.'))
        return native
