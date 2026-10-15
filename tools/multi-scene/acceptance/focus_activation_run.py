"""One reviewed H04 physical run; component verdicts never change release gates.

The caller supplies a freshly discovered Device and services the existing backend
request files. This runner does not build, authenticate, drive UI or renew cutoffs.
"""
from pathlib import Path
import plistlib
import time
import uuid
from urllib.parse import unquote, urlparse

import focus_activation_backend as backend
import focus_activation_host as host
import focus_activation_recorder as recorder
import focus_activation_transport as protocol
import installed_code
import operation_launch as shared
import operation_setup as setup
import operation_transport as t

KIND = 'H04_PHYSICAL_ACTIVATION'
SDK, BUNDLE, REVIEWER = shared.SDK, shared.BUNDLE, shared.REVIEWER


def product(plan):
    """Compiler/source assessment is reviewed; recheck all admitted bytes here."""
    t.require(plan['schemaVersion'] == 1 and plan['kind'] == KIND and plan['sourceRevision'] == SDK
              and plan['buildConfiguration'] == 'Debug' and plan['bundle'] == BUNDLE
              and plan['scenario'] == protocol.SCENARIO and plan['profile'] == protocol.PROFILE,
              'wrong H04 product or scenario scope')
    app = shared.operator.clean_path(plan['app'])
    info = plistlib.loads(setup.read(app/'Info.plist'))
    t.require(info['CFBundleIdentifier'] == BUNDLE and info['CFBundleSupportedPlatforms'] == ['iPhoneOS']
              and info['DTPlatformName'] == 'iphoneos' and info['MinimumOSVersion'] == '27.0'
              and setup.file_sha(app/'Info.plist') == plan['infoSHA256'], 'physical H04 app metadata differs')
    t.require(installed_code.inventory(app) == plan['product'], 'signed H04 Mach-O inventory changed')
    t.require(set(plan['buildEvidence']) == {'source','compiler','build','signature'}, 'incomplete H04 build evidence')
    for reference in plan['buildEvidence'].values(): shared.reference(reference)
    source = t.load(setup.read(shared.reference(plan['buildEvidence']['source'])), maximum=t.MAX_CONTEXT_BYTES)
    t.require(source['sourceRevision'] == SDK and source['buildConfiguration'] == 'Debug'
              and isinstance(source['files'],dict) and source['files'], 'wrong H04 frozen source manifest')
    for path, digest in source['files'].items():
        t.require(setup.file_sha(shared.operator.clean_path(path)) == digest, 'H04 frozen source changed')
    current = shared.helper_sources()
    t.require(current.keys() <= plan['helpers'].keys() and all(setup.file_sha(shared.operator.clean_path(path)) == digest
              for path,digest in plan['helpers'].items()), 'H04 runner helpers changed or incomplete')
    identity = plan['backend']['identity']
    t.require(set(identity) == {'application_id','service','source'} and t.identifier(identity['application_id'])
              and identity['source'] == 'ios' and isinstance(identity['service'],str) and identity['service'],
              'backend application/service missing')
    t.require(type(plan['backend']['maximumAttempts']) is int and 1 <= plan['backend']['maximumAttempts'] <= 24
              and setup.finite(plan['backend']['pollSeconds']) and 0 < plan['backend']['pollSeconds'] <= 60,
              'unbounded backend polling policy')
    return app


def admission(value, plan_raw, output, now):
    t.require(value['state'] == 'NATIVE_ADMITTED' and value['scope'] == KIND and value['reviewer'] == REVIEWER
              and value['planSHA256'] == t.sha(plan_raw) and value['output'] == str(output)
              and value['maximumNativeCells'] == 1, 'H04 native run not separately admitted')
    review = t.load(setup.read(shared.reference(value['review'])))
    t.require(review['state'] == 'PASS' and review['scope'] == KIND and review['reviewer'] == REVIEWER
              and review['planSHA256'] == t.sha(plan_raw) and review['remainingFindings'] == [], 'H04 final review absent')
    identity = value['identity']
    t.require(set(identity) == {'runID','startupNonce'} and len(set(identity.values())) == 2
              and all(isinstance(v,str) and str(uuid.UUID(v)) == v for v in identity.values()), 'H04 run identity invalid')
    cuts = value['cutoffs']
    keys = ['launchUntil','executionUntil','backendUntil','deadline']
    t.require(set(cuts) == set(keys) and all(type(cuts[k]) is int for k in keys)
              and setup.finite(value['issuedAt']) and value['issuedAt'] <= now < cuts['launchUntil']
              < cuts['executionUntil'] < cuts['backendUntil'] < cuts['deadline'] <= value['issuedAt']+10_800
              and cuts['backendUntil'] <= value['issuedAt']+backend.transport.MAX_BUDGET_SECONDS,
              'H04 fixed cutoffs invalid or outside collector budget')
    # Access is a real preflight receipt supplied by the tool dispatcher, not an empty query as app discovery.
    access = t.load(setup.read(shared.reference(value['backendAccess'])))
    t.require(access['state'] == 'APPLICATION_AND_RUM_READ_VERIFIED' and access['identity'] == t.load(plan_raw)['backend']['identity']
              and value['issuedAt'] <= access['observedAt'] <= now
              and set(access['observations']) == {'application','rumRead'}, 'fresh backend access not proved')
    for ref in access['observations'].values(): shared.reference(ref)
    return dict(cuts)


