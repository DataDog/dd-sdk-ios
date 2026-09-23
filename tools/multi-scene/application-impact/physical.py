#!/usr/bin/env python3
"""One bounded physical ABBA wave. Preparation never admits native execution."""
import argparse
import datetime
import fnmatch
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import sys
import time
import uuid
import build
from contract import require, scenario, compare_abba
from physical_contract import app_absence, display, ready_admission, returned
from trace_contract import SCHEMAS, inventory, measure
from notification import Notification
sys.path.append(str(Path(__file__).resolve().parents[1]/'acceptance'))
import installed_code

shared=build.shared


def save(path,value):shared.save(Path(path),value,exclusive=True)


def execute(argv,out,label,deadline,*,check=True):
    out=Path(out);require(time.time()<deadline,'command after deadline')
    require(not (out/(label+'.command.json')).exists() and not (out/(label+'.log')).exists(),'command output reused')
    start=time.time();save(out/(label+'.admission.json'),dict(argv=argv,started_at=start,deadline=deadline))
    with (out/(label+'.log')).open('xb') as stream:
        child=subprocess.Popen(argv,stdout=stream,stderr=subprocess.STDOUT,start_new_session=True,env=shared.environment())
        try:child.wait(timeout=max(0.001,deadline-time.time()))
        except subprocess.TimeoutExpired:
            os.killpg(child.pid,signal.SIGTERM)
            try:child.wait(timeout=3)
            except subprocess.TimeoutExpired:os.killpg(child.pid,signal.SIGKILL);child.wait(timeout=3)
    receipt=dict(argv=argv,started_at=start,finished_at=time.time(),returncode=child.returncode,deadline=deadline,
                 log_sha256=shared.sha(out/(label+'.log')))
    save(out/(label+'.command.json'),receipt)
    require(time.time()<deadline,'late command response')
    if check:require(child.returncode==0,label+' failed')
    return receipt


class Device:
    def __init__(self,identifier,out):self.identifier=identifier;self.out=Path(out)
    def command(self,args,label,deadline,*,check=True,seconds=15):
        raw=self.out/(label+'.raw.json');require(not raw.exists(),'raw response reused')
        limit=min(deadline,time.time()+seconds+3)
        require(len(args)>=3 and args[0]=='device','unsupported device command shape')
        # Launch treats everything after the bundle as app arguments, including option-looking values.
        argv=['xcrun','devicectl',*args[:3],'--device',self.identifier,'--timeout',str(min(seconds,max(1,int(limit-time.time())-1))), '--json-output',str(raw),*args[3:]]
        receipt=execute(argv,self.out,label,limit,check=check)
        result=shared.read(raw) if raw.exists() else None
        if check:require(result is not None,'missing actual response')
        return result,receipt
    def apps_absent(self,bundle,label,deadline):
        raw,_=self.command(['device','info','apps','--bundle-id',bundle],label,deadline)
        app_absence(raw,self.identifier,bundle);return raw
    def copy_from(self,bundle,source,destination,label,deadline):
        require(not Path(destination).exists(),'download target reused')
        return self.command(['device','copy','from','--domain-type','appDataContainer','--domain-identifier',bundle,
                             '--source',source,'--destination',str(destination)],label,deadline)
    def copy_to(self,bundle,source,destination,label,deadline):
        return self.command(['device','copy','to','--domain-type','appDataContainer','--domain-identifier',bundle,
                             '--source',str(source),'--destination',destination],label,deadline)


def device_inventory(device,udid,out,label,deadline):
    path=Path(out)/(label+'.raw.json')
    execute(['xcrun','devicectl','list','devices','--timeout','15','--json-output',str(path)],out,label,min(deadline,time.time()+18))
    raw=shared.read(path);require(raw.get('info',{}).get('outcome')=='success','device inventory failed')
    values=[d for d in raw.get('result',{}).get('devices',[]) if d.get('identifier')==device]
    require(len(values)==1,'physical device absent or duplicated');d=values[0];h=d.get('hardwareProperties',{});v=d.get('deviceProperties',{})
    require(h.get('reality')=='physical' and h.get('deviceType')=='iPhone' and h.get('udid')==udid,'wrong physical device')
    require(d.get('connectionProperties',{}).get('tunnelState')=='connected' and v.get('developerModeStatus')=='enabled'
            and v.get('ddiServicesAvailable') is True,'physical developer services unavailable')
    return dict(identifier=device,udid=udid,product_type=h['productType'],os_version=v['osVersionNumber'],os_build=v['osBuildUpdate'])


