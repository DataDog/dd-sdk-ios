"""One physical H06 launch up to the existing Session's admission boundary.

Product preparation and native qualification are separate reviewed artifacts. This
adapter never builds, predicts a device PID, synthesizes a challenge or retries a
launch. An unverified attempted launch leaves the app in place for safe recovery.
"""
from pathlib import Path
import plistlib
import re
import sys
import time
import uuid
from urllib.parse import unquote, urlparse

import installed_code
import operation_cleanup as cleanup
import operation_display as pixels
import operation_media as media
import operation_operator as operator
import operation_quicktime as quicktime
import operation_quicktime_session as quicktime_session
import operation_session as session
import operation_setup as setup
import operation_transport as t
import s2_hosting_workflow as workflow

SDK = '94842cc8ad7b104c1394c236b98b95b6c24a0956'
BUNDLE = 'com.datadoghq.rum-native-multi-scene-probe'
SCENARIO = 'operations.cross-scene.physical-setup'
REVIEWER = '/root/c06_runtime_plan'


def reference(value):
    t.require(isinstance(value, dict) and set(value) == {'path', 'sha256'}
              and t.digest(value['sha256']), 'invalid launch evidence reference')
    path = operator.clean_path(value['path'])
    t.require(setup.file_sha(path) == value['sha256'], 'launch evidence changed')
    return path


def helper_sources():
    parent = Path(__file__).resolve().parents[1]
    paths = {Path(__file__).resolve(), *Path(__file__).parent.glob('operation_*.py')}
    for module in list(sys.modules.values()):
        filename = getattr(module, '__file__', None)
        if filename:
            path = Path(filename).resolve()
            if path.is_relative_to(parent) and path.suffix == '.py' and not path.name.startswith('test_'):
                paths.add(path)
    return {str(path): setup.file_sha(path) for path in sorted(paths)}


def product(plan):
    """Recheck the prepared bytes; the bound review owns compiler qualification."""
    t.require(plan['schemaVersion'] == 1 and plan['kind'] == 'H06_PHYSICAL_LAUNCH'
              and plan['sourceRevision'] == SDK and plan['buildConfiguration'] == 'Debug'
              and plan['bundle'] == BUNDLE, 'unreviewed launch product scope')
    app = operator.clean_path(plan['app'])
    info = plistlib.loads(setup.read(app/'Info.plist'))
    t.require(info['CFBundleIdentifier'] == BUNDLE and info['CFBundleSupportedPlatforms'] == ['iPhoneOS']
              and info['DTPlatformName'] == 'iphoneos', 'not the physical probe product')
    t.require(installed_code.inventory(app) == plan['product'], 'signed product changed')
    t.require(set(plan['buildEvidence']) == {'source', 'compiler', 'build', 'signature'},
              'incomplete product qualification evidence')
    for value in plan['buildEvidence'].values(): reference(value)
    sources = t.load(setup.read(reference(plan['buildEvidence']['source'])), maximum=t.MAX_CONTEXT_BYTES)
    t.require(sources['sourceRevision'] == SDK and sources['buildConfiguration'] == 'Debug'
              and isinstance(sources['files'], dict) and sources['files'], 'wrong compiled source manifest')
    for path, digest in sources['files'].items():
        t.require(setup.file_sha(operator.clean_path(path)) == digest, 'frozen native source changed')
    current = helper_sources()
    t.require(current.keys() <= plan['helpers'].keys()
              and all(setup.file_sha(operator.clean_path(path)) == digest for path,digest in plan['helpers'].items()),
              'launcher helper inventory changed')
    profile = plan['profile']
    t.require(set(profile) == t.PROFILE_KEYS and profile['sourceRevision'] == SDK
              and profile['buildConfiguration'] == 'Debug' and t.digest(profile['scenarioSHA256'])
              and profile['inference'] == 'debug-rum-ui-event-network-context', 'wrong inference contract')
    t.validate_setup(plan['setupProfile'])
    for key in ['source', 'binary']: reference(plan['decoder'][key])
    t.require(reference(plan['decoder']['source']) == Path(pixels.__file__).with_suffix('.swift').resolve(),
              'foreign display decoder source')
    return app


def toolchain(plan, environment):
    """Bind recording and CoreDevice transfers to the same prepared Xcode bytes."""
    value = plan['toolchain']; developer = Path(workflow.DEVELOPER)
    t.require(set(value) == {'developer', 'version', 'devicectl'}
              and value['developer'] == str(developer)
              and environment.get('DEVELOPER_DIR') == str(developer), 'capture/transfer Xcode environment differs')
    t.require(reference(value['version']) == developer.parent/'version.plist'
              and reference(value['devicectl']) == developer/'usr/bin/devicectl', 'capture toolchain changed')
    return value


