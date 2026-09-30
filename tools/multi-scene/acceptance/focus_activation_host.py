"""H04 physical transfers and task-only cleanup through the existing Device adapter.

The caller owns reviewed source/build/signature, device readiness, installation,
launch and backend collection. This class never drives UI or qualifies a gate.
"""
from pathlib import Path
import time
import uuid

import focus_activation_recorder as recorder
import focus_activation_transport as protocol
import installed_code
from operation_cleanup import ObservedDevice
import operation_setup as setup
import operation_transport as t


def freshness(raw, expected):
    value=t.load(raw)
    fields={'schemaVersion','runID','scenarioID','sourceRevision','processID','bundleIdentifier','nonce',
            'boundary','paths','releaseAcceptance'}
    t.require(isinstance(value,dict) and set(value)==fields, 'focus startup receipt shape differs')
    t.require(type(value['schemaVersion']) is int and value['schemaVersion']==1
              and value['runID']==expected['run_id'] and value['scenarioID']==protocol.SCENARIO
              and value['sourceRevision']==expected['revision'] and type(value['processID']) is int
              and value['processID']==expected['process_id'] and value['bundleIdentifier']==expected['bundle']
              and value['nonce']==expected['startup_nonce'] and str(uuid.UUID(value['nonce']))==value['nonce']
              and value['boundary']=='before-sdk-and-probe-writer' and value['releaseAcceptance'] is False,
              'focus startup identity or boundary differs')
    paths=value['paths']
    t.require(isinstance(paths,dict) and set(paths)==setup.STARTUP_ABSENT_PATHS|{'Documents'}
              and paths['Documents'] in ['ABSENT','EMPTY']
              and all(paths[p]=='ABSENT' for p in setup.STARTUP_ABSENT_PATHS), 'stale focus startup artifacts')
    return value


