"""Remote final stream capture with the existing exact backend inventory join."""
import datetime
import json
from pathlib import Path
import time
import uuid
import backend as common
import physical_ownership as ownership
import physical_rum_contract as rum_contract
from capture_io import atomic, encoded
from acceptance_common import require, Rejected

shared=common.shared


def inventory_bindings(paths):
    result=[]
    for path in map(Path,paths):
        response=path.with_name(path.name.replace('.request.json','.response.json'))
        publication=path.with_name(path.name.removesuffix('.request.json'))/'publication.json'
        result.append(dict(request_sha256=shared.sha(path),response_sha256=shared.sha(response),publication_sha256=shared.sha(publication)))
    return result


def collect(out,identity,rows,expected,started,terminal_at,deadline,*,process_live,evidence_contract=None):
    require(evidence_contract is None or evidence_contract == rum_contract.CONTRACT, 'unknown physical evidence contract')
    local=ownership.inventory(rows,identity)
    require(local['session_id']==expected['session_id'],'physical query session differs')
    start=datetime.datetime.fromtimestamp(started-120,datetime.timezone.utc).isoformat()
    end=datetime.datetime.fromtimestamp(terminal_at+1,datetime.timezone.utc).isoformat()
    query='@application.id:'+expected['application_id']+' @session.id:'+expected['session_id']
    minimum=len(local['views'])+sum(k[0]!='view' for k in local['accepted'])+1
    require(minimum<=common.transport.ROW_LIMIT,'physical inventory exceeds bound')
    for attempt in range(24):
        try:
            inventories=[];requests=[]
            for selected,threshold in [(query,minimum),(query+' service:'+expected['service']+' source:ios',minimum-1)]:
                require(process_live(),'physical background uploader exited')
                request=common.transport.begin(out,dict(run_id=identity['run_id'],nonce=str(uuid.uuid4())),selected,start,end,deadline,minimum_rows=threshold)
                requests.append(str(request));print(json.dumps(dict(backend_request=str(request))),flush=True)
                inventories.append(common.transport.wait(request,process_live=process_live))
                require(process_live(),'physical uploader exited during query')
            if evidence_contract is None:
                joined=common.join(*inventories,local,expected)
                state='JOINED_FINAL_SOURCE_CLASSIFICATION_REQUIRED'
            else:
                assessment=rum_contract.assess(*inventories,rows,identity,expected)
                atomic(out/('rum-fields-assessment-'+str(attempt)+'.json'),encoded(dict(
                    state='RUM_FIELDS_ASSESSED' if assessment['state']=='RUM_FIELDS_QUALIFIED' else 'RUM_FIELDS_'+assessment['state'],
                    evidence_contract=evidence_contract,assessment=assessment,inventory_requests=requests,
                    completed_at=time.time(),deadline=deadline)))
                require(time.time()<deadline,'late physical RUM-fields assessment')
                require(assessment['state']=='RUM_FIELDS_QUALIFIED','physical RUM-fields '+assessment['state'],
                    'PENDING' if assessment['state']=='PENDING' else 'INVALID')
                joined=dict(evidence_contract=evidence_contract,rum_fields=assessment,release_acceptance=False,
                            inventory_bindings=inventory_bindings(requests))
                state='RUM_FIELDS_JOINED_SOURCE_CLASSIFICATION_REQUIRED'
            result=dict(state=state,**joined,query_interval=dict(start=start,end=end),
                attempts=attempt+1,inventory_requests=requests,completed_at=time.time(),deadline=deadline)
            atomic(out/'backend-joined.json',encoded(result));require(time.time()<deadline,'late physical backend publication');return result
        except Rejected as error:
            if error.state!='PENDING':raise
            atomic(out/('index-pending-'+str(attempt)+'.json'),encoded(dict(reason=str(error),at=time.time(),deadline=deadline)))
            require(time.time()+10<deadline,'incomplete backend at original deadline');time.sleep(10)
    require(False,'physical backend polling exhausted')


def terminal(collector,out,identity,expected,started,execution_deadline,*,evidence_contract=None):
    require(evidence_contract is None or evidence_contract == rum_contract.CONTRACT, 'unknown physical evidence contract')
    deadline=min(execution_deadline,time.time()+600)
    raw=collector.download('events.jsonl',deadline);atomic(out/'terminal-before-collection.jsonl',raw)
    checkpoint=json.loads((collector.output/'background.before/background-checkpoint.json').read_bytes())
    committed=common.capture.checkpoint(raw,checkpoint,identity['run_id'],checkpoint['request_id'])
    rows=common.capture.rows(raw,identity['run_id']);require(rows[:len(committed)]==committed,'physical writer prefix differs')
    require(sum(r['kind']=='native_background' for r in rows)==1 and not any(r['kind'] in
        ['native_input','native_appear','transition_begin','transition_complete','native_model'] for r in rows[len(committed):]),
        'unplanned physical input after background boundary')
    joined=collect(out,identity,rows,expected,started,time.time(),deadline,process_live=collector.process_live,evidence_contract=evidence_contract)
    require(collector.process_live(),'physical uploader replaced before stop')
    collector.remote.command(['device','process','terminate','--pid',str(identity['pid'])],'terminal-stop',deadline)
    require(not any(p['processIdentifier']==identity['pid'] for p in collector.remote.processes('terminal-process-absence',deadline)),
            'physical process remains after termination')
    sealed=collector.download('events.jsonl',deadline);atomic(out/'sealed-events.jsonl',sealed)
    require(sealed==raw,'physical stream changed during backend collection')
    if evidence_contract is not None:
        require(joined['inventory_bindings']==inventory_bindings(joined['inventory_requests']),'physical saved inventory changed')
    saved=[common.transport.wait(Path(p)) for p in joined['inventory_requests']]
    if evidence_contract is None:
        final=common.join(*saved,ownership.inventory(common.capture.rows(sealed,identity['run_id']),identity),expected,pending=False)
    else:
        assessment=rum_contract.assess(*saved,common.capture.rows(sealed,identity['run_id']),identity,expected,pending=False)
        require(assessment['state']=='RUM_FIELDS_QUALIFIED','sealed physical RUM-fields incomplete')
        final=dict(evidence_contract=evidence_contract,rum_fields=assessment,release_acceptance=False)
    require(all(final[k]==joined[k] for k in final),'physical sealed backend join differs')
    scoped=dict(evidence_contract=evidence_contract) if evidence_contract is not None else {}
    atomic(out/'terminal-rejoin.json',encoded(dict(**scoped,state='SEALED_STREAM_EQUALS_FROZEN_BACKEND_INVENTORY',
        stream_sha256=shared.sha(out/'sealed-events.jsonl'),backend_join_sha256=shared.sha(out/'backend-joined.json'),
        finished_at=time.time(),deadline=deadline,queries_after_termination=0,release_acceptance=False)))
    require(time.time()<deadline,'late physical terminal rejoin');return joined
