"""Failure cleanup for the tap-only app journey; never renew a scenario deadline."""
import argparse
import hashlib
import json
from pathlib import Path
import time
import uuid

from acceptance_common import require
from capture_contract import MAX_BYTES, published_snapshot
from capture_io import atomic, bounded_read, encoded


def validate_ack(request, raw, reply, now):
    require(reply.get('kind')=='OPERATOR_RELEASED' and reply.get('request_id')==request['request_id']
            and reply.get('identity')==request['identity'] and reply.get('pid')==request['pid']
            and reply.get('request_sha256')==hashlib.sha256(raw).hexdigest()
            and request['issued_at']<=reply.get('at',0)<=now<request['deadline']
            and reply.get('user_message','').strip().casefold()=='released', 'missing, stale or foreign release acknowledgement')


def acknowledge(path, message):
    path=Path(path);raw=bounded_read(path,16_384);request=json.loads(raw);now=time.time()
    require(request['kind']=='APP_JOURNEY_RELEASE_REQUIRED', 'wrong release request')
    reply=dict(kind='OPERATOR_RELEASED',request_id=request['request_id'],identity=request['identity'],pid=request['pid'],
               request_sha256=hashlib.sha256(raw).hexdigest(),at=now,user_message=message)
    validate_ack(request,raw,reply,now)
    atomic(path.with_name('operator-released.json'),encoded(reply))
    return reply


def idle(snapshot, pid, binding):
    topology=snapshot['fields']['topology']
    require(topology['pid']==pid and topology['app_state']==0, 'cleanup original foreground process unavailable')
    scenes=topology['scene_inventory'];require(len(scenes)==1 and scenes[0]['id']==binding['scene']
                                             and scenes[0]['activation']==0, 'cleanup scene changed or inactive')
    owned=[w for w in scenes[0]['windows'] if w.get('owned') is True]
    require(len(owned)==1 and owned[0]['id']==binding['window'] and owned[0]['root']==binding['root']
            and owned[0]['key'] is True and owned[0]['root_attached'] is True, 'cleanup native window/root changed')
    attached=[c for c in topology['controllers'] if c.get('window')==binding['window']]
    require(attached and any(c['id']==binding['root'] for c in attached)
            and all(c.get('scene')==binding['scene'] and c.get('transition')=={} for c in attached),
            'cleanup transition still active or controller inventory incomplete')
    return dict(state='TOPOLOGY_IDLE_AFTER_OPERATOR_RELEASE',snapshot_sequence=snapshot['sequence'],pid=pid,
                scope='Explicit finger release plus fresh owned foreground topology; no gesture-state instrumentation claim')


def fence(driver, deadline, emit):
    folder=driver.out/'human-release';folder.mkdir(mode=0o700)
    limit=min(deadline-45,time.time()+180)
    require(time.time()+1<limit, 'no release budget; leave task app running')
    request=dict(kind='APP_JOURNEY_RELEASE_REQUIRED',request_id=str(uuid.uuid4()),identity=driver.identity,
                 pid=driver.expected['pid'],issued_at=time.time(),deadline=limit,
                 instruction='The journey stopped. Stop touching the simulator and reply Released in this conversation. Leave the app open.')
    raw=encoded(request);path=folder/'request.json';atomic(path,raw)
    emit('human_status',dict(instruction=request['instruction']))
    emit('human_release',dict(request_path=str(path),**request))
    reply_path=folder/'operator-released.json'
    while not reply_path.exists():
        require(time.time()<limit, 'operator release unconfirmed; leave task app running')
        time.sleep(.2)
    reply_raw=bounded_read(reply_path,16_384);reply=json.loads(reply_raw)
    validate_ack(request,raw,reply,time.time())
    # A distinct cleanup request uses the already-admitted cleanup budget. The
    # original Collector and its expired scenario deadline are never modified.
    collector=driver.collector;native=dict(schema_version=1,**driver.identity,request_id=str(uuid.uuid4()),phase='cleanup.idle')
    native_raw=encoded(native);atomic(folder/'native-request.json',native_raw)
    receipt_path=collector.directory/('checkpoint-'+native['request_id']+'.json')
    require(not receipt_path.exists() and driver.process_live(), 'cleanup process or request stale')
    end=min(deadline,time.time()+30)
    atomic(collector.request_path,native_raw,exclusive=False)
    while not receipt_path.exists():
        require(time.time()<end and driver.process_live(), 'fresh cleanup snapshot unavailable; leave task app running')
        time.sleep(.05)
    receipt_raw=bounded_read(receipt_path,16_384);stream=bounded_read(collector.directory/'events.jsonl',MAX_BYTES)
    atomic(folder/'writer-checkpoint.json',receipt_raw);atomic(folder/'observed-events.jsonl',stream)
    result,snapshot=published_snapshot(stream,json.loads(receipt_raw),native_raw,set(),cost_policy=driver.cost_policy)
    require(stream.startswith(collector.last_prefix) and snapshot['sequence']>collector.last_sequence
            and driver.process_live() and time.time()<end, 'cleanup snapshot is stale or changed the failed capture')
    proof=idle(snapshot,driver.expected['pid'],driver.binding)
    proof.update(operator_sha256=hashlib.sha256(reply_raw).hexdigest(),request_sha256=hashlib.sha256(native_raw).hexdigest(),
                 writer_sha256=hashlib.sha256(receipt_raw).hexdigest(),finished_at=time.time(),deadline=end)
    atomic(folder/'quiescent.json',encoded(proof))
    require(time.time()<end, 'cleanup idle receipt published late')
    return proof


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--request',type=Path,required=True)
    parser.add_argument('--user-message',required=True);args=parser.parse_args()
    acknowledge(args.request,args.user_message)