def require_quiet_host():
    rows=subprocess.check_output(['ps','-axo','pid=,command=']).decode().splitlines()
    competing=[row for row in rows if any(x in row for x in ['/usr/bin/xcodebuild build','/usr/bin/xcodebuild test','xctrace record'])
               and 'application-impact/physical.py' not in row and 'python3 -B - <<' not in row]
    require(not competing,'competing build, test or profile workload')


def prepare(root,build_root,profile,certificate,device,udid):
    root=Path(root).resolve();require(not root.exists(),'preparation output consumed');root.mkdir()
    build_root=Path(build_root).resolve();plan=build.verify(build_root,repository_helpers=False);owner=shared.read(build.OWNER)
    require(owner['native_admitted'] is False,'unexpected native admission')
    runtime_helpers={n:shared.sha(shared.REPO/n) for n in build.HELPERS}
    deltas={n:dict(build=v,runtime=runtime_helpers[n]) for n,v in plan['helpers'].items() if runtime_helpers.get(n)!=v}
    require(set(runtime_helpers)==set(plan['helpers']) and set(deltas)<=set('tools/multi-scene/application-impact/'+n for n in ['physical.py','build.py','test_physical.py']), 'unreviewed runtime helper delta')
    shared.freeze_helpers(root,runtime_helpers)
    before=build.protected();deadline=time.time()+300
    hardware=device_inventory(device,udid,root,'physical-device',deadline)
    profile=Path(profile).resolve();r=subprocess.run(['security','cms','-D','-i',str(profile)],capture_output=True,check=True,timeout=15)
    provision=plistlib.loads(r.stdout);entitlements=provision['Entitlements'];team=entitlements['com.apple.developer.team-identifier']
    require(udid in provision.get('ProvisionedDevices',[]) and entitlements.get('get-task-allow') is True,'profile does not grant this development device')
    require(provision['ExpirationDate'].replace(tzinfo=datetime.timezone.utc).timestamp()>time.time(),'profile expired')
    require(certificate in {hashlib.sha1(c).hexdigest().upper() for c in provision['DeveloperCertificates']},'certificate not granted by profile')
    record=dict(build_root=str(build_root),build_plan_sha256=shared.sha(build_root/'plan.json'),definition=owner,
                device=device,udid=udid,protected=before,profile_sha256=shared.sha(profile),certificate=certificate,team=team,
                products={},native_admitted=False,toolchain=plan['toolchain'],hardware=hardware,
                runtime_helpers=runtime_helpers,build_helper_deltas=deltas,compiler_receipts={})
    for arm in ['A','B']:
        receipt=build_root/(arm+'-device')/'build-result.json';built=shared.read(receipt)
        record['compiler_receipts'][arm+'-device']=shared.sha(receipt)
        require(built['state']=='UNSIGNED_DEVICE_BUILD_QUALIFIED','unqualified compiler product')
        for framework in ['UIKit','SwiftUI']:
            item=built['products'][framework];source=Path(item['path']);bundle=item['bundle'];key=arm+'-'+framework
            require(shared.product(source,bundle=bundle)==item['product'],'unsigned product changed')
            require(fnmatch.fnmatchcase(team+'.'+bundle,entitlements['application-identifier']),'profile does not grant bundle')
            folder=root/key;folder.mkdir();app=folder/source.name;shutil.copytree(source,app)
            shutil.copy2(profile,app/'embedded.mobileprovision')
            entitlement_path=folder/'entitlements.plist'
            entitlement_path.write_bytes(plistlib.dumps({'application-identifier':team+'.'+bundle,'com.apple.developer.team-identifier':team,'get-task-allow':True}))
            binaries=installed_code.inventory(app)['binaries']
            main=plistlib.loads((app/'Info.plist').read_bytes())['CFBundleExecutable']
            require(set(binaries)=={main},'unexpected embedded code in static SDK fixture')
            execute(['codesign','--force','--sign',certificate,'--entitlements',str(entitlement_path),str(app)],folder,'sign',deadline)
            execute(['codesign','--verify','--deep','--strict','--verbose=2',str(app)],folder,'verify-signature',deadline)
            execute(['codesign','--display','--extract-certificates='+str(folder/'certificate-'),str(app)],folder,'certificate',deadline)
            require(hashlib.sha1((folder/'certificate-0').read_bytes()).hexdigest().upper()==certificate,'signature certificate changed')
            record['products'][key]=dict(path=str(app),bundle=bundle,source=built['source'],framework=framework,
                fixture=plan['arms'][arm+'-device']['fixture'],product=shared.product(app,bundle=bundle),installed=installed_code.inventory(app))
    require(build.protected()==before,'protected paths changed')
    save(root/'signed-plan.json',record)
    print(json.dumps(dict(state='SIGNED_PRODUCTS_PREPARED',root=str(root),native_admitted=False)))


