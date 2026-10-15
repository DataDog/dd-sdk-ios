"""Reuse complete MCP inventories; keep the original uploader alive until sealing."""
import datetime
import json
from pathlib import Path
import sys
import time
import uuid
import ownership_contract as ownership
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'automatic-coverage'))
import human_contract as capture
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'app-acceptance'))
import journey_contract as contract
import journey_transport as transport
from capture_io import atomic, encoded, bounded_read
from acceptance_common import require, Rejected
import s2_hosting_workflow as shared

MAX_BYTES=32*1024*1024


def join(rows,native_rows,local,expected,*,pending=True):
    result=contract.mapped_backend(rows,native_rows,local,expected,pending=pending)
    require(not result['browser'],'unexpected Browser events in native transition fixture')
    payload=contract.backend_event(result['reducer'])
    counts=dict(view=len(local['views']),action=sum(k[0]=='action' for k in local['accepted']),crash=0)
    for family,count in counts.items():
        require(contract.field(payload,'session.'+family+'.count')==count,'session reducer not settled',
                'PENDING' if pending else 'INVALID')
    return dict(native=result,exact_session_counts=counts,
                incidental_disposition='REQUIRES_SOURCE_CLASSIFICATION' if result['incidental'] else 'NONE',
                release_acceptance=False)


def collect(out,identity,rows,expected,started,terminal_at,deadline,*,process_live):
    local=ownership.inventory(rows,identity)
    require(local['session_id']==expected['session_id'],'native query session differs')
    start=datetime.datetime.fromtimestamp(started-120,datetime.timezone.utc).isoformat()
    end=datetime.datetime.fromtimestamp(terminal_at+1,datetime.timezone.utc).isoformat()
    query='@application.id:'+expected['application_id']+' @session.id:'+expected['session_id']
    minimum=len(local['views'])+sum(k[0]!='view' for k in local['accepted'])+1
    require(minimum<=transport.ROW_LIMIT,'native-derived inventory exceeds frozen bound')
    for attempt in range(24):
        try:
            inventories=[];requests=[]
            for selected,threshold in [(query,minimum),(query+' service:'+expected['service']+' source:ios',minimum-1)]:
                require(process_live(),'original background uploader exited before query')
                request=transport.begin(out,dict(run_id=identity['run_id'],nonce=str(uuid.uuid4())),selected,start,end,deadline,minimum_rows=threshold)
                requests.append(str(request));print(json.dumps(dict(backend_request=str(request))),flush=True)
                inventories.append(transport.wait(request,process_live=process_live))
                require(process_live(),'original background uploader exited during query')
            joined=join(*inventories,local,expected)
            result=dict(state='JOINED_FINAL_SOURCE_CLASSIFICATION_REQUIRED',**joined,
                query_interval=dict(start=start,end=end),attempts=attempt+1,inventory_requests=requests,
                completed_at=time.time(),deadline=deadline)
            atomic(out/'backend-joined.json',encoded(result));require(time.time()<deadline,'late backend join publication')
            return result
        except Rejected as error:
            if error.state!='PENDING':raise
            atomic(out/('index-pending-'+str(attempt)+'.json'),encoded(dict(reason=str(error),at=time.time(),deadline=deadline)))
            require(time.time()+10<deadline,'complete inventory unavailable at original deadline');time.sleep(10)
    require(False,'backend polling bound exhausted')


def freeze(collector,out,identity):
    raw=bounded_read(collector.documents/'events.jsonl',MAX_BYTES)
    atomic(out/'terminal-before-collection.jsonl',raw)
    checkpoint=json.loads((collector.output/'background.before/background-checkpoint.json').read_bytes())
    committed=capture.checkpoint(raw,checkpoint,identity['run_id'],checkpoint['request_id'])
    rows=capture.rows(raw,identity['run_id'])
    require(rows[:len(committed)]==committed,'writer prefix differs from full native stream')
    require(sum(r['kind']=='native_background' for r in rows)==1,'missing/duplicate terminal background')
    require(not any(r['kind'] in ['native_input','native_appear','transition_begin','transition_complete','native_model']
                    for r in rows[len(committed):]),'native input occurred outside final writer checkpoint')
    ownership.inventory(rows,identity)
    return raw,rows


def terminal(collector,out,identity,expected,product,installed,device,started,execution_deadline,seconds):
    frozen,rows=freeze(collector,out,identity)
    live=collector.process_live
    require(live(),'background uploader absent before collection')
    require(shared.product(installed,bundle=identity['bundle'])==product,'installed source changed')
    deadline=min(execution_deadline,time.time()+seconds)
    joined=collect(out,identity,rows,expected,started,time.time(),deadline,process_live=live)
    require(live(),'original process replaced before terminal stop')
    shared.command(['xcrun','simctl','terminate',device,identity['bundle']],out,'terminal-stop',deadline=min(deadline,time.time()+30))
    require(not shared.process(identity['pid']),'task process did not exit at final seal')
    raw=bounded_read(collector.documents/'events.jsonl',MAX_BYTES);atomic(out/'sealed-events.jsonl',raw)
    require(raw==frozen,'native stream changed during background collection; frozen inventory incomplete')
    saved=[transport.wait(Path(path)) for path in joined['inventory_requests']]
    sealed=join(*saved,ownership.inventory(capture.rows(raw,identity['run_id']),identity),expected,pending=False)
    require(all(sealed[k]==joined[k] for k in sealed),'sealed stream/backend inventory differs')
    atomic(out/'terminal-rejoin.json',encoded(dict(state='SEALED_STREAM_EQUALS_FROZEN_BACKEND_INVENTORY',
        stream_sha256=shared.sha(out/'sealed-events.jsonl'),backend_join_sha256=shared.sha(out/'backend-joined.json'),
        finished_at=time.time(),deadline=deadline,queries_after_termination=0,release_acceptance=False)))
    require(time.time()<deadline,'terminal rejoin publication late')
    return joined