def stage_cutoffs(value, now, *, with_backend=False):
    keys = ['launchUntil','recordUntil','stopUntil','executionUntil','deadline']
    expected = keys + (['backendUntil'] if with_backend else [])
    t.require(set(value) == set(expected) and all(setup.finite(value[k]) for k in expected), 'missing fixed stage cutoffs')
    a,b,c,d,e = [value[k] for k in keys]
    t.require(now < a < b < c <= d < e, 'closed or unordered stage cutoffs')
    if with_backend:
        t.require(d < value['backendUntil'] < e, 'backend cutoff leaves no cleanup reserve')
    return dict(value)


def new_identity():
    """Freeze in the admission before requesting the operator's acknowledgement."""
    return dict(zip(['runID', 'startupNonce', 'displayNonce'], [str(uuid.uuid4()) for _ in range(3)]))


def launch_readiness(directory, raw, plan_raw, admission_raw, now):
    admission, plan, reply = t.load(admission_raw), t.load(plan_raw), t.load(raw)
    identity = admission['identity']
    t.require(set(identity) == {'runID','startupNonce','displayNonce'}
              and len(set(identity.values())) == 3
              and all(isinstance(v,str) and str(uuid.UUID(v)) == v for v in identity.values()),
              'invalid frozen launch nonces')
    server_raw = setup.read(directory/'server.json'); server = t.load(server_raw)
    t.require(set(server) == {'state','pid','url','started_at','seconds','native_launches','directory','nonce'}
              and server['state'] == 'BOUND_OPERATOR_PAGE' and type(server['pid']) is int and server['pid'] > 0
              and server['directory'] == str(directory) and t.identifier(server['nonce'])
              and type(server['native_launches']) is int and server['native_launches'] == 0
              and isinstance(server['url'],str) and re.fullmatch(r'http://127\.0\.0\.1:[0-9]{1,5}',server['url'])
              and 0 < int(server['url'].rsplit(':',1)[1]) < 65536
              and type(server['seconds']) is int and 0 < server['seconds'] <= 21600
              and setup.finite(server['started_at']), 'foreign operator server')
    t.require(reply.get('kind') == 'OPERATOR_READY' and reply.get('planSHA256') == t.sha(plan_raw)
              and reply.get('admissionSHA256') == t.sha(admission_raw)
              and reply.get('identitySHA256') == t.sha(t.encode(identity))
              and reply.get('channel') == server and reply.get('device') == plan['device']
              and reply.get('mode') == SCENARIO and isinstance(reply.get('userMessageReference'),str)
              and reply['userMessageReference'].strip() and setup.finite(reply.get('at'))
              and setup.finite(admission['issuedAt'])
              and server['started_at'] <= admission['issuedAt'] <= reply['at'] <= now < admission['cutoffs']['launchUntil']
              and admission['cutoffs']['deadline'] <= server['started_at']+server['seconds'],
              'readiness is foreign, stale or outside the original launch window')
    state = t.load(setup.read(directory/'state.json'))
    t.require(state.get('ready') is False and state.get('cleanup_started') is False
              and state.get('deadline') is None and 'release_request' not in state, 'operator page already consumed')
    return server_raw


def require_no_task_process(rows, app, product):
    """Decode actual device file URLs; missing or ambiguous ownership blocks removal."""
    t.require(isinstance(rows,list), 'process inventory absent')
    seen = set()
    for row in rows:
        pid, executable = row.get('processIdentifier'), row.get('executable')
        t.require(type(pid) is int and pid > 0 and pid not in seen and isinstance(executable,str) and executable,
                  'ambiguous process inventory')
        seen.add(pid); parsed = urlparse(executable)
        t.require(parsed.scheme in ['', 'file'] and parsed.netloc in ['', 'localhost'], 'unrecognized process executable URL')
        path = Path(unquote(parsed.path)); t.require(path.is_absolute(), 'relative process executable')
        bundle = row.get('bundleIdentifier')
        if bundle is not None:
            t.require(isinstance(bundle,str) and bundle, 'ambiguous process bundle')
            t.require(bundle != BUNDLE, 'task process remains before cleanup')
            t.require(path.parts[-2:] != (app.name, product['executable']),
                      'foreign bundle conflicts with task executable ownership')
            continue
        t.require(path.parts[-2:] != (app.name, product['executable'])
                  and path.name != product['executable'] and path.parent.name != app.name,
                  'task process remains or executable ownership is ambiguous')