def verify(root):
    root=Path(root);plan=shared.read(root/'signed-plan.json');build.verify(plan['build_root'],repository_helpers=False)
    require(shared.tree(root/'helpers')==plan['runtime_helpers']
            and all(shared.sha(shared.REPO/n)==v for n,v in plan['runtime_helpers'].items()),'runtime helper changed')
    require(all(shared.sha(Path(plan['build_root'])/key/'build-result.json')==v for key,v in plan['compiler_receipts'].items()),'compiler receipt changed')
    require(shared.sha(Path(plan['build_root'])/'plan.json')==plan['build_plan_sha256'],'build plan changed')
    require(build.protected()==plan['protected'],'protected paths changed')
    require(shared.capture(['xcodebuild','-version']).stdout.decode().strip()==plan['toolchain'],'toolchain changed')
    for item in plan['products'].values():
        require(shared.product(Path(item['path']),bundle=item['bundle'])==item['product'],'signed product changed')
    return plan


def stop_recorder(proc,deadline):
    if proc is None:return
    if proc.poll() is None:
        os.killpg(proc.pid,signal.SIGINT)
        try:proc.wait(timeout=max(.01,deadline-time.time()))
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid,signal.SIGKILL);proc.wait(timeout=3);raise


def cleanup(device,bundle,pid,owned,proc,out,deadline,notification_error=None):
    errors=[] if notification_error is None else [notification_error]
    checks={} if notification_error is None else {'notification':'INVALID'}
    def attempt(name,operation):
        try:operation();checks[name]='PASS'
        except Exception as error:checks[name]='INVALID';errors.append(name+': '+str(error))
    attempt('recorder',lambda:stop_recorder(proc,min(deadline,time.time()+25)))
    if owned:attempt('uninstall',lambda:device.command(['device','uninstall','app',bundle],'cleanup-uninstall',deadline,seconds=30))
    attempt('app_absence',lambda:device.apps_absent(bundle,'cleanup-apps',deadline))
    def processes():
        raw,_=device.command(['device','info','processes'],'cleanup-processes',deadline)
        data=returned(raw,device.identifier,'devicectl.device.info.processes')
        values=data.get('runningProcesses');require(isinstance(values,list),'missing cleanup process inventory')
        require(not any(r.get('processIdentifier')==pid for r in values) if pid is not None else True,'task process retained')
    attempt('process_absence',processes)
    # Uninstall success plus a complete empty bundle inventory is the physical app/data removal contract.
    # The generic data-domain error alone never proves absence.
    attempt('container_query',lambda:device.command(['device','info','files','--domain-type','appDataContainer','--domain-identifier',bundle],
                                                   'cleanup-container-query',deadline,check=False))
    if time.time()>=deadline:errors.append('cleanup deadline exceeded')
    verdict=dict(state='INVALID' if errors else 'PASS',checks=checks,errors=errors,deadline=deadline,finished_at=time.time())
    save(Path(out)/'cleanup.json',verdict);return verdict


