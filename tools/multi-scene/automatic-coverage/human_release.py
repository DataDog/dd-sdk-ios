"""Coverage-only cleanup proof; never repairs a failed scenario verdict."""
import hashlib
import json
from pathlib import Path
import sys
import time
import uuid
import human_contract as oracle
import s2_hosting_workflow as shared
from acceptance_common import require

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'interactive-transitions'))
import physical_release as release_protocol


def process_identity(pid):
    return shared.capture(['ps','-p',str(pid),'-o','lstart=,comm='],check=False).stdout.decode().strip()


def idle(raw, receipt, request_bytes, run, binding, original_prefix):
    require(raw.startswith(original_prefix),'cleanup rewrote the failed scenario evidence')
    request=json.loads(request_bytes);count=receipt['byte_count'];prefix=raw[:count]
    require(set(receipt)=={'schema_version','run_id','request_id','sequence','success','byte_count','sha256'}
        and type(receipt['schema_version']) is int and receipt['schema_version']==1 and receipt['success'] is True
        and type(count) is int and len(original_prefix)<count<=len(raw) and prefix.endswith(b'\n')
        and hashlib.sha256(prefix).hexdigest()==receipt['sha256'],'invalid cleanup writer prefix')
    rows=[json.loads(line) for line in prefix.splitlines()]
    require(rows and all(r['run_id']==run for r in rows) and [r['sequence'] for r in rows]==list(range(1,len(rows)+1))
        and receipt['sequence']==rows[-1]['sequence'] and receipt['run_id']==run
        and receipt['request_id']==request['request_id'],'foreign or incomplete cleanup stream')
    bindings=[r for r in rows if r['kind']=='human_window_binding']
    require(len(bindings)==1 and bindings[0]['payload']==binding,'cleanup replaced the native owner')
    snapshots=[r for r in rows if r['kind']=='human_snapshot' and r['payload']['request_id']==request['request_id']]
    require(len(snapshots)==1,'missing or duplicate fresh cleanup snapshot')
    value=snapshots[0]['payload']
    require(request['run_id']==run and request['phase']==value['phase']=='cleanup.idle'
        and value['request_sha256']==hashlib.sha256(request_bytes).hexdigest(),'stale cleanup snapshot')
    topology=value['topology'];state=value['input_state']
    if type(topology['app_state']) is int and topology['app_state']==1:
        # Launch can return before foreground activation. This observation can
        # only keep cleanup pending; it never authorizes task teardown.
        require(topology['window_alive'] is True and topology['root_alive'] is True
            and topology['bound_root_unchanged'] is True
            and all(topology['bound_'+k]==binding[k] for k in ['window','root','scene']),
            'reactivating fixture owner changed')
        scene=oracle.one(topology['scene_inventory'],'reactivating scene')
        require(scene['id']==binding['scene'] and scene['activation']==1,'reactivating scene changed')
        windows=scene['windows']
        require(windows and len({w['id'] for w in windows})==len(windows),'incomplete reactivating windows')
        owned=oracle.one([w for w in windows if w.get('owned') is True],'reactivating content window')
        require(owned['id']==binding['window'] and owned['root']==binding['root']
            and owned['root_attached'] is True and not any(w['key'] for w in windows if w is not owned),
            'reactivating window owner changed')
        input_idle(state,binding)
        return None
    oracle.topology(topology,binding)
    if not input_idle(state,binding):return None
    return dict(state='NATIVE_INPUT_IDLE',run_id=run,request_id=request['request_id'],sequence=snapshots[0]['sequence'],
                checkpoint_sha256=hashlib.sha256(json.dumps(receipt,sort_keys=True).encode()).hexdigest())


def input_idle(state,binding):
    require(state['valid'] is True and all(state[k]==binding[k] for k in ['window','root','scene'])
        and type(state['view_count']) is int and 0<state['view_count']<=4096
        and type(state['controller_count']) is int and 0<state['controller_count']<=256,'incomplete native input inventory')
    for name in ['gestures','controls','scrolls']:
        entries=state[name]
        require(type(entries) is list and len({e['id'] for e in entries})==len(entries)
            and all(type(e['id']) is str and e['id']!='nil' for e in entries),'invalid cleanup '+name+' inventory')
    require(all(type(g['state']) is int and g['state'] in range(6) and type(g['touches']) is int and g['touches']>=0
                for g in state['gestures']),'invalid gesture state')
    require(type(state['coordinators']) is list and all(type(v) is str and v!='nil' for v in state['coordinators']),
            'invalid native coordinator inventory')
    for name,keys in [('controls',['tracking']),('scrolls',['tracking','dragging','decelerating'])]:
        require(all(type(e[k]) is bool for e in state[name] for k in keys),'invalid native tracking state')
    if (any(g['state'] in [1,2] or g['touches'] for g in state['gestures'])
        or any(e['tracking'] for e in state['controls'])
        or any(any(e[k] for k in ['tracking','dragging','decelerating']) for e in state['scrolls'])
        or state['coordinators']):return False
    return True