class Session:
    """One bootstrap, ARM and STOP. Failed capture can still permit safe cleanup."""
    maximum_polls=128

    def __init__(self,remote,app,output,*,run_id,process_id,revision,startup_nonce,execution_ms,cleanup_ms,
                 device_udid,wait=lambda:time.sleep(1)):
        self.remote=remote;self.app=Path(app);self.output=Path(output);self.created=time.time();self.wait=wait
        t.require(not self.output.exists() and not any(p.is_symlink() for p in [self.output,*self.output.parents]),
                  'focus session output reused or redirected')
        self.product=installed_code.inventory(self.app)
        self.expected=dict(run_id=run_id,process_id=process_id,revision=revision,startup_nonce=startup_nonce,
                           execution_ms=execution_ms,cleanup_ms=cleanup_ms,device=remote.identifier,
                           device_udid=device_udid,bundle=self.product['bundleIdentifier'],app=str(self.app))
        t.require(type(execution_ms) is int and type(cleanup_ms) is int
                  and self.created*1000 < execution_ms < cleanup_ms <= self.created*1000+10_800_000,
                  'focus session cutoffs are expired or unbounded')
        self.frozen=t.encode(self.expected);self.output.mkdir();t.save(self.output/'definition.json',self.frozen)
        self.observed={}
        for name,deadline in [('execution',execution_ms/1000),('cleanup',cleanup_ms/1000)]:
            folder=self.output/('io-'+name);folder.mkdir()
            # This generic receipt verifier uses a lower time boundary, not a human-release attestation.
            self.observed[name]=ObservedDevice(remote,folder,deadline,self.created)
        self.used=set();self.identity=None;self.process=None;self.failed=False;self.previous=b'';self.arm_reply=None;self.bootstrap_raw=None;self.replies={}

    def live(self,phase):
        t.require(setup.read(self.output/'definition.json')==self.frozen and t.encode(self.expected)==self.frozen,
                  'focus frozen context changed')
        t.require(self.remote.identifier==self.expected['device'], 'focus physical device changed')
        deadline=self.expected['execution_ms' if phase=='execution' else 'cleanup_ms']/1000
        t.require(time.time()<deadline, 'focus original cutoff expired')
        return deadline

    def failure(self,folder,error):
        self.failed=True
        t.save(folder/'failure.json',t.encode(dict(state='INVALID',error_type=type(error).__name__,reason=str(error),
              at=time.time(),overall='UNQUALIFIED',teardown_authorized=False)))

    def folder(self,name):
        t.require(name not in self.used, 'focus operation already consumed')
        self.used.add(name);folder=self.output/name;folder.mkdir();return folder

    def transfer(self,phase,folder,source,destination,label,*,download):
        deadline=self.live(phase);observed=self.observed[phase]
        method=observed.pull if download else observed.push
        result,receipt=method(self.expected['bundle'],source,destination,label,deadline,
                              **({'check':False} if download else {}))
        self.live(phase)
        return t.transferred(result,receipt,device=self.expected['device'],bundle=self.expected['bundle'],
            source=source,destination=destination,deadline=deadline,optional=download)

    def download(self,phase,folder,source,name,*,maximum=t.MAX_CONTEXT_BYTES):
        for index in range(self.maximum_polls):
            destination=folder/f'{name}-{index:04d}.raw'
            if self.transfer(phase,folder,source,destination,name,download=True):
                raw=setup.read(destination,maximum=maximum);self.live(phase);return raw
            self.wait()
        raise ValueError('focus publication poll bound exhausted')

    def current_process(self,phase,label):
        self.live(phase);raw,_=self.observed[phase].command(['device','info','processes'],label)
        process=setup.device_process(raw,self.identity,self.product,self.app.name)
        if self.process is not None:t.require(process==self.process, 'original focus process was replaced')
        self.live(phase);return process

    def bootstrap(self):
        folder=self.folder('bootstrap')
        try:
            self.live('execution');prefix='Documents/'+self.expected['run_id']
            installed=self.download('execution',folder,prefix+'.installed-code.json','installed')
            startup=self.download('execution',folder,prefix+'.startup-freshness.json','startup')
            challenge=self.download('execution',folder,prefix+'.focus-channel/challenge.json','challenge')
            self.product=installed_code.validate(t.load(installed,maximum=t.MAX_CONTEXT_BYTES),self.app,
                self.expected['run_id'],self.expected['revision'],self.expected['process_id'])
            t.require(self.product['bundleIdentifier']==self.expected['bundle'], 'focus installed bundle changed')
            freshness(startup,self.expected)
            self.identity=protocol.challenge(challenge,installed,run_id=self.expected['run_id'],
                process_id=self.expected['process_id'],revision=self.expected['revision'],
                execution_ms=self.expected['execution_ms'],cleanup_ms=self.expected['cleanup_ms'])
            self.process=self.current_process('execution','bootstrap-process')
            for name,raw in [('installed.json',installed),('startup.json',startup),('challenge.json',challenge)]:t.save(folder/name,raw)
            result=dict(state='BOUND_PHYSICAL_PROCESS_AND_STORAGE',identity=self.identity,process=self.process,
                        product=self.product,artifacts={n:setup.file_sha(folder/n) for n in ['installed.json','startup.json','challenge.json']},
                        at=time.time(),overall='UNQUALIFIED',teardown_authorized=False)
            self.bootstrap_raw=t.encode(result)
            t.save(folder/'result.json',self.bootstrap_raw);self.live('execution');return result
        except Exception as error:self.failure(folder,error);raise

    def bound(self,phase):
        self.live(phase);t.require(self.identity is not None and self.process is not None,'focus bootstrap missing')
        folder=self.output/'bootstrap';raw=setup.read(folder/'result.json')
        t.require(raw==self.bootstrap_raw,'focus bootstrap record changed');saved=t.load(raw)
        t.require(saved['identity']==self.identity and saved['process']==self.process,
                  'focus bootstrap result replaced')
        t.require(all(setup.file_sha(folder/name)==sha for name,sha in saved['artifacts'].items()),
                  'focus bootstrap bytes changed')
        product=installed_code.validate(t.load(setup.read(folder/'installed.json')),self.app,self.expected['run_id'],
                                       self.expected['revision'],self.expected['process_id'])
        t.require(product==self.product, 'focus signed product changed')

    def exchange(self,operation):
        phase='execution' if operation=='arm' else 'cleanup';folder=self.folder(operation)
        try:
            self.bound(phase)
            if operation=='arm':t.require(not self.failed and 'stop' not in self.used,'failed or stopped focus session cannot arm')
            self.current_process(phase,operation+'-process-before')
            sent=protocol.request(self.identity,operation);sha=t.sha(sent);t.save(folder/'request.json',sent)
            t.save(folder/'marker',sha.encode());prefix='Documents/'+self.identity['runID']+'.focus-channel/'
            self.transfer(phase,folder,folder/'request.json',prefix+sha+'.json',operation+'-payload',download=False)
            self.transfer(phase,folder,folder/'marker',prefix+operation+'.request',operation+'-publish',download=False)
            raw=self.download(phase,folder,prefix+sha+'.reply.json',operation+'-reply')
            t.save(folder/'reply.json',raw)
            result=protocol.reply(raw,sent,received_at_ms=int(time.time()*1000))
            self.current_process(phase,operation+'-process-after')
            if operation=='stop' and self.arm_reply is not None:
                _,before=protocol.opaque(t.load(self.arm_reply,maximum=t.MAX_CONTEXT_BYTES)['observation']['after'])
                _,after=protocol.opaque(t.load(raw,maximum=t.MAX_CONTEXT_BYTES)['observation']['after'])
                original=before['input'][0];actual=next(i for i in after['input'] if i['logicalSceneID']=='scene-A')
                t.require(all(original[k]==actual[k] for k in ['nativeSceneID','generation','windowIdentity','rootIdentity','observerIdentity']),
                          'focus original A owner changed before stop')
            self.live(phase);t.save(folder/'result.json',t.encode(result))
            self.replies[operation]=(sent,raw)
            if operation=='arm':self.arm_reply=raw
            return result
        except Exception as error:self.failure(folder,error);raise

    def collect(self):
        folder=self.folder('collection')
        try:
            self.bound('execution');t.require(self.arm_reply is not None and not self.failed,'unarmed or failed focus collection')
            for index in range(self.maximum_polls):
                raw=self.download('execution',folder,recorder.SOURCE,f'recorder-{index:04d}',maximum=recorder.MAX_BYTES)
                t.require(raw.startswith(self.previous),'native focus recorder changed or truncated');self.previous=raw
                try:result=recorder.validate(raw,self.expected['run_id'])
                except recorder.Pending:self.wait();continue
                t.save(folder/'collected.jsonl',raw)
                recorder.seal(folder/'collected.jsonl',folder/'sealed',self.expected['run_id'])
                t.save(folder/'result.json',t.encode(result));return folder/'sealed'
            raise ValueError('focus recorder poll bound exhausted')
        except Exception as error:self.failure(folder,error);raise

    def process_absence(self,label):
        raw,_=self.observed['cleanup'].command(['device','info','processes'],label)
        rows=raw.get('result',{}).get('runningProcesses')
        t.require(isinstance(rows,list) and all(isinstance(row,dict) and type(row.get('processIdentifier')) is int
                  and row['processIdentifier']>0 and isinstance(row.get('executable'),str) and row['executable'] for row in rows),
                  'focus process absence inventory malformed')
        t.require(all(row['processIdentifier']!=self.process['processID'] and row['executable']!=self.process['executable'] for row in rows),
                  'focus task process remains or restarted')

    def cleanup(self):
        folder=self.folder('cleanup')
        try:
            self.bound('cleanup');self.exchange('stop')
            raw=self.download('cleanup',folder,recorder.SOURCE,'final-recorder',maximum=recorder.MAX_BYTES)
            # Preserve full bytes even when a failed scenario cannot pass the semantic oracle.
            t.save(folder/'final-recorder.jsonl',raw)
            t.require(raw.startswith(self.previous),'final focus recorder replaced or truncated')
            try:status=recorder.validate(raw,self.expected['run_id'],previous=self.previous)
            except Exception as error:status=dict(state='UNQUALIFIED',error_type=type(error).__name__,reason=str(error))
            t.save(folder/'final-recorder-status.json',t.encode(status))
            observed=self.observed['cleanup'];device,_=observed.command(['device','info','details'],'cleanup-device')
            details=device['result'];h=details['hardwareProperties'];properties=details['deviceProperties']
            t.require(h.get('reality')=='physical' and h.get('deviceType')=='iPad' and h.get('udid')==self.expected['device_udid']
                      and int(properties['osVersionNumber'].split('.')[0])>=27 and properties.get('osBuildUpdate'),
                      'cleanup physical device or supported OS differs')
            deadline=self.live('cleanup');self.remote.quiescent(deadline)
            quiet_raw=setup.read(self.remote.output/'before-cleanup-quiescence.json');t.save(folder/'host-quiescence.json',quiet_raw)
            quiet=t.load(quiet_raw)
            t.require(quiet['state']=='PASS' and quiet['remaining']==[] and quiet['groups']==self.remote.groups
                      and quiet['deadline']==deadline and self.created<=quiet['at']<deadline,'focus host workers not quiescent')
            self.current_process('cleanup','cleanup-process-final');self.live('cleanup')
            sent,returned=self.replies['stop']
            t.require(setup.read(self.output/'stop/request.json')==sent and setup.read(self.output/'stop/reply.json')==returned,
                      'focus stopped-idle proof changed before teardown')
            protocol.reply(returned,sent,received_at_ms=int(time.time()*1000))
            t.save(folder/'teardown-admission.json',t.encode(dict(process=self.process,bundle=self.expected['bundle'],
                idle_reply_sha256=setup.file_sha(self.output/'stop/reply.json'),at=time.time(),deadline=deadline,
                final_recorder_sha256=t.sha(raw),scenario='UNCHANGED',evidence='UNCHANGED')))
            removed,_=observed.command(['device','process','terminate','--pid',str(self.process['processID'])],'cleanup-terminate')
            t.require(removed['result'].get('deviceIdentifier')==self.expected['device'] and removed['result'].get('process')==
                      dict(processIdentifier=self.process['processID'],executable=self.process['executable']),'focus termination identity differs')
            self.process_absence('cleanup-process-absence')
            removed,_=observed.command(['device','uninstall','app',self.expected['bundle']],'cleanup-uninstall')
            t.require(removed['result'].get('deviceIdentifier')==self.expected['device'] and
                      removed['result'].get('uninstalledApplications')==[dict(bundleID=self.expected['bundle'])],'focus uninstall identity differs')
            apps,_=observed.command(['device','info','apps','--bundle-id',self.expected['bundle']],'cleanup-app-absence');value=apps['result']
            t.require(value.get('deviceIdentifier')==self.expected['device'] and value.get('matchingBundleIdentifier')==self.expected['bundle']
                      and value.get('apps')==[],'focus task app absence unproved')
            self.process_absence('cleanup-process-final-absence');self.live('cleanup')
            result=dict(state='TASK_APP_REMOVED',appAbsence='PASS',processAbsence='PASS',containerAbsence='UNVERIFIED',
                        dataDisposition='OS_APP_UNINSTALL_CONTRACT',preSDKFreshness='PASS',
                        directlyObservedFilesystemAbsence=False,deviceOS=properties['osVersionNumber'],
                        deviceBuild=properties['osBuildUpdate'],scenario='UNCHANGED',evidence='UNCHANGED',
                        finalCaptureState=status['state'],releaseAcceptance=False,at=time.time(),deadline=deadline)
            t.save(folder/'result.json',t.encode(result));return result
        except Exception as error:self.failure(folder,error);raise