def publish_admission(device,bundle,identity,out,deadline):
    require(time.time()<deadline,'recorder admission late')
    out=Path(out);admission=dict(state='TRACE_READY',**identity);ready_admission(admission,identity)
    payload=out/'native-admission.json';save(payload,admission)
    device.copy_to(bundle,payload,'Documents/impact-admission-'+identity['run_id']+'.json','publish-admission',deadline)
    require(time.time()<deadline,'recorder admission late')
    marker=out/'native-ready'
    with marker.open('x') as stream:stream.write(identity['nonce'])
    device.copy_to(bundle,marker,'Documents/impact-ready-'+identity['run_id'],'publish-marker',deadline)
    require(time.time()<deadline,'recorder marker late')


def export_trace(out,trace,deadline):
    out=Path(out);toc=out/'trace-toc.xml'
    execute(['xcrun','xctrace','export','--input',str(trace),'--toc','--output',str(toc)],out,'trace-inventory',deadline)
    inventory(toc.read_bytes());exports={}
    for name in SCHEMAS:
        path=out/(name+'.xml');xpath='/trace-toc/run[@number="1"]/data/table[@schema="'+name+'"]'
        execute(['xcrun','xctrace','export','--input',str(trace),'--xpath',xpath,'--output',str(path)],out,'export-'+name,deadline)
        exports[name]=path.read_bytes()
    return toc.read_bytes(),exports


