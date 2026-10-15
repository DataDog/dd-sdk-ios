"""Actual-display evidence for human fold input; no synthesized UI actions."""
import hashlib
import json
import math
from pathlib import Path
import time
from acceptance_common import require
import s2_webview_runtime as displays


def ms():return time.time_ns()//1_000_000

def asset(ref):
    require(isinstance(ref,dict) and set(ref)=={'path','sha256'},'unbound human asset')
    path=Path(ref['path']);require(path.is_file() and not path.is_symlink(),'missing/symlinked human asset')
    raw=path.read_bytes();require(hashlib.sha256(raw).hexdigest()==ref['sha256'],'human asset changed');return raw

def signature(ref,device):return displays.display_signature(displays.active_display(json.loads(asset(ref)),device))

def capture_interval(display_ref, command_ref, device):
    command=json.loads(asset(command_ref));raw=json.loads(asset(display_ref));argv=command['command']
    require(Path(argv[0]).name=='devicectl' and argv[1:]==['device','info','displays','--device',device,
            '--timeout','15','--json-output',display_ref['path']] and raw['info']['arguments'][1:]==argv[1:]
            and command['returncode']==0,'display is not the actual returned command output')
    start,end=command['started_at'],command['finished_at']
    require(all(type(v) in [int,float] and math.isfinite(v) for v in [start,end]) and start<=end,'invalid capture clock')
    log=Path(command_ref['path']).with_suffix('.log')
    require(log.is_file() and hashlib.sha256(log.read_bytes()).hexdigest()==command['log_sha256'],'capture log changed')
    return int(start*1000),int(end*1000)


def validate_input(p,request,device):
    require(p.get('input_kind')=='HUMAN_ACTUAL_DISPLAY','not a human display observation')
    prompt=json.loads(asset(p['human_prompt']));terminal=json.loads(asset(json.loads(asset(p['input_proof']))['terminal']))
    require(prompt['kind']=='HUMAN_FOLD_REQUEST' and prompt['request_sha256']==p['request_sha256']
            and prompt['device']==device and prompt['phase']==request['phase']
            and prompt['deadline']==request['deadline'] and prompt['input_deadline']==request['deadline']-60_000,'foreign human prompt')
    require(request['issued_at']<=prompt['issued_at']==p['input_started_at']<=p['input_finished_at']==p['input_returned_at']<prompt['input_deadline'],
            'human input outside original host interval')
    require(terminal['status']=='HUMAN_DISPLAY_OBSERVED' and terminal['automated_input_workers']==0
            and terminal['worker_quiescent'] is True and terminal['observed_after_ms']==p['input_returned_at'], 'wrong human completion/quiescence')
    before_clock=capture_interval(p['human_before_display'],p['human_before_command'],device)
    after_clock=capture_interval(p['human_after_display'],p['human_after_command'],device)
    require(request['issued_at']<=before_clock[0]<=before_clock[1]<=prompt['issued_at']
            <=after_clock[0]<=after_clock[1]<=p['input_returned_at'],'older matching observation substituted')
    before=signature(p['human_before_display'],device);after=signature(p['human_after_display'],device)
    require(before==signature(request['displays_before'],device) and after==signature(p['displays'],device)
            and before!=after,'human observed display does not match native proof')
    require(prompt['display']==p['human_before_display'],'prompt replaced actual before observation')
    require(asset(prompt['screenshot']).startswith(b'\x89PNG\r\n\x1a\n'),'prompt screenshot missing')
    shot=json.loads(asset(prompt['screenshot_command']))
    active=displays.active_display(json.loads(asset(p['human_before_display'])),device)
    require(shot['device']==device and shot['display_unique_id']==active['uniqueId'] and shot['returncode']==0,'prompt screenshot belongs to another display')


