"""Finish the fixture's bounded Home task after two complete event inventories."""
import hashlib
import json
import uuid
import human_contract as oracle
import local_event_collection
import s2_hosting_workflow as shared
from acceptance_common import require


def digest(raw):return hashlib.sha256(raw).hexdigest()


def ready(raw, before_bytes, checkpoint_bytes, idle_bytes, *, run, pid):
    value=json.loads(raw);request=json.loads(before_bytes)
    require(set(value)=={'schema_version','state','run_id','pid','request_id','request_sha256','checkpoint_sha256','idle_sha256'}
        and type(value['schema_version']) is int and value['schema_version']==1 and value['state']=='READY'
        and value['run_id']==request['run_id']==run and value['pid']==pid
        and value['request_id']==request['request_id'] and request['phase']=='background.before'
        and value['request_sha256']==digest(before_bytes) and value['checkpoint_sha256']==digest(checkpoint_bytes)
        and value['idle_sha256']==digest(idle_bytes),'foreign, stale or incomplete Home ready receipt')
    return value


def completion(raw, before_bytes, finish_bytes, first_checkpoint, final_checkpoint, idle_bytes, *, run, pid):
    value=json.loads(raw);before=json.loads(before_bytes);finish=json.loads(finish_bytes)
    require(set(value)=={'schema_version','run_id','request_id','request_sha256','pid','state','finish_request_id',
        'finish_request_sha256','first_checkpoint_sha256','final_checkpoint_sha256','idle_sha256','app_state','task_was_valid'}
        and type(value['schema_version']) is int and value['schema_version']==1
        and value['state']=='END_REQUESTED' and value['task_was_valid'] is True
        and type(value['app_state']) is int and value['app_state']==2
        and value['run_id']==before['run_id']==finish['run_id']==run and value['pid']==pid
        and value['request_id']==before['request_id'] and before['phase']=='background.before'
        and value['request_sha256']==digest(before_bytes) and finish['phase']=='background.finish'
        and value['finish_request_id']==finish['request_id'] and value['finish_request_sha256']==digest(finish_bytes)
        and value['first_checkpoint_sha256']==digest(first_checkpoint)
        and value['final_checkpoint_sha256']==digest(final_checkpoint) and value['idle_sha256']==digest(idle_bytes),
        'Home task expired, failed, returned to foreground or has foreign completion bindings')
    return value


def await_ready(collector,folder,identifier,deadline):
    before=(folder/'request.json').read_bytes();request=json.loads(before)
    task=collector.documents/('home-task-'+request['request_id']+'.json')
    path=collector.documents/('home-ready-'+request['request_id']+'.json')
    checkpoint=collector.documents/('events-checkpoint-'+identifier+'.json')
    idle=collector.documents/('home-input-idle-'+request['request_id']+'.json')
    def published():
        require(not task.exists(),'Home task ended or expired before terminal inventory')
        if not path.exists():return None
        require(checkpoint.is_file() and idle.is_file(),'Home ready preceded its writer files')
        raw=path.read_bytes()
        ready(raw,before,checkpoint.read_bytes(),idle.read_bytes(),run=collector.run,pid=collector.pid)
        (folder/'home-ready.json').write_bytes(raw)
        return True
    collector.wait(published,deadline)


def finish(collector,folder,rows,deadline,*,terminal=None,completion_scope=None):
    if terminal is None:
        terminal=lambda raw,*,prefix:local_event_collection.terminal_rows(raw,run_id=collector.run,prefix=prefix)
    before=(folder/'request.json').read_bytes();request=json.loads(before)
    first=(folder/'background-checkpoint.json').read_bytes()
    prefix=(folder/'background-events.jsonl').read_bytes()
    initial=(folder/'background-collected-events.jsonl').read_bytes()
    require(terminal(initial,prefix=prefix)==rows,
        'Home finish requires the complete original terminal inventory')
    idle=(folder/'home-input-idle.json').read_bytes()
    ack={'schema_version':1,'run_id':collector.run,'request_id':str(uuid.uuid4()),'phase':'background.finish',
        'home':dict(request_id=request['request_id'],request_sha256=digest(before),pid=collector.pid,
            **{k:collector.binding[k] for k in ['window','root','scene']},checkpoint_sha256=digest(first),
            idle_sha256=digest(idle),terminal_byte_count=len(initial),terminal_sha256=digest(initial))}
    shared.save(folder/'home-finish-request.json',ack,exclusive=True)
    ack_bytes=(folder/'home-finish-request.json').read_bytes()
    task=collector.documents/('home-task-'+request['request_id']+'.json')
    require(not task.exists(),'Home task was already consumed before finish')
    collector.live(deadline);shared.save(collector.documents/'human-snapshot-request.json',ack)
    collector.wait(lambda:task if task.exists() else None,deadline)
    end=task.read_bytes();final_path=collector.documents/('events-checkpoint-home-finish-'+ack['request_id']+'.json')
    require(json.loads(end).get('state')=='END_REQUESTED','Home task failed or expired')
    require(final_path.is_file(),'Home task ended before its final writer checkpoint')
    final=final_path.read_bytes()
    completion(end,before,ack_bytes,first,final,idle,run=collector.run,pid=collector.pid)
    raw=(collector.documents/'events.jsonl').read_bytes();final_receipt=json.loads(final)
    final_rows=oracle.checkpoint(raw,final_receipt,collector.run,'home-finish-'+ack['request_id'])
    require(raw.startswith(initial),'Home finalization changed the first terminal inventory')
    require(len(final_rows)>=len(rows),'Home final checkpoint predates the first terminal inventory')
    result=terminal(raw,prefix=prefix)
    require(result is not None,'Home inventory became incomplete after the first terminal check')
    collector.live(deadline)
    (folder/'home-task.json').write_bytes(end);(folder/'home-final-checkpoint.json').write_bytes(final)
    (folder/'home-final-events.jsonl').write_bytes(raw)
    shared.save(folder/'home-completion.json',dict(state='FINAL_INVENTORY_REVALIDATED',run_id=collector.run,
        task_state='END_REQUESTED',before_request_sha256=digest(before),finish_request_sha256=digest(ack_bytes),
        initial_inventory_sha256=digest(initial),final_inventory_sha256=digest(raw),final_sequence=result[-1]['sequence'],
        **(completion_scope or {})),exclusive=True)
    return result
