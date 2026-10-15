"""Strict local API compatibility assertions; no backend-release acceptance claim."""
import json

CALLS = ['startView','flag','timing','loading','attribute','attributes','removeAttribute','removeAttributes',
         'message','error','request','url','method','action','startAction','stopAction','startOperation',
         'succeedOperation','failOperation','stopView']


def require(value, message):
    if not value: raise ValueError(message)


def validate(receipt, events, run_id, source, mode, pid, os_version):
    require(receipt['run_id']==run_id and receipt['source']==source and receipt['pid']==pid, 'stale or foreign receipt')
    require(receipt['automatic']==mode and receipt['os'].startswith(os_version), 'wrong runtime/configuration')
    require(receipt['scene_unchanged'] is True and receipt['owned_window'] is True, 'lost owned scene/window')
    require(receipt['preflight']['ready'] is True and isinstance(receipt['preflight']['at'],(int,float)), 'precritical readiness missing')
    require(bool(receipt['preflight']['automatic_owner'])==(mode=='on'), 'automatic owner absent before API calls')
    require(receipt['callbacks']==2, 'callback missing or duplicated')
    require(receipt['main']['valid'] is True and receipt['main']['calls']==CALLS, 'incomplete main selector inventory')
    off=receipt['background']
    require(off['calls']==CALLS and off['onMain'] is False, 'incomplete off-main selector inventory')
    require(off['nilFactory'] is True and off['rejectedUnreadScene'] is True, 'off-main factory accepted')
    require(off['sceneReads']==0 and receipt['scene_reads_after_main_turn']==0 and off['releasedScene'] is True, 'UIKit read or deferred retention')
    require('off-main' not in json.dumps(events), 'off-main call changed telemetry')
    require(any(e.get('view',{}).get('name')=='APIClient.FixtureScreen' for e in events)==(mode=='on'), 'automatic tracking prerequisite missing')
    summaries={}
    for lane, name, error_count in [('swift-legacy','swift-legacy',3),('swift-targeted','swift-targeted',3),('objc-main','objc-main-manual',2)]:
        views=[e for e in events if e.get('type')=='view' and e['view'].get('name')==name]
        ids={e['view']['id'] for e in views}; require(len(ids)==1, 'manual occurrence missing or duplicated: '+lane)
        owner=next(iter(ids)); final=max(views,key=lambda e:e['_dd']['document_version'])
        require(final['view']['is_active'] is False and final['context']['stop']==2, 'manual stop or attributes lost')
        owned=[e for e in events if e.get('context',{}).get('lane')==lane and e.get('type')!='view']
        require(all(e.get('view',{}).get('id')==owner for e in owned), 'foreign telemetry owner: '+lane)
        errors=[e for e in owned if e['type']=='error']; require(len(errors)==error_count, 'error missing/duplicate')
        resources=[e for e in owned if e['type']=='resource']; require(len(resources)==3, 'resource missing/duplicate')
        require(all(e['context'].get('finish')==3 and e['resource']['status_code']==200 for e in resources), 'resource completion attributes lost')
        require(sorted(e['resource']['method'] for e in resources)==['GET','GET','PUT'], 'resource methods changed')
        startup=[e for e in owned if e['type']=='action' and e.get('action',{}).get('type')=='application_start']
        require(len(startup)<=1, 'duplicate launch action')
        actions=[e for e in owned if e['type']=='action' and e not in startup]; require(len(actions)==2, 'action pairing changed')
        names=['instant','ended'] if lane.startswith('swift') else ['objc-main','objc-main-ended']
        require(sorted(e['action']['target']['name'] for e in actions)==sorted(names), 'unexpected action names')
        require(sorted(e['context'].get('form') for e in errors)==(['callback','error','message'] if lane.startswith('swift') else ['error','message']), 'unexpected error forms')
        require(sorted(e['context'].get('form') for e in resources)==['method','request','url'], 'unexpected Resource forms')
        require(all(e['resource']['url']=='https://fixture.invalid/'+('resource' if lane.startswith('swift') else lane) for e in resources), 'unexpected Resource URL')
        operations=[e for e in owned if e['type']=='vital' and e.get('vital',{}).get('type')=='operation_step']
        require(len(operations)==3 and sorted(e['vital']['step_type'] for e in operations)==['end','end','start'], 'operation steps changed')
        require(sum(e['vital'].get('failure_reason')=='error' for e in operations)==1, 'operation failure reason lost')
        operation_name='operation' if lane.startswith('swift') else lane
        failure_key=lane+('-failure' if lane.startswith('swift') else '-failed')
        require(all(e['vital']['name']==operation_name for e in operations), 'unexpected Operation name')
        require(sorted((e['vital']['operation_key'],e['vital']['step_type']) for e in operations)==sorted([(lane,'start'),(lane,'end'),(failure_key,'end')]), 'unexpected Operation keys')
        require(len(owned)==len(errors)+len(resources)+len(actions)+len(operations)+len(startup), 'unexpected per-lane event')
        if lane.startswith('swift'):
            require(final['feature_flags']['flag'] is True, 'flag missing')
            require(final['view']['custom_timings']['ready']>=0 and final['view']['loading_time']>=0, 'timing/loading missing')
            require(final['context']['keep-single']=='value' and final['context']['keep-batch']==7, 'view attributes lost')
            require('remove-single' not in final['context'] and 'remove-batch' not in final['context'], 'attribute removal lost')
            require(final['context']['start']==1, 'start attributes lost')
        else:
            require(final['feature_flags']['objc-main'] is True and final['context']['objc-main']=='objc-main', 'ObjC conversion/flag lost')
        summaries[lane]=dict(owner=owner, errors=len(errors),resources=len(resources),actions=len(actions),operations=len(operations))
    require(summaries['swift-legacy']['owner']!=summaries['swift-targeted']['owner'], 'fixture occurrence identities reused')
    guards=[e for e in events if e.get('type')=='view' and e['view'].get('name')=='guard']
    require(len({e['view']['id'] for e in guards})==1, 'guard owner changed')
    final=max(guards,key=lambda e:e['_dd']['document_version'])
    require(final['context']['keep-single']=='single' and final['context']['keep-batch']=='batch', 'off-main removal mutated live view')
    guard_actions=[e for e in events if e.get('type')=='action' and e.get('context',{}).get('lane')=='guard']
    require(len(guard_actions)==1 and guard_actions[0]['action']['target']['name']=='guard-ended', 'off-main action disrupted pairing')
    boundary=receipt['pre_background']
    require(boundary['run_id']==run_id and isinstance(boundary['nonce'],str) and boundary['nonce'], 'missing background boundary identity')
    count=boundary['event_count'];require(type(count) is int and 0<count<len(events),'invalid background boundary')
    guard_owner=final['view']['id']
    delta=events[count:]
    require(all(e.get('view',{}).get('id')==guard_owner and e.get('type') in ['view','action'] for e in delta), 'foreign or unexpected off-main delta')
    delta_actions=[e for e in delta if e.get('type')=='action']
    require(delta_actions==guard_actions, 'off-main boundary lost action pairing')
    allowed={v['owner'] for v in summaries.values()} | {guard_owner}
    for event in events:
        owner=event.get('view',{}).get('id')
        if owner in allowed and event.get('type')!='view':
            require(event.get('context',{}).get('lane') in summaries or event in guard_actions or event.get('action',{}).get('type')=='application_start', 'untagged unexpected owned event')
    return dict(verdict='PASS', lanes=summaries, callbacks=2, objc_selectors=20, ui_accesses=0,
                evidence='optimized local runtime and decoded local intake; no Datadog backend or public promotion claim')
