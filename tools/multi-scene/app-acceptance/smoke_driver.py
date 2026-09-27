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

    def validate_phase_ready(self, rows, snapshot, owner, visible, screen):
        if screen != 'dashboard':return
        webs=[w for w in snapshot['fields']['topology'].get('webviews',[]) if w.get('window')==owner['native_window']]
        require(len(webs)==1 and webs[0].get('controller')==visible['controller'],
                'dashboard WebView has a different visible owner')
        browser_contract.dashboard_attachment(rows,snapshot,owner,pending=True)
        before=[r for r in rows if r['sequence']<snapshot['sequence']]
        require(any(r['kind']=='browser_message' for r in before), 'dashboard Browser messages not ready', 'PENDING')
        browser_contract.local_inventory(before,self.expected)

    def validate_prompt_ready(self, ready, label):
        if label=='dashboard-setup':
            require(smoke_contract.dashboard_setup_needed(ready),
                    'refreshed dashboard no longer needs the frozen setup')
        if label=='dashboard-interaction':
            if self.definition['mode']=='signed-in-smoke':
                phases.dashboard_timeframe(ready,self.selection['browser_control_label'])
            require(phases.matches(ready['ax'],self.selection['browser_control_label'])
                    and not phases.matches(ready['ax'],self.selection['browser_result_label']),
                    'refreshed Browser control/effect readiness changed')

    def validate_observation_ready(self, ready):
        if ready['screen']!='dashboard' or self.definition['mode']!='signed-in-smoke':return
        # The app hides the timeframe bar until intervalConfirmed arrives.
        # Loaded WebView content alone cannot qualify the next human input.
        phases.dashboard_timeframe_owner(ready)
        require(any(phases.matches(ready['ax'],label,'button') for label in ['1h','15m']),
                'dashboard native time-range control not ready', 'PENDING')
        smoke_contract.dashboard_setup_needed(ready)

    def prepare_dashboard(self, begin):
        if self.definition['mode']!='signed-in-smoke' or not smoke_contract.dashboard_setup_needed(begin):
            return None
        require(not any(p['phase']=='dashboard-setup' for p in self.inputs), 'dashboard setup already consumed')
        end=self.prompt(begin,'dashboard-setup',
            'The dashboard retained 15m. Tap 15m, choose 1 hour, then wait for the next instruction. '
            'This prepares the same starting range as the baseline; do not pin or edit the dashboard.')
        # prompt() can refresh readiness; retain the observation it actually used.
        before=self.observations['dashboard-begin']
        observed=False
        for index in range(180):
            self.live(end);tree,_=self.ax('dashboard-setup-effect-'+str(index),end)
            if phases.matches(tree,'1h','button') and not phases.matches(tree,'15m','button'):
                observed=True;break
            time.sleep(.5)
        require(observed,'dashboard setup effect missing')
        effect=self.out/'phases/dashboard-timeframe-setup-effect.json'
        atomic(effect,encoded(dict(observed_at=time.time(),ax=tree,prompt=self.inputs[-1],deadline=end)))
        after=self.ready('dashboard-setup-complete','dashboard',deadline=end)
        phases.dashboard_timeframe(after,'1h')
        require(before['owner']['view_id']==after['owner']['view_id'] and before['binding']==after['binding'],
                'dashboard setup replaced the owned view')
        require(browser_contract.dashboard_attachment(self.current_rows(),before['snapshot'],before['owner'])
                ==browser_contract.dashboard_attachment(self.current_rows(),after['snapshot'],after['owner']),
                'dashboard setup replaced the owned WebView')
        setup=dict(before_phase='dashboard-begin',after_phase='dashboard-setup-complete',
                   effect_path=str(effect),effect_sha256=hashlib.sha256(effect.read_bytes()).hexdigest())
        smoke_contract.dashboard_setup(self.current_rows(),dict(mode=self.definition['mode'],
            phases=self.observations,inputs=self.inputs,dashboard_setup=setup))
        return setup

    def run(self):
        smoke_contract.definition(self.definition)
        if self.definition['mode'] == 'signed-in-smoke':
            import signed_in_account
            choice=self.definition['dashboard_interaction']
            require(self.selection['browser_control_label']==choice['before']
                    and self.selection['browser_result_label']==choice['after'], 'unqualified dashboard control selection')
            # Account setup is outside the comparison. This fresh launch still
            # proves its real Home owner before navigating to Services.
            entry=self.ready('signed-in-entry','account-home')
            ready=self.step(entry,'service-list','Open Services in '+self.selection['organization']+
                            '. Do not select a service yet.','list',authenticated_transition=True)
            self.account_binding=signed_in_account.subject(self.current_rows(),ready,self.expected['account_salt'])
            if self.expected.get('baseline_account_binding') is not None:
                require(self.account_binding['digests']==self.expected['baseline_account_binding']['digests'],
                        'candidate account or organization differs from baseline')
            atomic(self.out/'account-binding.json',encoded(self.account_binding))
        else:
            ready=self.ready('login-initial','login')
            ready=self.step(ready,'login-subdomain','Tap Log In with Subdomain once, then stop. Leave the text field untouched and do not type. Wait for the Back instruction.','login',subdomain=True)
            ready=self.step(ready,'login-returned','Tap the Back button beside Enter Subdomain once.','login')
            ready=self.step(ready,'service-list','Use QR code login for '+self.selection['organization']+
                            ': tap Scan QR Code, then Choose QR Code Image and select the login screenshot from Photos. '
                            'After sign-in, open the Services list. Do not select a service yet.','list',authenticated_transition=True,seconds=600)
        ready=self.step(ready,'service-detail','Open the existing service '+self.selection['service_label']+' once. Do not edit or favorite it.','detail')
        ready=self.step(ready,'service-list-returned','Use Back once to return to the Services list. If Search is open, tap Close to reveal the Services heading; do not tap Back again.','list')
        begin=self.step(ready,'dashboard-begin','Open the existing dashboard '+self.selection['dashboard_label']+'. Wait on its detail page.','dashboard')
        browser_contract.dashboard_attachment(self.current_rows(),begin['snapshot'],begin['owner'])
        browser_contract.local_inventory(self.current_rows(),self.expected)
        setup=self.prepare_dashboard(begin)
        begin=self.observations['dashboard-begin']
        before=self.ready('dashboard-before-input','dashboard')
        require(phases.matches(before['ax'],self.selection['browser_control_label'])
                and not phases.matches(before['ax'],self.selection['browser_result_label']),
                'Browser control/effect readiness not independently established')
        instruction='Use the frozen read-only Browser control once: '+self.selection['browser_control_label']
        if self.definition['mode']=='signed-in-smoke':
            instruction='Tap the dashboard time-range button '+choice['before']+', choose '+choice['menu_choice']+', then wait for '+choice['after']+'. Do not pin the time or edit the dashboard.'
        end=self.prompt(before,'dashboard-interaction',instruction)
        observed=False
        for index in range(180):
            self.live(end);tree,_=self.ax('browser-effect-'+str(index),end)
            role='button' if self.definition['mode']=='signed-in-smoke' else None
            if (phases.matches(tree,self.selection['browser_result_label'],role)
                    and not phases.matches(tree,self.selection['browser_control_label'],role)):observed=True;break
            time.sleep(.5)
        require(observed,'frozen Browser control effect missing')
        effect=self.out/'phases/browser-interaction-effect.json'
        atomic(effect,encoded(dict(observed_at=time.time(),ax=tree,prompt=self.inputs[-1],deadline=end)))
        after=self.ready('dashboard-after-input','dashboard',deadline=end)
        if self.definition['mode']=='signed-in-smoke':
            phases.dashboard_timeframe(after,choice['after'])
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
        native=dict(mode=self.definition['mode'],j03=interval,phases=self.observations,inputs=self.inputs,backgrounds=self.backgrounds,
                    terminal=dict(checkpoint=checkpoint,foreground=True),native_launches=1,process_id=self.expected['pid'],device=self.device)
        if setup is not None:native['dashboard_setup']=setup
        if self.definition['mode']=='signed-in-smoke':native['account_binding']=self.account_binding
        native['manifest']=smoke_contract.native_manifest(result['rows'],native,self.expected,self.definition)
        emit('human_status',dict(instruction='The journey is captured. Leave the app on this Services screen without touching it while ordinary uploads finish.'))
        return native