def executable_path(value):
    parsed = urlparse(value)
    t.require(parsed.scheme in ['', 'file'] and parsed.netloc in ['', 'localhost'], 'foreign device executable URL')
    path = Path(unquote(parsed.path))
    t.require(path.is_absolute() and '..' not in path.parts, 'ambiguous device executable path')
    return path


class Runner:
    def __init__(self, remote, plan_path, admission_path, output, *, environment,
                 notify=backend.shared.notify_request, wait=time.sleep):
        self.remote, self.output = remote, shared.operator.clean_path(output)
        t.require(not self.output.exists(), 'H04 run output already consumed')
        self.plan_path = shared.operator.clean_path(plan_path); self.plan_raw = setup.read(self.plan_path)
        self.admission_path = shared.operator.clean_path(admission_path); self.admission_raw = setup.read(self.admission_path)
        self.plan, self.admission = t.load(self.plan_raw), t.load(self.admission_raw)
        self.started = time.time(); self.cutoffs = admission(self.admission,self.plan_raw,self.output,self.started)
        self.frozen = t.encode(dict(plan=self.plan,admission=self.admission))
        self.environment, self.notify, self.wait = dict(environment), notify, wait
        self.used = self.install_attempted = self.launch_attempted = self.absence_proved = False
        self.session = None; self.capture = None; self.installed = None
        self.output.mkdir(); t.save(self.output/'plan.json',self.plan_raw); t.save(self.output/'admission.json',self.admission_raw)
        self.observed = host.ObservedDevice(remote,self.output,self.cutoffs['launchUntil'],self.started)
        self.result = dict(state='RUNNING',scenario='UNRUN',evidence='UNRUN',cleanup='UNTOUCHED',
                           installAttempted=False,launchAttempted=False,sdkRegression=False,
                           releaseAcceptance=False,gatesClosed=[],errors=[])

    def live(self, phase):
        t.require(time.time() < self.cutoffs[phase] and self.remote.identifier == self.plan['device']
                  and setup.read(self.plan_path) == self.plan_raw and setup.read(self.admission_path) == self.admission_raw
                  and setup.read(self.output/'plan.json') == self.plan_raw and setup.read(self.output/'admission.json') == self.admission_raw
                  and t.encode(dict(plan=self.plan,admission=self.admission)) == self.frozen
                  and self.cutoffs == self.admission['cutoffs'], 'H04 inputs changed or original cutoff expired')

    def apps(self, observed, label):
        raw,_ = observed.command(['device','info','apps','--bundle-id',BUNDLE],label); value = raw['result']
        t.require(value.get('deviceIdentifier') == self.remote.identifier and value.get('matchingBundleIdentifier') == BUNDLE
                  and isinstance(value.get('apps'),list), 'task app inventory missing or ambiguous')
        return value['apps']

    def no_process(self, observed, label):
        raw,_ = observed.command(['device','info','processes'],label)
        shared.require_no_task_process(raw['result'].get('runningProcesses'),self.app,self.plan['product'])

    def preflight(self):
        self.live('launchUntil'); self.app = product(self.plan); shared.toolchain(self.plan,self.environment)
        setup.command(['/usr/bin/codesign','--verify','--deep','--strict',str(self.app)],
                      self.output,'signature',self.cutoffs['launchUntil'])
        folder = self.output/'publication-preflight'; folder.mkdir(); backend.transport.preflight(folder)
        raw,_ = self.observed.command(['device','info','details'],'preflight-device'); result = raw['result']
        h,v = result['hardwareProperties'],result['deviceProperties']
        t.require(h['reality'] == 'physical' and h['deviceType'] == 'iPad' and h['udid'] == self.plan['udid']
                  and v['developerModeStatus'] == 'enabled' and v['ddiServicesAvailable'] is True
                  and int(v['osVersionNumber'].split('.')[0]) >= 27 and v['osBuildUpdate'], 'physical iPad prerequisites absent')
        lock,_ = self.observed.command(['device','info','lockState'],'preflight-lock')
        t.require(lock['result']['passcodeRequired'] is False and lock['result']['unlockedSinceBoot'] is True, 'physical iPad locked')
        raw,_ = self.observed.command(['device','info','displays'],'preflight-display'); display = setup.display(raw)
        t.require(self.apps(self.observed,'preflight-app-absence') == [], 'task app already installed')
        self.no_process(self.observed,'preflight-process-absence'); self.live('launchUntil'); self.absence_proved = True
        t.save(self.output/'preflight.json',t.encode(dict(state='PASS',physicalDevice=h['udid'],os=v['osVersionNumber'],
            build=v['osBuildUpdate'],display=display,planSHA256=t.sha(self.plan_raw),admissionSHA256=t.sha(self.admission_raw),
            taskAppAbsence=True,taskProcessAbsence=True,at=time.time())))

    def launch(self):
        self.live('launchUntil'); product(self.plan)
        self.install_attempted = True; self.result['installAttempted'] = True
        raw,_ = self.observed.command(['device','install','app',str(self.app)],'install'); value = raw['result']
        rows = value.get('installedApplications')
        t.require(value.get('deviceIdentifier') == self.remote.identifier and isinstance(rows,list) and len(rows) == 1
                  and rows[0].get('bundleID') == BUNDLE, 'installed app response differs')
        self.installed = executable_path(rows[0]['installationURL'])
        t.require(self.installed.name == self.app.name, 'installed app URL differs')
        self.live('launchUntil'); product(self.plan)
        identity = self.admission['identity']; run_id,nonce = identity['runID'],identity['startupNonce']
        env = dict(DD_PROBE_CAPTURE_JSONL='1',DD_PROBE_FOCUS_ACTIVATION_PROFILE=protocol.PROFILE,
                   MULTISCENE_CODE_IDENTITY_RUN_ID=run_id,MULTISCENE_CODE_IDENTITY_REVISION=SDK,
                   DD_PROBE_FOCUS_STARTUP_NONCE=nonce,
                   DD_PROBE_FOCUS_EXECUTION_DEADLINE_MS=str(self.cutoffs['executionUntil']*1000),
                   DD_PROBE_FOCUS_CLEANUP_DEADLINE_MS=str(self.cutoffs['deadline']*1000))
        args = ['device','process','launch','--environment-variables',t.encode(env).decode(),BUNDLE,'--',
                '--probe-scenario',protocol.SCENARIO,'--probe-run-id',run_id,'--probe-run-mode','clean']
        t.save(self.output/'launch-inputs.json',t.encode(dict(arguments=args,environment=env)))
        self.launch_attempted = True; self.result['launchAttempted'] = True
        raw,_ = self.observed.command(args,'launch'); pid = raw['result']['process']['processIdentifier']
        t.require(type(pid) is int and pid > 0, 'actual launched PID missing')
        current,_ = self.observed.command(['device','info','processes'],'launched-process')
        process = setup.device_process(current,dict(processID=pid),self.plan['product'],self.app.name)
        t.require(executable_path(process['executable']) == self.installed/self.plan['product']['executable'],
                  'launched process differs from exact installed app URL')
        t.save(self.output/'launched-process.json',t.encode(dict(process=process,installedURL=str(self.installed),at=time.time())))
        self.session = host.Session(self.remote,self.app,self.output/'session',run_id=run_id,process_id=pid,revision=SDK,
            startup_nonce=nonce,execution_ms=self.cutoffs['executionUntil']*1000,cleanup_ms=self.cutoffs['deadline']*1000,
            device_udid=self.plan['udid'],wait=lambda:self.wait(1))
        self.session.bootstrap()
        t.require(self.session.process == process, 'bootstrap process changed after launch')
        self.live('launchUntil')

    def collect(self):
        self.live('executionUntil'); product(self.plan); self.session.exchange('arm')
        self.capture = self.session.collect(); self.live('executionUntil')
        _,local = recorder.verified(self.capture)
        t.save(self.output/'scenario.json',t.encode(dict(state='PASS',capture=str(self.capture),
            captureSHA256=setup.file_sha(self.capture/'result.json'),local=local['local'],at=time.time())))
        self.result['scenario'] = 'PASS'
        self.live('backendUntil')
        collector = backend.Backend(self.capture,self.output/'backend',self.plan['backend']['identity'],
            deadline=self.cutoffs['backendUntil'],maximum_attempts=self.plan['backend']['maximumAttempts'],
            poll_seconds=self.plan['backend']['pollSeconds'],notify=self.notify,wait=self.wait)
        collector.collect(); self.live('backendUntil'); self.result['evidence'] = 'PASS'

    def prelaunch_cleanup(self):
        t.require(self.absence_proved and self.install_attempted and not self.launch_attempted,
                  'prelaunch cleanup lacks original absence or launch may exist')
        self.live('deadline'); self.remote.quiescent(self.cutoffs['deadline'])
        quiet = t.load(setup.read(self.remote.output/'before-cleanup-quiescence.json'))
        t.require(quiet['state'] == 'PASS' and quiet['remaining'] == [] and quiet['groups'] == self.remote.groups
                  and quiet['deadline'] == self.cutoffs['deadline'] and self.started <= quiet['at'] < self.cutoffs['deadline'],
                  'prelaunch workers not quiescent')
        observed = host.ObservedDevice(self.remote,self.output,self.cutoffs['deadline'],self.started)
        self.no_process(observed,'prelaunch-cleanup-processes')
        rows = self.apps(observed,'prelaunch-cleanup-apps')
        t.require(rows == [] or len(rows) == 1 and rows[0].get('bundleIdentifier') == BUNDLE, 'ambiguous task installation')
        if rows:
            raw,_ = observed.command(['device','uninstall','app',BUNDLE],'prelaunch-uninstall')
            t.require(raw['result'].get('deviceIdentifier') == self.remote.identifier and
                      raw['result'].get('uninstalledApplications') == [dict(bundleID=BUNDLE)], 'prelaunch uninstall differs')
        t.require(self.apps(observed,'prelaunch-final-app-absence') == [], 'task app remains')
        self.no_process(observed,'prelaunch-final-process-absence'); self.live('deadline')
        return dict(state='PASS',scope='TASK_INSTALL_WITHOUT_LAUNCH',containerAbsence='UNVERIFIED',
                    dataDisposition='OS_APP_UNINSTALL_CONTRACT',at=time.time())

    def run(self):
        t.require(not self.used, 'H04 run already consumed'); self.used = True
        t.save(self.output/'consumed.json',t.encode(dict(planSHA256=t.sha(self.plan_raw),admissionSHA256=t.sha(self.admission_raw),
            identity=self.admission['identity'],device=self.remote.identifier,cutoffs=self.cutoffs,at=time.time())))
        try:
            self.preflight(); self.launch(); self.collect()
        except Exception as error:
            phase = 'evidence' if self.result['scenario'] == 'PASS' else 'scenario'
            self.result[phase] = 'INCOMPLETE' if phase == 'evidence' else 'INVALID'
            self.result['errors'].append(dict(phase=phase,type=type(error).__name__,reason=str(error)))
        finally:
            try:
                if self.session is not None and self.session.bootstrap_raw is not None:
                    # Backend failure does not consume the independent stop/export/cleanup reserve.
                    self.live('deadline'); cleaned = self.session.cleanup(); self.live('deadline')
                    t.require(cleaned['state'] == 'TASK_APP_REMOVED', 'task removal incomplete')
                    self.result['cleanup'] = 'PASS'
                    if self.result['scenario'] == 'PASS' and cleaned['finalCaptureState'] != 'SEALED_FOCUS_PREFIX':
                        self.result['scenario'] = 'INVALID'
                        self.result['errors'].append(dict(phase='scenario',reason='final capture invalidated the frozen prefix'))
                elif self.install_attempted and not self.launch_attempted:
                    cleaned = self.prelaunch_cleanup(); self.result['cleanup'] = 'PASS'
                elif self.launch_attempted:
                    cleaned = dict(state='BLOCKED',reason='attempted launch lacks complete bootstrap; preserve task app')
                    self.result['cleanup'] = 'BLOCKED'
                else:
                    cleaned = dict(state='UNTOUCHED'); self.result['cleanup'] = 'UNTOUCHED'
                t.save(self.output/'cleanup.json',t.encode(cleaned))
            except Exception as error:
                self.result['cleanup'] = 'BLOCKED'
                self.result['errors'].append(dict(phase='cleanup',type=type(error).__name__,reason=str(error)))
            self.result['state'] = 'QUALIFIED_PHYSICAL_H04_COMPONENT' if all(self.result[k] == 'PASS'
                for k in ['scenario','evidence','cleanup']) else 'INVALID'
            self.result.update(at=time.time(),planSHA256=t.sha(self.plan_raw),admissionSHA256=t.sha(self.admission_raw),
                               artifacts={p.name:setup.file_sha(p) for p in self.output.iterdir() if p.is_file()})
            t.save(self.output/'result.json',t.encode(self.result))
        return self.result