def cell(root,index):
    root=Path(root);plan=verify(root);matrix=plan['definition']['matrix'];require(0<=index<len(matrix),'unknown cell')
    for i in range(index):require(shared.read(root/'cells'/str(i)/'summary.json')['state']=='PASS','prior cell did not qualify')
    if index>=4:require(shared.read(root/'UIKit-comparison.json')['state']=='PASS','prior workload regressed')
    stage=root/'stage.json'
    if index==0:
        started=time.time();save(stage,dict(started_at=started,deadline=started+plan['definition']['budgets_seconds']['physical_stage'],signed_plan_sha256=shared.sha(root/'signed-plan.json')))
    stage=shared.read(stage);require(stage['signed_plan_sha256']==shared.sha(root/'signed-plan.json'),'stage plan changed')
    require(time.time()+540<stage['deadline'],'insufficient fixed stage budget')
    out=root/'cells'/str(index);out.mkdir(parents=True,exist_ok=False)
    item=plan['products'][matrix[index]['arm']+'-'+matrix[index]['workload']];bundle=item['bundle'];device=Device(plan['device'],out)
    identity=dict(run_id=str(uuid.uuid4()),nonce=str(uuid.uuid4()),source=item['source'],fixture=item['fixture'],framework=item['framework'])
    started=time.time();deadline=started+plan['definition']['budgets_seconds']['native_per_cell']
    save(out/'admission.json',dict(index=index,identity=identity,started_at=started,deadline=deadline,signed_plan_sha256=shared.sha(root/'signed-plan.json')))
    owned=False;pid=None;recorder=None;notice=None;record_stream=None;scenario_state='INVALID';evidence='INVALID';details={};native=None
    try:
        require_quiet_host()
        require(device_inventory(plan['device'],plan['udid'],out,'physical-device',deadline)==plan['hardware'],'physical environment changed')
        raw,_=device.command(['device','info','lockState'],'lock',deadline)
        lock=returned(raw,plan['device'],'devicectl.device.info.lockState')
        require(lock.get('passcodeRequired') is False and lock.get('unlockedSinceBoot') is True,'physical device locked')
        device.apps_absent(bundle,'preinstall-apps',deadline)
        # This query is retained even when CoreDevice reports its generic unavailable-container error.
        device.command(['device','info','files','--domain-type','appDataContainer','--domain-identifier',bundle], 'preinstall-container-query',deadline,check=False)
        owned=True
        device.command(['device','install','app',item['path']],'install',deadline,seconds=30)
        raw,_=device.command(['device','info','files','--domain-type','appDataContainer','--domain-identifier',bundle,'--subdirectory','Documents'], 'fresh-documents',deadline)
        data=returned(raw,plan['device'],'devicectl.device.info.files')
        require(data.get('files')==[],'fresh Documents inventory is not empty or unsupported')
        environment={'IMPACT_RUN_ID':identity['run_id'],'IMPACT_NONCE':identity['nonce'],
            'MULTISCENE_CODE_IDENTITY_RUN_ID':identity['run_id'],'MULTISCENE_CODE_IDENTITY_REVISION':identity['source']}
        raw,_=device.command(['device','process','launch','--environment-variables',json.dumps(environment),bundle],'launch',deadline)
        launched=returned(raw,plan['device'],'devicectl.device.process.launch');pid=launched.get('process',{}).get('processIdentifier')
        require(type(pid) is int and pid>0,'missing launched process identity');identity['pid']=pid
        ready_deadline=min(deadline-180,time.time()+50)
        require(time.time()<ready_deadline,'insufficient time for full workload and recorder stop')
        receipt=out/'installed-code.json'
        copied=False
        for attempt in range(5):
            path=out/('installed-code-attempt-'+str(attempt)+'.json')
            try:
                device.copy_from(bundle,'Documents/'+identity['run_id']+'.installed-code.json',path,'installed-code-'+str(attempt),ready_deadline)
                shutil.copy2(path,receipt);copied=True;break
            except Exception:
                if time.time()+1>=ready_deadline:raise
                time.sleep(1)
        require(copied,'pre-SDK installed-code receipt not published')
        verified=installed_code.validate(installed_code.read_receipt(receipt),item['path'],identity['run_id'],identity['source'],pid)
        save(out/'installed-code-verdict.json',verified)
        before,_=device.command(['device','info','displays'],'display-before',ready_deadline);display(before,plan['device'])
        notification_name='com.datadoghq.exp224.recorder.'+identity['run_id'];notice=Notification(notification_name)
        options=out/'recording-options.json';save(options,{'Hangs':{'detectPriorityInversions':False,'hangsThreshold':250},'Points of Interest':{'excludeOSLogs':False}})
        trace=out/'capture.trace';argv=['xcrun','xctrace','record','--device',plan['udid'],'--attach',str(pid),
            '--instrument','Core Animation FPS','--instrument','Hitches','--instrument','Hangs','--instrument','Points of Interest',
            '--time-limit',str(max(1,int(deadline-time.time())))+'s','--output',str(trace),'--notify-tracing-started',notification_name,'--no-prompt','--recording-options',str(options)]
        save(out/'recorder-admission.json',dict(argv=argv,at=time.time(),deadline=deadline))
        record_stream=(out/'recorder.log').open('xb');recorder=subprocess.Popen(argv,stdout=record_stream,stderr=subprocess.STDOUT,start_new_session=True,env=shared.environment())
        notification=notice.wait(ready_deadline,recorder);save(out/'recorder-ready.json',notification)
        publish_admission(device,bundle,identity,out,ready_deadline)
        # No recurring transfers during the measured 16+96+30-second workload.
        finish_after=time.time()+144
        while time.time()<finish_after:
            require(time.time()<deadline,'native deadline expired');require(recorder.poll() is None,'recorder ended during workload');time.sleep(min(.25,finish_after-time.time()))
        result=out/'native.json'
        device.copy_from(bundle,'Documents/impact-'+identity['run_id']+'.json',result,'native-result',deadline)
        native=shared.read(result);scenario(native,identity);scenario_state='PASS'
        after,_=device.command(['device','info','displays'],'display-after',deadline)
        require(display(before,plan['device'])==display(after,plan['device']),'physical display changed')
        stop_recorder(recorder,min(deadline,time.time()+25));require(recorder.returncode==0,'recorder failed')
        record_stream.close();record_stream=None
        log=(out/'recorder.log').read_text()
        require(not any(word in log.lower() for word in ['dropped','data loss','error:','failed to']),'recorder reported incomplete data')
        require(trace.is_dir() and time.time()<deadline,'missing/late trace')
        details.update(native_finished_at=time.time(),trace_members=shared.tree(trace))
    except Exception as error:details['native_error']=str(error)
    finally:
        if notice is not None:
            try:notice.close()
            except Exception as error:details['notification_cleanup_error']=str(error)
        clean=cleanup(device,bundle,pid,owned,recorder,out,time.time()+plan['definition']['budgets_seconds']['cleanup_per_cell'],
                      details.get('notification_cleanup_error'))
        if record_stream is not None:record_stream.close()
    if scenario_state=='PASS' and 'native_error' not in details:
        export_deadline=time.time()+plan['definition']['budgets_seconds']['trace_export_per_cell']
        save(out/'export-admission.json',dict(started_at=time.time(),deadline=export_deadline))
        try:
            toc,exports=export_trace(out,out/'capture.trace',export_deadline)
            measured=measure(toc,exports,native,identity,Path(item['path']).stem,before,after,plan['device'])
            require(time.time()<export_deadline,'metric result late');save(out/'measurement.json',measured);evidence='PASS';details['metrics']=measured['metrics']
        except Exception as error:details['evidence_error']=str(error)
    if build.protected()!=plan['protected']:details['protected_error']='protected paths changed';evidence='INVALID'
    summary=dict(index=index,arm=matrix[index]['arm'],framework=item['framework'],identity=identity,
        scenario=scenario_state,evidence=evidence,cleanup=clean['state'],state='PASS' if scenario_state==evidence==clean['state']=='PASS' else 'INVALID',
        started_at=started,finished_at=time.time(),details=details)
    save(out/'summary.json',summary);print(json.dumps({k:summary[k] for k in ['index','state','scenario','evidence','cleanup']}),flush=True)
    if summary['state']!='PASS':return False
    if index in [3,7]:
        group=[shared.read(root/'cells'/str(i)/'summary.json') for i in range(index-3,index+1)]
        comparison=compare_abba([dict(arm=r['arm'],**r['details']['metrics']) for r in group]);save(root/(item['framework']+'-comparison.json'),comparison)
        require(comparison['state']=='PASS','paired performance regression; stop the wave')
    return True


