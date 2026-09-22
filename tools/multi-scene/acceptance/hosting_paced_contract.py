"""Human pacing adds causal observations without relaxing the existing H16 oracle."""
from acceptance_common import require, unique
from app_journey_inventory import identifier
import hosting_contract

PHASES = ['push', 'pop', 'present', 'dismiss']


def local(document, identity):
    require(identity['arm']=='B' and identity['mode']=='manual','only remaining manual candidate admitted')
    accepted=hosting_contract.local(document,identity)
    records=document['records'];scene=unique([r for r in records if r['kind']=='scene-connected'],'owned scene')
    require(not any(r['kind']=='human-input-rejected' for r in records),'rejected/late human input')
    ready=[r for r in records if r['kind']=='human-ready'];inputs=[r for r in records if r['kind']=='human-input']
    require([r['phase'] for r in ready]==PHASES and [r['phase'] for r in inputs]==PHASES,'missing/extra/reordered human input')
    controllers={r['phase']:r['controller'] for r in records if r['kind']=='boundary'}
    expected_ids={'root':scene['root_controller'],'detail':controllers['push'],'modal':controllers['present']}
    request_ids=[]
    for index,(request,actual) in enumerate(zip(ready,inputs)):
        phase=PHASES[index];identifier(request['request_id']);request_ids.append(request['request_id'])
        boundary=unique([r for r in records if r['kind']=='boundary' and r['phase']==hosting_contract.PHASES[index]],'preceding visible boundary')
        transition=unique([r for r in records if r['kind']=='transition-start' and r['phase']==phase],'following transition')
        require(boundary['sequence']<request['sequence']<actual['sequence']<transition['sequence'],'input not between ready ownership and transition')
        require(request['control']=='hosting.'+phase and request['request_id']==actual['request_id'],'stale/aliased native control')
        require(request['controller']==actual['controller']==boundary['controller']
                and request['window']==actual['window']==scene['window'],'human input belongs to foreign controller/window')
        issued,deadline,consumed=request.get('issued_ns'),request.get('deadline_ns'),actual.get('consumed_ns')
        require(all(type(v) is int for v in [issued,deadline,consumed])
                and 0<=issued<=request['monotonic_ns']<=consumed<deadline
                and consumed<=actual['monotonic_ns'] and 0<deadline-issued<=180_000_000_000,'human input outside app-local deadline')
        prior=[r for r in records if r['sequence']<request['sequence']]
        require([r['name'] for r in prior if r['kind']=='swiftui-appear']==hosting_contract.NAMES[:index+1]
                and [r['name'] for r in prior if r['kind']=='swiftui-disappear']==hosting_contract.NAMES[:index],
                'human control appeared before the preceding lifetime callbacks')
        attachments=request['attachments'];names=['root']+(['detail'] if index>=1 else [])+(['modal'] if index>=3 else [])
        require(set(attachments)==set(names),'attachment inventory incomplete')
        for name,attachment in attachments.items():
            require(set(attachment)=={'controller','loaded','window'} and attachment['controller']==expected_ids[name]
                    and type(attachment['loaded']) is bool and attachment['window'] in [None,scene['window']]
                    and (attachment['window'] is None or attachment['loaded']),'attachment identity/ownership differs')
        current=next(a for a in attachments.values() if a['controller']==boundary['controller'])
        require(current['loaded'] is True and current['window']==scene['window'],'visible controller detached at ready input')
    require(len(set(request_ids))==4,'consumed readiness reused')
    return dict(accepted,human_input={'state':'QUALIFIED','requests':request_ids,'attachment_observations':4})
