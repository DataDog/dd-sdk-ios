"""Bounded CoreDevice transfers with immutable raw responses and owned children."""
import json
import os
from pathlib import Path
import signal
import subprocess
import time
import build

shared=build.shared
require=build.require


def members(group):
    result=subprocess.run(['/bin/ps','-axo','pid=,pgid='],capture_output=True,text=True,
                          start_new_session=True,timeout=15,check=True)
    return sorted(int(pid) for pid,pgid in (line.split() for line in result.stdout.splitlines()) if int(pgid)==group)


def returned(raw,device,command):
    info=raw.get('info',{});args=info.get('arguments',[])
    require(info.get('outcome')=='success' and info.get('commandType')==command and '--device' in args
            and args[args.index('--device')+1]==device,'foreign or failed device response')
    return raw['result']


def display(raw,device):
    value=returned(raw,device,'devicectl.device.info.displays');screens=value.get('displays',[])
    require(len(screens)==1,'ambiguous physical display inventory');screen=screens[0]
    require(screen.get('primary') is True and screen.get('type')=={'integrated':{}} and
            screen.get('backlightState')=='activeOn' and type(screen.get('displayId')) is int,'wrong physical display')
    require(screen.get('currentOrientation') in ['rot0','rot90','rot180','rot270'] and
            len(screen['nativeSize'])==2 and all(type(n) in [int,float] and n>0 for n in screen['nativeSize']) and
            type(screen.get('pointScale')) in [int,float] and screen['pointScale']>0,'invalid physical display geometry')
    return {k:screen[k] for k in ['displayId','primary','type','nativeSize','pointScale','currentOrientation','bounds']}


class Device:
    def __init__(self,identifier,output):
        self.identifier=identifier;self.output=Path(output);self.output.mkdir(exist_ok=True);self.sequence=0;self.groups=[]
    def command(self,args,label,deadline,*,check=True,seconds=30):
        self.sequence+=1;folder=self.output/(str(self.sequence).zfill(5)+'-'+label);folder.mkdir()
        limit=min(deadline,time.time()+seconds);require(time.time()+1<limit,'device command lacks remaining budget')
        raw=folder/'response.json';argv=['xcrun','devicectl',*args[:3],'--device',self.identifier,
            '--timeout',str(max(1,int(limit-time.time())-1)),'--json-output',str(raw),*args[3:]]
        started=time.time();shared.save(folder/'admission.json',dict(argv=argv,started_at=started,deadline=limit),exclusive=True)
        error=None
        with (folder/'console.log').open('xb') as stream:
            child=subprocess.Popen(argv,stdout=stream,stderr=subprocess.STDOUT,env=shared.environment(),start_new_session=True)
            self.groups.append(child.pid)
            try:child.wait(timeout=max(.001,limit-time.time()))
            except BaseException as failure:error=failure
            finally:
                if child.poll() is None:
                    os.killpg(child.pid,signal.SIGTERM)
                    try:child.wait(timeout=1)
                    except subprocess.TimeoutExpired:os.killpg(child.pid,signal.SIGKILL);child.wait(timeout=1)
        before=remaining=None;quiescence_error=None
        try:
            before=remaining=members(child.pid)
            if remaining:
                os.killpg(child.pid,signal.SIGKILL);remaining=members(child.pid)
        except Exception as failure:quiescence_error=str(failure)
        receipt=dict(started_at=started,finished_at=time.time(),deadline=limit,returncode=child.returncode,
                     pid=child.pid,group=child.pid,before=before,remaining=remaining,quiescence_error=quiescence_error,
                     response_sha256=shared.sha(raw) if raw.exists() else None)
        shared.save(folder/'receipt.json',receipt,exclusive=True)
        if error:raise error
        require(quiescence_error is None and remaining==[] and before==[],'CoreDevice child lifetime unqualified')
        require(time.time()<limit,'device response arrived after original deadline')
        result=shared.read(raw) if raw.exists() else None
        if check:
            require(child.returncode==0 and result is not None,'device command failed: '+label)
            returned(result,self.identifier,'devicectl.'+'.'.join(args[:3]))
        return result,receipt
    def pull(self,bundle,source,destination,label,deadline,*,check=True):
        destination=Path(destination);require(not destination.exists(),'download destination reused')
        return self.command(['device','copy','from','--domain-type','appDataContainer','--domain-identifier',bundle,
            '--source',source,'--destination',str(destination)],label,deadline,check=check)
    def push(self,bundle,source,destination,label,deadline):
        return self.command(['device','copy','to','--domain-type','appDataContainer','--domain-identifier',bundle,
            '--source',str(source),'--destination',destination],label,deadline)
    def absence(self,bundle,label,deadline):
        raw,_=self.command(['device','info','apps','--bundle-id',bundle],label,deadline)
        result=returned(raw,self.identifier,'devicectl.device.info.apps')
        require(result.get('deviceIdentifier')==self.identifier and result.get('matchingBundleIdentifier')==bundle and
                result.get('apps')==[],'task app remains or inventory incomplete')
    def processes(self,label,deadline):
        raw,_=self.command(['device','info','processes'],label,deadline)
        rows=returned(raw,self.identifier,'devicectl.device.info.processes').get('runningProcesses')
        require(isinstance(rows,list),'missing physical process inventory');return rows
    def quiescent(self,deadline):
        require(time.time()<deadline,'process inventory after cleanup deadline')
        response=subprocess.run(['/bin/ps','-axo','pid=,pgid='],capture_output=True,text=True,start_new_session=True,
            timeout=min(15,max(.001,deadline-time.time())),check=True)
        rows=[dict(pid=int(pid),group=int(group)) for pid,group in (r.split() for r in response.stdout.splitlines()) if int(group) in self.groups]
        proof=dict(state='PASS' if not rows and time.time()<deadline else 'INVALID',groups=self.groups,remaining=rows,at=time.time(),deadline=deadline)
        shared.save(self.output/'before-cleanup-quiescence.json',proof,exclusive=True)
        require(proof['state']=='PASS','device commands not quiescent; task cleanup deferred')


def hardware(device,udid,out,deadline):
    raw,_=device.command(['device','info','details'],'device-details',deadline)
    result=returned(raw,device.identifier,'devicectl.device.info.details')
    h=result['hardwareProperties'];v=result['deviceProperties']
    require(h['reality']=='physical' and h['deviceType']=='iPad' and h['udid']==udid and
            v['developerModeStatus']=='enabled' and v['ddiServicesAvailable'] is True and
            int(v['osVersionNumber'].split('.')[0])>=18,'physical iPad developer prerequisite missing')
    raw,_=device.command(['device','info','lockState'],'device-lock',deadline)
    lock=returned(raw,device.identifier,'devicectl.device.info.lockState')
    require(lock['passcodeRequired'] is False and lock['unlockedSinceBoot'] is True,'physical iPad locked')
    return dict(device=device.identifier,udid=udid,model=h['productType'],os=v['osVersionNumber'],build=v['osBuildUpdate'])