def home_idle(collector):
    folder=collector.output/'background.before';request_bytes=(folder/'request.json').read_bytes();request=json.loads(request_bytes)
    path=collector.documents/('home-input-idle-'+request['request_id']+'.json')
    raw=path.read_bytes();value=json.loads(raw)
    require(value['schema_version']==1 and value['run_id']==collector.run and value['pid']==collector.pid
        and value['request_id']==request['request_id'] and request['phase']=='background.before'
        and value['request_sha256']==hashlib.sha256(request_bytes).hexdigest()
        and value['notification']=='UIApplication.didEnterBackgroundNotification','foreign native Home idle proof')
    rows=oracle.checkpoint((folder/'background-events.jsonl').read_bytes(),shared.read(folder/'background-checkpoint.json'),
        collector.run,shared.read(folder/'background-checkpoint.json')['request_id'])
    before=oracle.one([r for r in rows if r['kind']=='human_snapshot' and r['payload']['request_id']==request['request_id']], 'Home request')
    home=oracle.one([r for r in rows if r['kind']=='native_background'],'actual Home')
    require(before['sequence']<home['sequence'],'Home idle request was not armed before Home')
    topology=value['topology'];binding=collector.binding
    require(topology['app_state']==2 and topology['window_alive'] is True and topology['root_alive'] is True
        and topology['bound_root_unchanged'] is True and all(topology['bound_'+k]==binding[k] for k in ['window','root','scene']),
        'Home idle proof lacks the original background owner')
    scene=oracle.one(topology['scene_inventory'],'Home scene')
    require(scene['id']==binding['scene'] and scene['activation']==2,'Home scene is not background')
    owned=oracle.one([w for w in scene['windows'] if w.get('owned') is True],'Home content window')
    require(owned['id']==binding['window'] and owned['root']==binding['root'] and owned['root_attached'] is True
        and not any(w['key'] for w in scene['windows'] if w is not owned),'Home owner was replaced')
    require(input_idle(value['input_state'],binding),'native Home input is not idle')
    require(process_identity(collector.pid)==collector.process_identity,'Home source process replaced')
    (folder/'home-input-idle.json').write_bytes(raw)
    return dict(state='NATIVE_HOME_INPUT_IDLE',run_id=collector.run,home_sequence=home['sequence'],
        request_id=request['request_id'],proof_sha256=hashlib.sha256(raw).hexdigest())


def capture_idle(collector, folder, identity, deadline):
    require(collector.binding is not None,'cleanup lacks original native binding')
    original=(collector.documents/'events.jsonl').read_bytes()
    (folder/'failed-scenario-prefix.jsonl').write_bytes(original)
    require(process_identity(collector.pid)==collector.process_identity,'original process changed before cleanup')
    # Failed Home collection can leave the same process suspended. Activation is
    # cleanup-only and occurs after release, never to salvage behavioral evidence.
    if any(r['kind']=='native_background' for r in collector.pending_for_cleanup()):
        shared.command(['xcrun','simctl','launch',collector.device,identity['bundle']],folder,'cleanup-reactivate',deadline=deadline)
        require(process_identity(collector.pid)==collector.process_identity,'cleanup activation replaced the original process')
    index=0
    while True:
        require(time.time()<deadline-15,'native idle unproven; preserve app for later restoration')
        require(process_identity(collector.pid)==collector.process_identity,'cleanup original process changed')
        attempt=folder/('idle-'+str(index));attempt.mkdir();index+=1
        request=dict(schema_version=1,run_id=collector.run,request_id=str(uuid.uuid4()),phase='cleanup.idle')
        shared.save(attempt/'request.json',request,exclusive=True);request_bytes=(attempt/'request.json').read_bytes()
        shared.save(collector.documents/'human-snapshot-request.json',request)
        path=collector.documents/('events-checkpoint-'+request['request_id']+'.json')
        limit=min(deadline-15,time.time()+collector.budget['snapshot_seconds'])
        while not path.exists():
            require(time.time()<limit and process_identity(collector.pid)==collector.process_identity,'cleanup snapshot unavailable; preserve app')
            time.sleep(.1)
        raw=(collector.documents/'events.jsonl').read_bytes();checkpoint=path.read_bytes()
        (attempt/'events.jsonl').write_bytes(raw);(attempt/'checkpoint.json').write_bytes(checkpoint)
        proof=idle(raw,json.loads(checkpoint),request_bytes,collector.run,collector.binding,original)
        require(time.time()<limit,'late cleanup snapshot; preserve app')
        if proof is not None:return proof
        time.sleep(.2)


def guard(collector,out,identity,deadline):
    require(process_identity(collector.pid)==collector.process_identity,'original process changed; defer teardown')
    raw=(collector.documents/'events.jsonl').read_bytes()
    (out/'before-release-events.jsonl').write_bytes(raw)
    return release_protocol.fence(collector,out,identity,deadline,device_label='simulator')
