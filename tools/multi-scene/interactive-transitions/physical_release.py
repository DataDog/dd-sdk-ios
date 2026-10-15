"""A failed human step cannot authorize app teardown while input may still be held."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import time
import uuid
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'app-acceptance'))
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'acceptance'))
from capture_io import atomic, encoded
from acceptance_common import require


def acknowledge(path, message):
    path=Path(path);request=json.loads(path.read_bytes());now=time.time()
    require(request['kind']=='HUMAN_RELEASE_REQUIRED' and request['issued_at']<=now<request['deadline'],
            'expired or foreign release acknowledgement')
    require(message.strip(), 'actual operator reply required')
    record=dict(kind='OPERATOR_RELEASED',request_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
        request_id=request['request_id'],run_id=request['run_id'],at=now,user_message=message)
    atomic(path.with_name('operator-released.json'),encoded(record));return record


def validate_ack(request, raw, reply, now):
    require(reply['kind']=='OPERATOR_RELEASED' and reply['request_id']==request['request_id'] and
        reply['run_id']==request['run_id'] and reply['request_sha256']==hashlib.sha256(raw).hexdigest() and
        request['issued_at']<=reply['at']<=now<request['deadline'] and bool(reply['user_message'].strip()),
        'stale, missing or foreign operator release')


def native_idle(data, checkpoint, request_bytes, identity, binding):
    """Failure rows remain present; this proves cleanup only, never scenario acceptance."""
    request=json.loads(request_bytes);count=checkpoint['byte_count']
    require(set(checkpoint)=={'schema_version','run_id','request_id','sequence','success','byte_count','sha256'} and
        type(checkpoint['schema_version']) is int and checkpoint['schema_version']==1 and checkpoint['success'] is True and
        type(count) is int and 0<count<=len(data),'invalid cleanup checkpoint')
    prefix=data[:count]
    require(prefix.endswith(b'\n') and
            hashlib.sha256(prefix).hexdigest()==checkpoint['sha256'],'cleanup checkpoint bytes differ')
    rows=[json.loads(line) for line in prefix.splitlines()]
    require(rows and [r['sequence'] for r in rows]==list(range(1,len(rows)+1)) and
        all(r['run_id']==identity['run_id'] for r in rows),'foreign or incomplete cleanup stream')
    require(checkpoint['run_id']==identity['run_id'] and checkpoint['request_id']==request['request_id'] and
        type(checkpoint['sequence']) is int and checkpoint['sequence']==rows[-1]['sequence'],'cleanup checkpoint identity differs')
    launches=[r for r in rows if r['kind']=='launch'];require(len(launches)==1,'cleanup launch missing')
    require(all(launches[0]['payload'][k]==identity[k] for k in ['pid','source','fixture','nonce','bundle']),
        'cleanup process identity changed')
    values=[r for r in rows if r['kind']=='human_snapshot' and r['payload']['request_id']==request['request_id']]
    require(len(values)==1,'cleanup snapshot absent or duplicated');value=values[0]['payload']
    require(request['run_id']==identity['run_id'] and request['phase']=='cleanup.idle' and
        value['phase']==request['phase'] and value['request_sha256']==hashlib.sha256(request_bytes).hexdigest(),
        'stale cleanup snapshot')
    state=value['input_state'];topology=value['topology']
    require(state['valid'] is True and all(state[k]==binding[k]==topology['bound_'+k] for k in ['window','root','scene'])
        and topology['window_alive'] is True and topology['root_alive'] is True and topology['bound_root_unchanged'] is True,
        'cleanup native owner changed')
    pans=state['pans'];require(pans and len({p['id'] for p in pans})==len(pans),'cleanup gesture inventory incomplete')
    require(all(type(p['state']) is int and p['state'] in [0,3,4,5] and type(p['touches']) is int and p['touches']==0 for p in pans)
        and state['coordinators']==[],'human input or transition still active; defer teardown')
    return dict(state='NATIVE_INPUT_IDLE',run_id=identity['run_id'],request_id=request['request_id'],
        sequence=values[0]['sequence'],checkpoint_sha256=hashlib.sha256(encoded(checkpoint)).hexdigest())


def fence(collector, out, identity, deadline, *, device_label='iPad'):
    folder=Path(out)/'human-release';folder.mkdir();limit=min(deadline-45,time.time()+180)
    require(time.time()+1<limit,'no budget for operator release; defer teardown')
    request=dict(kind='HUMAN_RELEASE_REQUIRED',request_id=str(uuid.uuid4()),run_id=identity['run_id'],
        issued_at=time.time(),deadline=limit,instruction='The test stopped. Release all fingers from the '+device_label+', stop interacting, and reply Released in this conversation. The app will remain open until release is verified.')
    path=folder/'request.json';raw=encoded(request);atomic(path,raw)
    print(json.dumps(dict(human_release=dict(request_path=str(path),**request))),flush=True)
    reply_path=folder/'operator-released.json'
    while not reply_path.exists():
        require(time.time()<limit,'operator release unconfirmed; defer teardown');time.sleep(.2)
    reply=json.loads(reply_path.read_bytes());validate_ack(request,raw,reply,time.time())
    # This new request is published only after the real operator acknowledgement.
    proof=collector.cleanup_idle(folder,identity,deadline)
    atomic(folder/'quiescent.json',encoded(dict(state='PASS',operator_sha256=hashlib.sha256(reply_path.read_bytes()).hexdigest(),
        native=proof,at=time.time(),deadline=deadline)))
    return proof


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--request',type=Path,required=True)
    parser.add_argument('--user-message',required=True);args=parser.parse_args()
    acknowledge(args.request,args.user_message)