class Launcher:
    """One installed product and one actual startup, then hand off exactly once."""
    def __init__(self, root, remote, plan_path, admission_path, readiness_path, *,
                 environment, wait=lambda: time.sleep(.25)):
        self.root = operator.clean_path(root); self.remote = remote
        self.plan_path = operator.clean_path(plan_path)
        self.plan_raw = setup.read(self.plan_path); self.plan = t.load(self.plan_raw)
        self.admission_raw = setup.read(admission_path); self.admission = t.load(self.admission_raw)
        self.readiness_raw = setup.read(readiness_path)
        self.environment, self.wait = dict(environment), wait
        self.started = time.time(); self.cutoffs = stage_cutoffs(self.admission['cutoffs'], self.started, with_backend=True)
        self.folder = self.root/'cells'/'h06-launch'; self.folder.mkdir()
        self.launch_attempted = self.install_attempted = self.absence_proved = False
        self.used = False; self.bound_session = None; self.sequence = 0
        identity = self.admission['identity']
        self.run_id, self.startup_nonce, self.display_nonce = [identity[k] for k in ['runID','startupNonce','displayNonce']]
        self.directory = self.root/'operator'
        for name,raw in [('plan.json',self.plan_raw),('admission.json',self.admission_raw),('readiness.json',self.readiness_raw)]:
            t.save(self.folder/name,raw)
        t.save(self.folder/'identity.json',t.encode(dict(runID=self.run_id,startupNonce=self.startup_nonce,
            displayNonce=self.display_nonce,cutoffs=self.cutoffs,device=remote.identifier,processID=None)))
        self.observed = cleanup.ObservedDevice(remote,self.folder,self.cutoffs['launchUntil'],self.started)

    def live(self):
        t.require(time.time() < self.cutoffs['launchUntil'] and setup.read(self.plan_path) == self.plan_raw
                  and setup.read(self.folder/'admission.json') == self.admission_raw
                  and setup.read(self.folder/'plan.json') == self.plan_raw
                  and setup.read(self.folder/'readiness.json') == self.readiness_raw
                  and t.encode(self.admission) == t.encode(t.load(self.admission_raw))
                  and t.encode(self.plan) == t.encode(t.load(self.plan_raw))
                  and self.cutoffs == t.load(self.admission_raw)['cutoffs']
                  and self.remote.identifier == self.plan['device'], 'launch binding changed or expired')

    def preflight(self):
        self.live(); self.app = product(self.plan)
        current_toolchain = toolchain(self.plan, self.environment)
        a = self.admission
        qt_mode = 'recorder' in self.plan
        scope = 'H06_QUICKTIME_FIRST_CELL' if qt_mode else 'H06_PHYSICAL_LAUNCH'
        t.require(a['state'] == 'NATIVE_ADMITTED' and a['scope'] == scope
                  and a['reviewer'] == REVIEWER and a['planSHA256'] == t.sha(self.plan_raw),
                  'native launch not separately reviewed')
        if qt_mode:
            qualified = quicktime_session.preparation(self.plan, a)
        else:
            qualified = t.load(setup.read(reference(a['adapterQualification'])))
            t.require(qualified['state'] == 'PHYSICAL_ADAPTER_QUALIFIED'
                      and qualified['device'] == self.remote.identifier
                      and qualified['helpers'] == self.plan['helpers']
                      and qualified['toolchain'] == current_toolchain, 'physical adapter qualification missing or stale')
        self.server_raw = launch_readiness(self.directory,self.readiness_raw,self.plan_raw,self.admission_raw,time.time())
        self.page_identity = session.page_health(self.directory,self.server_raw,self.cutoffs['launchUntil'],self.folder/'page-before')
        t.save(self.folder/'readiness-consumed.json',t.encode(dict(sha256=t.sha(self.readiness_raw),at=time.time())))
        setup.command(['/usr/bin/codesign','--verify','--deep','--strict',str(self.app)],
            self.folder,'signature',self.cutoffs['launchUntil'])
        out = self.folder/'backend-preflight'; out.mkdir(); session.backend.transport.preflight(out)
        self.live()
        details,_ = self.observed.command(['device','info','details'],'startup-device')
        hardware,properties = details['result']['hardwareProperties'],details['result']['deviceProperties']
        t.require(hardware['reality'] == 'physical' and hardware['deviceType'] == 'iPad'
                  and hardware['udid'] == self.plan['udid'] and properties['developerModeStatus'] == 'enabled'
                  and properties['ddiServicesAvailable'] is True, 'physical iPad unavailable')
        t.require(qualified['hardware'] == dict(udid=hardware['udid'], os=properties['osVersionNumber'],
                  build=properties['osBuildUpdate']), 'physical adapter OS qualification differs')
        raw,_ = self.observed.command(['device','info','lockState'],'startup-lock')
        t.require(raw['result']['passcodeRequired'] is False and raw['result']['unlockedSinceBoot'] is True, 'physical iPad locked')
        if qt_mode:
            observed = a['recorderObservation']
            t.require(set(observed) == {'inventory', 'pid', 'initialAX', 'toolCallID', 'originalAudio'},
                      'QuickTime initial observation incomplete')
            self.quicktime = quicktime.Recorder(self.folder/'quicktime', run_id=self.run_id,
                device=self.remote.identifier, inventory=observed['inventory'], pid=observed['pid'],
                decoder=self.plan['decoder']['binary'], decoder_source_sha256=self.plan['decoder']['source']['sha256'],
                record_deadline=self.cutoffs['recordUntil'], evidence_deadline=self.cutoffs['stopUntil'],
                restore_deadline=self.cutoffs['executionUntil'], original_audio=observed['originalAudio'],
                developer_directory=current_toolchain['developer'],
                initial_ax=setup.read(reference(observed['initialAX']), t.MAX_CONTEXT_BYTES),
                initial_tool_call_id=observed['toolCallID'])
            t.require(self.quicktime.binding['device']['udid'] == self.plan['udid'], 'QuickTime iPad differs')
        self.absence('before-install'); self.absence_proved = True

    def absence(self, label):
        raw,_ = self.observed.command(['device','info','apps','--bundle-id',BUNDLE],label)
        result = raw['result']
        t.require(result.get('deviceIdentifier') == self.remote.identifier
                  and result.get('matchingBundleIdentifier') == BUNDLE and result.get('apps') == [],
                  'task bundle present or inventory ambiguous')

    def pull(self, suffix):
        source = 'Documents/'+self.run_id+suffix
        while time.time() < self.cutoffs['launchUntil']:
            self.live(); self.sequence += 1; label = f'startup-pull-{self.sequence:05d}'
            target = self.folder/(label+'.json')
            result,receipt = self.observed.pull(BUNDLE,source,target,label,self.cutoffs['launchUntil'],check=False)
            if t.transferred(result,receipt,device=self.remote.identifier,bundle=BUNDLE,source=source,
                destination=target,deadline=self.cutoffs['launchUntil'],optional=True):
                raw = setup.read(target); t.save(self.folder/('native'+suffix),raw); return raw
            self.wait()
        raise ValueError('startup receipt missing before original cutoff')

    def construct(self, identity, code, startup):
        self.live(); product(self.plan)
        process,_ = self.observed.command(['device','info','processes'],'startup-process')
        setup.device_process(process,identity,self.plan['product'],self.app.name)
        current_page = session.page_health(self.directory,self.server_raw,self.cutoffs['launchUntil'],self.folder/'page-after')
        t.require(current_page == self.page_identity, 'operator process changed during startup')
        remote = media.ExecutionDevice(self.remote,execution_until=self.cutoffs['executionUntil'],deadline=self.cutoffs['deadline'])
        channel = t.Channel(remote,BUNDLE,self.folder/'channel',identity,deadline=self.cutoffs['deadline'])
        expected = dict(device=self.remote.identifier,udid=self.plan['udid'],run_id=self.run_id,
            process_id=identity['processID'],profile=self.plan['profile'],setup_profile=self.plan['setupProfile'],
            product=self.plan['product'],startup_nonce=self.startup_nonce)
        host = setup.HostSetup(channel,self.app,code,expected,startup_raw=startup)
        prompts = operator.Operator(self.directory,channel,server_raw=self.server_raw)
        if 'recorder' in self.plan:
            movie = quicktime_session.Movie(remote, self.quicktime, run_id=identity['runID'])
        else:
            movie = media.Movie(remote,self.folder/'movie',record_until=self.cutoffs['recordUntil'],
                stop_until=self.cutoffs['stopUntil'],environment=self.environment)
        capture = media.Media(host,self.folder/'media',binary=self.plan['decoder']['binary']['path'],
            source_sha256=self.plan['decoder']['source']['sha256'],binary_sha256=self.plan['decoder']['binary']['sha256'],
            nonce=self.display_nonce,movie=movie,wait=self.wait)
        result = session.Session(host,prompts,capture,backend_deadline=self.cutoffs['backendUntil'],
            maximum_attempts=self.plan['backend']['maximumAttempts'],poll_seconds=self.plan['backend']['pollSeconds'],wait=self.wait)
        t.save(self.folder/'construction.json',t.encode(dict(state='SESSION_BOUND',identity=identity,
            planSHA256=t.sha(self.plan_raw),admissionSHA256=t.sha(self.admission_raw),
            artifacts={p.name:setup.file_sha(p) for p in self.folder.iterdir() if p.is_file()},
            nativeEvidence=str(self.remote.output),releaseAcceptance=False,gatesClosed=[])))
        return result

    def before_launch_cleanup(self):
        """No foreground launch or operator gesture was admitted in this branch."""
        t.require(self.absence_proved and self.install_attempted and not self.launch_attempted,
                  'prelaunch cleanup authority missing')
        deadline = self.cutoffs['deadline']; self.remote.quiescent(deadline)
        observed = cleanup.ObservedDevice(self.remote,self.folder,deadline,time.time())
        raw,_ = observed.command(['device','info','processes'],'prelaunch-cleanup-processes')
        rows = raw['result'].get('runningProcesses')
        require_no_task_process(rows,self.app,self.plan['product'])
        # The install may have failed after placing the bundle. Observe first.
        raw,_ = observed.command(['device','info','apps','--bundle-id',BUNDLE],'prelaunch-cleanup-apps')
        result = raw['result']
        t.require(result.get('deviceIdentifier') == self.remote.identifier
                  and result.get('matchingBundleIdentifier') == BUNDLE and isinstance(result.get('apps'),list),
                  'ambiguous prelaunch cleanup inventory')
        if result['apps']:
            observed.command(['device','uninstall','app',BUNDLE],'prelaunch-uninstall')
        self.observed = observed
        self.absence('prelaunch-absence')
        return 'PASS'

    def launch(self):
        t.require(not self.used, 'launch already consumed'); self.used = True
        try:
            self.preflight(); self.live(); product(self.plan); self.install_attempted = True
            self.observed.command(['device','install','app',str(self.app)],'install')
            self.live(); product(self.plan)
            env = dict(DD_PROBE_CAPTURE_JSONL='1',DD_PROBE_PHYSICAL_OPERATION_CAPTURE='1',
                DD_PROBE_PHYSICAL_OPERATION_EXECUTION='1',MULTISCENE_CODE_IDENTITY_RUN_ID=self.run_id,
                MULTISCENE_CODE_IDENTITY_REVISION=SDK,DD_PROBE_OPERATION_STARTUP_NONCE=self.startup_nonce,
                DD_PROBE_OPERATION_DISPLAY_NONCE=self.display_nonce,
                DD_PROBE_OPERATION_DISPLAY_SOURCE_SHA256=self.plan['decoder']['source']['sha256'],
                DD_PROBE_OPERATION_DISPLAY_BINARY_SHA256=self.plan['decoder']['binary']['sha256'],
                DD_PROBE_PHYSICAL_OPERATION_CAPTURE_DEADLINE=str(self.cutoffs['deadline']))
            args = ['device','process','launch','--environment-variables',t.encode(env).decode(),BUNDLE,'--',
                '--probe-scenario',SCENARIO,'--probe-run-id',self.run_id,'--probe-run-mode','clean']
            t.save(self.folder/'launch-inputs.json',t.encode(dict(arguments=args,environment=env)))
            self.launch_attempted = True
            raw,_ = self.observed.command(args,'launch')
            pid = raw['result']['process']['processIdentifier']
            t.require(type(pid) is int and pid > 0, 'actual launched PID missing')
            code = self.pull('.installed-code.json'); startup = self.pull('.startup-freshness.json')
            installed_code.validate(t.load(code),self.app,self.run_id,SDK,pid)
            challenge = self.pull('.operations-challenge.json')
            identity = t.challenge(challenge,run_id=self.run_id,process_id=pid,profile=self.plan['profile'],
                installed_code=code,setup_profile=self.plan['setupProfile'])
            setup.startup_freshness(startup,identity,BUNDLE,self.startup_nonce)
            self.bound_session = self.construct(identity,code,startup)
            return self.bound_session
        except BaseException as error:
            verdict = 'UNTOUCHED' if not self.install_attempted else 'BLOCKED'
            cleanup_error = None
            if self.install_attempted and not self.launch_attempted:
                try: verdict = self.before_launch_cleanup()
                except BaseException as failure: cleanup_error = str(failure)
            t.save(self.folder/'failure.json',t.encode(dict(state='INVALID',reason=str(error),
                installAttempted=self.install_attempted,launchAttempted=self.launch_attempted,
                cleanup=verdict,cleanupError=cleanup_error,appPreserved=self.launch_attempted,
                sdkRegression=False,releaseAcceptance=False,gatesClosed=[])))
            raise