def bound_cell(row,index,plan,admission,plan_sha):
    item=plan['matrix'][index];product=plan['products'][item['arm']+'-'+item['workload']]
    require(type(row.get('index')) is int and row['index']==index and row.get('arm')==item['arm']
            and row.get('framework')==item['workload'],'swapped cell summary')
    identity=row.get('identity',{})
    require(all(identity.get(k)==product[k] for k in ['source','fixture','framework']),'stale cell product')
    require(admission.get('index')==index and admission.get('signed_plan_sha256')==plan_sha
            and row.get('started_at')==admission.get('started_at'),'foreign cell admission')
    require(set(admission.get('identity',{}))=={'run_id','nonce','source','fixture','framework'}
            and all(identity.get(k)==v for k,v in admission['identity'].items()),'stale cell identity')
    require(identity['run_id']!=identity['nonce'],'reused run nonce')
    for name in ['run_id','nonce']:require(str(uuid.UUID(identity[name]))==identity[name],'invalid '+name)
    return identity


def final_verdict(cells,comparisons,cleanup_state,error=None):
    complete=len(cells)==8 and all(c.get('state')=='PASS' for c in cells)
    accepted=complete and set(comparisons)=={'UIKit','SwiftUI'} and all(c.get('state')=='PASS' for c in comparisons.values())
    if cleanup_state!='PASS' or error or not complete or set(comparisons)!={'UIKit','SwiftUI'}:state='INVALID'
    elif accepted:state='PASS'
    else:state='FAIL'
    return dict(state=state,cells_completed=sum(c.get('state')=='PASS' for c in cells),cells_planned=8,
                scenario='PASS' if len(cells)==8 and all(c.get('scenario')=='PASS' for c in cells) else 'INVALID',
                evidence='PASS' if len(cells)==8 and all(c.get('evidence')=='PASS' for c in cells) else 'INVALID',
                cleanup=cleanup_state,comparisons=comparisons,error=error)


