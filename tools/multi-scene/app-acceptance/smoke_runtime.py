"""Bound ordinary upload collection to an immutable F08 behavior prefix."""
import datetime
from pathlib import Path
import time
import uuid

import journey_builds as builds
import journey_contract as contract
import journey_transport as transport
import smoke_contract as smoke
from journey_driver import emit
from capture_io import atomic, encoded, bounded_read
from capture_contract import loads, MAX_BYTES
from acceptance_common import require, Rejected
import s2_hosting_workflow as shared


def collected(out, identity, expected, behavior, frozen, checkpoint, driver, native, started, deadline):
    local=contract.mapper_inventory(behavior,expected)
    browser=smoke.browser.local_inventory(behavior,expected)
    native_min=len(local['views'])+sum(k[0]!='view' for k in local['accepted'])
    broad_min=native_min+len(browser['latest'])+sum(k[0]!='view' for k in browser['events'])
    require(broad_min<=transport.ROW_LIMIT,'frozen behavior exceeds backend inventory bound')
    start=datetime.datetime.fromtimestamp(started-120,datetime.timezone.utc).isoformat()
    # Queries remain open to ordinary delivery; membership is fixed by the
    # writer-backed behavior prefix, never by a later event that looks similar.
    query='@application.id:'+expected['application_id']+' @session.id:'+expected['session_id']
    for attempt in range(24):
        require(time.time()<deadline and driver.process_live(),'delivery deadline or original process lost')
        try:
            values=[];requests=[]
            for selected,minimum in [(query,broad_min),(query+' service:'+expected['service']+' source:ios',native_min)]:
                path=transport.begin(out,dict(run_id=identity['run_id'],nonce=str(uuid.uuid4())),selected,start,'now',deadline,minimum_rows=minimum)
                requests.append(str(path));emit('backend_request',str(path))
                values.append(transport.wait(path,process_live=driver.process_live))
            raw=bounded_read(driver.collector.directory/'events.jsonl',MAX_BYTES)
            atomic(out/('delivery-'+str(attempt)+'.jsonl'),raw)
            captured=smoke.tail(raw,frozen,checkpoint,identity)
            result=smoke.joined(values[0],values[1],behavior,captured['rows'],native['j03'],expected)
            result.update(completed_at=time.time(),deadline=deadline,inventory_requests=requests,
                          behavior_sha256=checkpoint['sha256'],cutoff_sequence=checkpoint['sequence'],
                          delivery_capture=str(out/('delivery-'+str(attempt)+'.jsonl')),delivery_sha256=captured['readback_sha256'],
                          attempts=attempt+1,query_start=start)
            atomic(out/'backend-joined.json',encoded(result))
            require(time.time()<deadline,'smoke backend publication late')
            return result
        except Rejected as error:
            if error.state!='PENDING':raise
            atomic(out/('smoke-pending-'+str(attempt)+'.json'),encoded(dict(reason=str(error),at=time.time(),deadline=deadline)))
            require(time.time()+10<deadline,'smoke delivery incomplete at fixed deadline');time.sleep(10)
    require(False,'smoke backend polling bound exhausted')


def terminal_capture(driver,native,out,identity,configuration,expected,installed,manifest,
                     device,bundle,pid,started,execution_deadline,backend_seconds):
    require(native['mode'] in smoke.MODES and native['terminal']['foreground'] is True,'wrong smoke terminal phase')
    checkpoint=loads((out/'behavior-checkpoint.json').read_bytes())
    require(checkpoint==native['terminal']['checkpoint'],'behavior checkpoint changed')
    frozen=bounded_read(out/'behavior-prefix.jsonl',MAX_BYTES)
    behavior=smoke.freeze(frozen,checkpoint,identity)[1]['rows']
    require(smoke.native_manifest(behavior,native,expected,driver.definition)==native['manifest'],'source-defined behavior manifest changed')
    require(driver.process_live(),'original foreground process exited before ordinary delivery')
    builds.product(installed,manifest)
    deadline=min(execution_deadline,time.time()+backend_seconds)
    joined=collected(out,identity,expected,behavior,frozen,checkpoint,driver,native,started,deadline)
    require(driver.process_live(),'original foreground process replaced before final seal')
    shared.command(['xcrun','simctl','terminate',device,bundle],out,'terminal-stop',deadline=min(deadline,time.time()+30))
    require(not shared.process(pid),'task process did not exit at final seal')
    raw=bounded_read(driver.collector.directory/'events.jsonl',MAX_BYTES)
    full=contract.sealed_stream(raw,checkpoint,identity,configuration,process_exited=True,cost_policy=smoke.COST_POLICY)
    tail=smoke.tail(raw,frozen,checkpoint,identity)
    atomic(out/'observer-cost.json',encoded(full['observer_cost']))
    atomic(out/'sealed-events.jsonl',raw)
    atomic(out/'stream-seal.json',encoded({k:v for k,v in full.items() if k!='rows'}))
    # No backend call after termination; replay saved complete responses only.
    values=[transport.wait(Path(path)) for path in joined['inventory_requests']]
    final=smoke.joined(values[0],values[1],behavior,full['rows'],native['j03'],expected,pending=False)
    require(all(final[key]==joined[key] for key in final),'saved smoke backend result changed at final seal')
    proof=dict(state='SMOKE_BEHAVIOR_AND_DELIVERY_SEALED',mode=native['mode'],identity=identity,expected=expected,
               behavior_sha256=checkpoint['sha256'],cutoff_sequence=checkpoint['sequence'],
               checkpoint_sha256=builds.sha(out/'behavior-checkpoint.json'),
               sealed_sha256=builds.sha(out/'sealed-events.jsonl'),backend_join_sha256=builds.sha(out/'backend-joined.json'),
               manifest=native['manifest'],observer_cost=full['observer_cost'],observer_cost_sha256=builds.sha(out/'observer-cost.json'),
               semantic_observation='COMPLETE_REQUIRES_PAIRED_SOURCE_REVIEW',performance_acceptance=False,
               later_record_count=len(tail['later']),
               later_kinds=sorted({r['kind'] for r in tail['later']}),
               completed_at=time.time(),deadline=deadline,queries_after_termination=0,forced_flushes=0,
               extra_home_steps=0,runtime_acceptance=False)
    atomic(out/'smoke-evidence.json',encoded(proof));require(time.time()<deadline,'smoke final evidence publication late')
    return joined