def observe(request_path, *, host, rules, display):
    request_path=Path(request_path);folder=request_path.parent;request=host.read(request_path);deadline=request['deadline']
    require(request['phase'] in ['open','closed'] and ms()<deadline,'unknown/expired human fold')
    ref=lambda path:{'path':str(path),'sha256':host.digest(path)}
    current=display(request['device'],folder,'human-before')
    require(signature(current,request['device'])==signature(request['displays_before'],request['device']),'display changed before prompt')
    active=displays.active_display(json.loads(asset(current)),request['device'])
    png=folder/'human-ready.png'
    host.command([host.DEVELOPER+'/usr/bin/devicectl','device','capture','screenshot','--device',request['device'],
                  '--display-unique-id',active['uniqueId'],'--destination',str(png),'--timeout','15'],folder,'human-screenshot',timeout=20)
    shot=folder/'human-screenshot-binding.json';host.save(shot,{'device':request['device'],'display_unique_id':active['uniqueId'],
        'returncode':0,'command':ref(folder/'human-screenshot.json')})
    prompt={'kind':'HUMAN_FOLD_REQUEST','request_sha256':rules.fingerprint(request),'device':request['device'],
            'phase':request['phase'],'issued_at':ms(),'deadline':deadline,'input_deadline':deadline-60_000,'display':current,'screenshot':ref(png),'screenshot_command':ref(shot)}
    require(prompt['issued_at']<prompt['input_deadline'],'prompt capture exceeded input deadline');prompt_path=folder/'human-prompt.json';host.save(prompt_path,prompt)
    print(json.dumps({'human_input':{'kind':'resource-trace-fold','phase':request['phase'],'device':request['device'],
          'deadline':prompt['input_deadline']/1000,'screenshot':str(png),'instruction':'Set this Duo to '+request['phase']+' once; native and backend evidence collection continues automatically.'}}),flush=True)
    index=0
    while ms()+25_000<prompt['input_deadline']:
        time.sleep(1);observed=display(request['device'],folder,'human-observed-'+str(index));index+=1;finished=ms()
        if signature(observed,request['device'])==signature(current,request['device']):continue
        require(finished<prompt['input_deadline'],'actual display observed after input deadline')
        terminal=folder/'human-terminal.json';host.save(terminal,{'status':'HUMAN_DISPLAY_OBSERVED','worker_quiescent':True,
            'automated_input_workers':0,'observed_after_ms':finished})
        value={'input_kind':'HUMAN_ACTUAL_DISPLAY','request_sha256':rules.fingerprint(request),
            'input_started_at':prompt['issued_at'],'input_finished_at':finished,'input_returned_at':finished,
            'terminal':ref(terminal),'human_before_display':current,'human_after_display':observed,'human_prompt':ref(prompt_path),
            'human_before_command':ref(folder/'human-before.json'),'human_after_command':ref(folder/('human-observed-'+str(index-1)+'.json'))}
        path=folder/'human-input-proof.json';host.save(path,value)
        print(json.dumps({'human_status':{'instruction':'Display change captured. Wait while ownership evidence is collected.'}}),flush=True)
        return path
    raise ValueError('human fold effect missing at original deadline')


def restore(device,out,fold,*,host,rules,display,reserve):
    if fold is None:return False
    initial=fold['initial_displays'];before=display(device,out,'fold-cleanup-before')
    wanted=signature(initial,device);current=before;deadline=min(ms()+240_000,int(host.DEADLINE*1000)-reserve*1000)
    if signature(current,device)!=wanted:
        require(ms()<deadline,'no cleanup pose reserve')
        print(json.dumps({'human_input':{'kind':'cleanup','phase':'closed','device':device,'deadline':deadline/1000,
            'instruction':'Restore the selected Duo to Closed. Task removal retains its separate cleanup reserve.'}}),flush=True)
        index=0
        while signature(current,device)!=wanted:
            require(ms()+25_000<deadline,'original display not restored');time.sleep(1)
            current=display(device,out,'fold-human-cleanup-'+str(index));index+=1
    require(ms()+25_000<host.DEADLINE*1000,'cleanup display capture reserve exhausted')
    after=display(device,out,'fold-cleanup-after');fold['cleanup_displays']=after
    fold['cleanup_pose_restored']=signature(after,device)==wanted
    require(fold['cleanup_pose_restored'],'original actual display not restored');return True
