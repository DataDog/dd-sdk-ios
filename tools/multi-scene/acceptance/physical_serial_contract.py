"""H05/H07 physical serial semantics, exact native work and complete backend joins."""
import json
import re
from pathlib import Path
from acceptance_common import require, require_before, require_identity, unique
from physical_same_key_contract import validate_backend as complete_rum_inventory

APP_ID = '43cbc59b-0626-438b-a3d9-c6417a4545a3'
SERVICE = 'ios-sdk-native-multi-scene-probe'
SHARED = 'trace-only-shared-request'


def validate_local(records, run_id, gate):
    require(gate in ['H05', 'H07'], 'unknown physical serial gate')
    expected = json.loads(Path(__file__).with_name('physical-serial-scenario-contracts.json').read_text())[gate]
    manifest = unique([r['manifest'] for r in records if r['type'] == 'manifest'], 'manifest')
    require(manifest.get('runID') == run_id and manifest.get('runMode') == 'clean'
            and not manifest.get('validationErrors'), 'stale/invalid serial manifest')
    require_identity(manifest.get('scenario'), expected, 'serial scenario')
    signals = [r['signal'] for r in records if r['type'] == 'signal']
    require(signals and all(s.get('runID') == run_id and s.get('scenarioID') == expected['identifier']
                           and s.get('schemaVersion') == 5 for s in signals), 'stale serial signal')
    require([s['sequence'] for s in signals] == list(range(1, len(signals)+1)), 'incomplete signal sequence')
    require(not any(s.get('result') in ['FAIL', 'INCONCLUSIVE'] for s in signals), 'native serial assertion failed', 'FAIL')
    terminal = unique([r for r in records if r['type'] == 'semantic-result'], 'terminal')
    result = terminal.get('result', {})
    require(terminal.get('runID') == run_id and result.get('scenarioID') == expected['identifier']
            and result.get('state') == 'PASS' and not result.get('issues')
            and result.get('matchedExpectationCount') == (7 if gate == 'H05' else 8), 'original serial expectations failed', 'FAIL')
    starts = [s for s in signals if s.get('kind') == 'step-started']
    acks = [s for s in signals if s.get('kind') == 'step-acknowledged']
    require(len(starts) == len(acks) == len(expected['steps']), 'missing serial driver steps')
    for i, (step, start, ack) in enumerate(zip(expected['steps'], starts, acks)):
        require(start.get('stepIndex') == ack.get('stepIndex') == i
                and start.get('stepKind') == ack.get('stepKind') == step['kind'], 'driver step identity')
        require_before(start, ack, 'acknowledgement')
        evidence = unique([s for s in signals if s['sequence'] == ack.get('acknowledgedSignalSequence')], 'acknowledged evidence')
        require_before(evidence, ack, 'evidence before ack')
        if step['kind'] not in ['wait-for-scene-ready', 'wait-for-signal']:
            require_before(start, evidence, 'fresh command evidence')
        if i+1 < len(starts): require_before(ack, starts[i+1], 'ordered driver')
    native = {}
    for label in ['scene-A', 'scene-B']:
        ready = unique([s for s in signals if s.get('kind') == 'scene-ready'
                        and s.get('semanticContext', {}).get('logicalSceneID') == label], 'native readiness '+label)
        native[label] = ready.get('semanticContext', {}).get('nativeSceneID')
    require(all(native.values()) and len(set(native.values())) == 2, 'native scenes alias')
    snapshots = [s for s in signals if s.get('kind') == 'rum-view-snapshot']
    views = {}
    for s in snapshots:
        c = s.get('rumContext', {})
        require(s.get('evidenceSource') == 'rum-mapper' and c.get('viewID') and c.get('sessionID'), 'independent mapper view missing')
        v = dict(view_id=c['viewID'], session_id=c['sessionID'], name=c.get('viewName'))
        require(c['viewID'] not in views or views[c['viewID']] == v, 'mutable native view identity')
        views[c['viewID']] = v
    require(views and len({v['session_id'] for v in views.values()}) == 1, 'native session changed')
    session = next(iter(views.values()))['session_id']
    work = []
    for s in signals:
        kind = s.get('kind')
        require(kind != 'rum-error', 'native RUM error', 'FAIL')
        if kind not in ['rum-action', 'rum-resource']: continue
        c, source = s.get('rumContext', {}), s.get('sourceContext', {})
        require(s.get('evidenceSource') == 'rum-mapper' and c.get('sessionID') == session
                and c.get('viewID') in views and s.get('eventID'), 'missing work identity or independent owner', 'FAIL')
        work.append(dict(kind=kind.removeprefix('rum-'),event_id=s['eventID'],session_id=session,
                         view_id=c['viewID'],phase=s.get('name'),source_scene=source.get('logicalSceneID')))
    require(len({(w['kind'], w['event_id']) for w in work}) == len(work), 'duplicate native work')

    def marker(phase, label, step):
        pair = [unique([s for s in signals if s.get('kind') == kind and s.get('name') == phase], phase+' '+kind)
                for kind in ['rum-action','rum-resource']]
        owner = pair[0]['rumContext']['viewID']
        for signal in pair:
            source = signal.get('sourceContext', {})
            require(signal['rumContext']['viewID'] == owner and source.get('logicalSceneID') == label
                    and source.get('nativeSceneID') == native[label], 'marker pair source/owner differs', 'FAIL')
            require_before(starts[step], signal, 'marker after its own command')
            earlier = [s for s in snapshots if s['rumContext']['viewID'] == owner and s['sequence'] < signal['sequence']]
            require(earlier and earlier[-1]['rumContext'].get('viewActive') is True, 'marker on stopped/missing view', 'FAIL')
        return owner

    phases = ['semantic-a-before-peer','automatic-b-after-ready'] if gate == 'H05' else ['trace-shared-creator-representative','trace-shared-consumer-representative']
    indices = [1,4] if gate == 'H05' else [2,6]
    owners = {label: marker(phase,label,index) for phase,label,index in zip(phases,['scene-A','scene-B'],indices)}
    require(len(set(owners.values())) == 2, 'peer marker owner aliases', 'FAIL')
    for label in ['scene-A'] if gate == 'H05' else ['scene-A','scene-B']:
        own = [s for s in snapshots if s.get('semanticContext',{}).get('logicalSceneID') == label
               and s.get('semanticContext',{}).get('screen') == 'home']
        require(own and {s['rumContext']['viewID'] for s in own} == {owners[label]}, 'missing/extra semantic Home', 'FAIL')
        require(all(s['semanticContext'].get('nativeSceneID') in [None,native[label]] for s in own), 'semantic native source differs')
    if gate == 'H05':
        b = [s for s in snapshots if s['rumContext']['viewID'] == owners['scene-B']]
        require(b and all(not s.get('semanticContext') for s in b), 'automatic B unexpectedly semantic', 'FAIL')
        require_before(starts[2],b[0],'new automatic B view after open')
        require(not any(s.get('kind') == 'rum-trace' for s in signals), 'unexpected Trace')
        automatic = {s['rumContext']['viewID'] for s in snapshots
                     if not s.get('semanticContext') and s['sequence'] > starts[2]['sequence']}
        first_automatic = min(s['sequence'] for s in snapshots if s['rumContext']['viewID'] in automatic)
        compatibility_fallback = []
        for item in work:
            if item['source_scene'] == 'scene-A':
                require(item['view_id'] == owners['scene-A'], 'semantic A work owned by peer', 'FAIL')
            elif item['source_scene'] == 'scene-B' and item['view_id'] not in automatic:
                require(item['view_id'] == owners['scene-A'] and item['phase'] in
                        ['navigation-appearance-1','on-appear','task-immediate'], 'B work outside declared automatic fallback', 'FAIL')
                start_work = unique([s for s in signals if s.get('kind') == 'rum-action'
                                     and s.get('name') == item['phase'] and s.get('sourceContext',{}).get('logicalSceneID') == 'scene-B'], 'fallback call phase')
                require(start_work['sequence'] < first_automatic, 'fallback after automatic B discovery', 'FAIL')
                compatibility_fallback.append(item)
            else:
                require(item['source_scene'] == 'scene-B', 'unknown work source', 'FAIL')
    local = dict(state='PASS', gate=gate,session_id=session,native_scenes=native,owners=owners,
                 views=list(views.values()),work=work,simultaneous_visibility_claimed=False)
    if gate == 'H05':
        local['documented_source_less_fallback'] = compatibility_fallback
    if gate == 'H07':
        trace_signal = unique([s for s in signals if s.get('kind') == 'rum-trace'], 'one shared automatic span')
        t, c = trace_signal.get('trace', {}), trace_signal.get('rumContext', {})
        require(trace_signal.get('evidenceSource') == 'trace-mapper' and trace_signal.get('name') == SHARED
                and trace_signal.get('sourceContext',{}).get('logicalSceneID') == 'scene-A'
                and trace_signal.get('sourceContext',{}).get('screen') == 'home', 'wrong trace source')
        require(c.get('viewID') == t.get('rumViewID') == owners['scene-A'] and c.get('sessionID') == t.get('rumSessionID') == session
                and t.get('rumApplicationID') == APP_ID, 'shared request retargeted or correlation missing', 'FAIL')
        require(c.get('actionIDs') in [None,[]] and t.get('rumActionIDs') in [None,[]], 'foreign action inherited', 'FAIL')
        require(t.get('operationName') == 'urlsession.request' and t.get('serviceName') == SERVICE and t.get('isError') is False, 'span metadata/error')
        require(re.fullmatch('[a-f0-9]{32}',t.get('traceID','')) and re.fullmatch('[a-f0-9]{16}',t.get('spanID',''))
                and trace_signal.get('eventID') == t['spanID'] and re.fullmatch('[a-f0-9]{16}',t.get('parentSpanID','')), 'missing exact span identity')
        require(type(t.get('startTimeNanoseconds')) is int and type(t.get('durationNanoseconds')) is int
                and t['durationNanoseconds'] > 0 and t['startTimeNanoseconds']//1_000_000 == t.get('startTimeMilliseconds'), 'missing integer wire timing')
        for suffix,label,index in [('started','scene-A',3),('joined','scene-B',7),('completed','scene-A',8)]:
            s = unique([s for s in signals if s.get('name') == 'trace-only-request-'+suffix+'-'+SHARED], suffix+' request')
            require(s.get('result') == 'PASS' and s.get('sourceContext',{}).get('logicalSceneID') == label, 'request boundary source/result')
            require_before(starts[index],s,'fresh request '+suffix)
            if suffix=='started':require_before(s,starts[4],'creator before peer open')
            if suffix=='joined':require_before(s,starts[8],'join before release')
        require_before(starts[8],trace_signal,'span completed after B release')
        require(not any(s.get('kind') == 'rum-resource' and s.get('resource',{}).get('url') == t.get('resourceName') for s in signals), 'trace-only request emitted RUM Resource', 'FAIL')
        local['span'] = t
    return local


def validate_backend(local,run_id,rows,count):
    result = complete_rum_inventory(local,run_id,rows,count)
    result['marker_pairs'] = 2
    if local['gate']=='H07':
        require(not any(r.get('attributes',{}).get('custom',{}).get('resource',{}).get('url') == local['span']['resourceName'] for r in rows), 'trace-only backend Resource', 'FAIL')
    return result


def validate_shared_span_backend(local, run_id, spans, count, details):
    from decimal import Decimal, InvalidOperation
    from datetime import datetime, timezone
    require(local.get('gate') == 'H07' and count == len(spans) == len(details) == 1,
            'missing/duplicate backend shared span', 'FAIL')
    expected = local['span'];row=spans[0];detail=details[0]
    def hex_id(value):
        require(isinstance(value,str) and value.isdigit() and 0 <= int(value) < 2**64, 'invalid backend decimal ID')
        return format(int(value),'016x')
    require(row.get('traceid') == expected['traceID'] and hex_id(row.get('spanid')) == expected['spanID']
            and hex_id(detail.get('span_id')) == expected['spanID']
            and hex_id(row.get('parentid')) == hex_id(detail.get('parent_id')) == expected['parentSpanID'], 'backend exact span IDs differ', 'FAIL')
    custom=row.get('custom',{});meta=detail.get('meta',{})
    require(custom.get('probe',{}).get('run_id') == meta.get('probe.run_id') == run_id
            and meta.get('_dd.p.ftid') == expected['traceID'], 'backend run/full trace identity differs', 'FAIL')
    for key,field in [('application','rumApplicationID'),('session','rumSessionID'),('view','rumViewID')]:
        require(meta.get('_dd.'+key+'.id') == expected[field], 'captured backend '+key+' differs', 'FAIL')
    require(meta.get('_dd.action.id') is None, 'foreign backend action', 'FAIL')
    require(row.get('operationname') == detail.get('name') == expected['operationName']
            and row.get('service') == detail.get('service') == expected['serviceName']
            and row.get('resourcename') == detail.get('resource')
            and custom.get('http',{}).get('url') == meta.get('http.url') == expected['resourceName']
            and row.get('status') == 'ok' and not row.get('error'), 'backend shared span payload differs', 'FAIL')
    try:duration=Decimal(str(custom.get('duration')))
    except InvalidOperation:raise ValueError('missing backend exact duration')
    require(duration.is_finite() and duration == expected['durationNanoseconds'], 'backend exact nanosecond duration differs', 'FAIL')
    start=row.get('starttimestamp')
    if isinstance(start,str):start=datetime.fromisoformat(start.replace('Z','+00:00'))
    require(isinstance(start,datetime) and start.tzinfo is not None, 'missing backend timestamp')
    delta=start.astimezone(timezone.utc)-datetime(1970,1,1,tzinfo=timezone.utc)
    milliseconds=(delta.days*86400+delta.seconds)*1000+delta.microseconds//1000
    # MCP observations round positive epoch starts to the nearest millisecond.
    # This validates that exposed projection, never submillisecond equality.
    require(start.microsecond % 1000 == 0, 'unexpected backend start precision')
    projected = (expected['startTimeNanoseconds'] + 500_000) // 1_000_000
    require(milliseconds == projected, 'backend start differs at exposed precision', 'FAIL')
    return dict(state='PASS',span_count=1,trace_id=expected['traceID'],span_id=expected['spanID'],
                view_id=expected['rumViewID'],duration_nanoseconds=expected['durationNanoseconds'],
                start_precision='observed nearest millisecond; submillisecond backend start unverified',
                backend_start_milliseconds=milliseconds, native_start_nanoseconds=expected['startTimeNanoseconds'],
                start_projection_inferred=True, duplicate_span_count=0)
