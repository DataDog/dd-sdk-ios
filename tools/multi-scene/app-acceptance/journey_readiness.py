"""Classify refresh traffic before reacquiring a real native readiness snapshot."""
import hashlib

import journey_contract as contract
import browser_contract
from capture_contract import prefix, STRICT_COST_POLICY
from acceptance_common import require


def readback(raw, checkpoint, identity, *, cost_policy=STRICT_COST_POLICY):
    """Validate all currently persisted bytes without calling them a writer seal."""
    prefix(raw,checkpoint,identity,cost_policy=cost_policy)
    require(raw.endswith(b'\n'),'partial persisted observation tail')
    receipt=dict(schema_version=1,identity=identity,request_id=checkpoint['request_id'],success=True,
                 sequence=len(raw.splitlines()),byte_count=len(raw),sha256=hashlib.sha256(raw).hexdigest())
    return prefix(raw,receipt,identity,cost_policy=cost_policy)['rows']


def pending_refresh(rows, snapshot, expected):
    require(snapshot in rows,'foreign readiness snapshot')
    pending=[r for r in rows if r['sequence']>snapshot['sequence']]
    require(pending and pending[0]['kind']=='observer_cost' and
            pending[0]['fields']['event_sequence']==snapshot['sequence'],'missing snapshot cost')
    require(all(r['request_id']==snapshot['request_id'] and r['phase']==snapshot['phase'] for r in pending),
            'request changed before prompt')
    events=[r for r in pending[1:] if r['kind']!='observer_cost']
    require(events and any(r['kind'] in ['mapper','browser_message'] for r in events), 'no qualifying refresh traffic')
    require(all(r['kind'] in ['context','mapper','browser_message'] for r in events),'native readiness consumed by transition')
    before=[r for r in rows if r['sequence']<snapshot['sequence']]
    context=contract.one([r for r in before if r['sequence']==snapshot['last_context_sequence'] and r['kind']=='context'],'readiness context')['fields']
    require(all(r['fields']==context for r in events if r['kind']=='context'),'context owner or clock changed before prompt')
    old=contract.mapper_inventory(before,expected);current=contract.mapper_inventory(rows,expected)
    require(set(old['views'])==set(current['views']),'refresh created another native occurrence')
    stable=['view.id','view.name','view.url','view.is_active','application.id','session.id','session.has_replay','service','source','usr.anonymous_id']
    for vid,value in old['views'].items():
        require(all(contract.field(value['event'],key)==contract.field(current['views'][vid]['event'],key) for key in stable),
                'refresh changed native owner or eligibility')
    browser=[r for r in events if r['kind']=='browser_message']
    if browser:
        previous=browser_contract.local_inventory(before,expected);updated=browser_contract.local_inventory(rows,expected)
        require(previous['source_identity']==updated['source_identity'] and previous['clocks']==updated['clocks']
                and set(previous['latest'])==set(updated['latest']),'refresh changed Browser source/view/clock')
        for row in browser:
            dispatch=browser_contract.context(rows,row,expected)
            require(dispatch==context,'refresh Browser dispatch context changed')
    return dict(state='REFRESH_REQUIRES_NEW_NATIVE_SNAPSHOT',pending_sequences=[r['sequence'] for r in events],
                original_snapshot_sequence=snapshot['sequence'],runtime_acceptance=False)