def finalize(root,error=None):
    root=Path(root);plan=shared.read(root/'signed-plan.json');out=root/'final';out.mkdir(exist_ok=False)
    deadline=time.time()+plan['definition']['budgets_seconds']['final_cleanup'];checks={};errors=[];binding_errors=[]
    save(out/'admission.json',dict(started_at=time.time(),deadline=deadline))
    device=Device(plan['device'],out)
    for key,item in plan['products'].items():
        try:device.apps_absent(item['bundle'],'absence-'+key,deadline);checks[key]='PASS'
        except Exception as failure:checks[key]='INVALID';errors.append(key+': '+str(failure))
    cells=[];receipts={};seen=set()
    bindings=dict(matrix=plan['definition']['matrix'],products=plan['products']);plan_sha=shared.sha(root/'signed-plan.json')
    for index in range(8):
        path=root/'cells'/str(index)/'summary.json'
        if path.exists():
            row=shared.read(path);cells.append(row);receipts[str(path.relative_to(root))]=shared.sha(path)
            try:
                identity=bound_cell(row,index,bindings,shared.read(path.parent/'admission.json'),plan_sha)
                require(not ({identity['run_id'],identity['nonce']}&seen),'duplicate wave identity')
                seen.update([identity['run_id'],identity['nonce']])
                require(shared.read(path.parent/'cleanup.json')['state']==row['cleanup'],'cleanup receipt differs')
                if row['evidence']=='PASS':
                    measurement=shared.read(path.parent/'measurement.json')
                    require(measurement['identity']==identity and measurement['metrics']==row['details']['metrics'],'measurement receipt differs')
            except Exception as failure:binding_errors.append('cell '+str(index)+': '+str(failure))
        elif (path.parent/'admission.json').exists():errors.append('cell '+str(index)+' missing terminal summary')
    try:
        raw,_=device.command(['device','info','processes'],'final-processes',deadline)
        processes=returned(raw,plan['device'],'devicectl.device.info.processes').get('runningProcesses')
        require(isinstance(processes,list),'missing final process inventory')
        pids={row['identity'].get('pid') for row in cells}-{None}
        require(not any(p.get('processIdentifier') in pids for p in processes),'task process retained')
        checks['processes']='PASS'
    except Exception as failure:checks['processes']='INVALID';errors.append(str(failure))
    try:require_quiet_host();checks['host_quiescence']='PASS'
    except Exception as failure:checks['host_quiescence']='INVALID';errors.append(str(failure))
    if build.protected()!=plan['protected']:errors.append('protected paths changed')
    if any(row.get('cleanup')!='PASS' for row in cells):errors.append('an original cell cleanup was invalid')
    if time.time()>=deadline:errors.append('final cleanup deadline expired')
    clean=dict(state='INVALID' if errors else 'PASS',checks=checks,errors=errors,deadline=deadline,finished_at=time.time())
    save(out/'cleanup.json',clean)
    comparisons={}
    for framework in ['UIKit','SwiftUI']:
        path=root/(framework+'-comparison.json')
        if path.exists():
            comparisons[framework]=shared.read(path);receipts[path.name]=shared.sha(path)
            try:
                group=[row for row in cells if row['framework']==framework]
                require(len(group)==4 and comparisons[framework]==compare_abba([dict(arm=row['arm'],**row['details']['metrics']) for row in group]),'comparison receipt differs')
            except Exception as failure:error=(error+'; ' if error else '')+str(failure)
    if binding_errors:error=(error+'; ' if error else '')+'; '.join(binding_errors)
    result=final_verdict(cells,comparisons,clean['state'],error)
    result.update(experiment='EXP-224',signed_plan_sha256=shared.sha(root/'signed-plan.json'),receipts=receipts,
                  finished_at=time.time(),scope='Application/display workload impact; not exact app-rendered frames or backend ownership acceptance')
    save(root/'summary.json',result);print(json.dumps(result),flush=True)
    return result['state']=='PASS'


def wave(root):
    error=None
    try:
        for index in range(8):
            if not cell(root,index):break
    except Exception as failure:error=str(failure)
    return finalize(root,error)


def main():
    p=argparse.ArgumentParser();p.add_argument('stage',choices=['prepare','cell','wave','finalize']);p.add_argument('--root',type=Path,required=True)
    p.add_argument('--build-root',type=Path);p.add_argument('--profile',type=Path);p.add_argument('--certificate');p.add_argument('--device');p.add_argument('--udid');p.add_argument('--index',type=int)
    a=p.parse_args()
    if a.stage=='prepare':prepare(a.root,a.build_root,a.profile,a.certificate,a.device,a.udid)
    elif a.stage=='cell':
        if not cell(a.root,a.index):sys.exit(1)
    elif a.stage=='wave':
        if not wave(a.root):sys.exit(1)
    elif not finalize(a.root):sys.exit(1)

if __name__=='__main__':main()
