"""F08 raw Browser preservation and long-lived native dashboard ownership.

Clock caching is a source-derived invariant, not direct cache observation. The
full raw inventory stays separate from the narrower, native-qualified J03 interval.
"""
import copy
import math

from journey_contract import one, field, identifier, require, backend_event, submitted_fields, mapper_inventory
from capture_contract import loads
from hosting_contract import sdk_milliseconds

FAMILIES = {'view', 'action', 'resource', 'error', 'long_task'}
INCIDENTAL_FAMILIES = {'vital'}


def key(event):
    family = field(event, 'type')
    require(family in FAMILIES | INCIDENTAL_FAMILIES, 'unqualified Browser family')
    view = identifier(field(event, 'view.id'))
    if family == 'view':
        version = field(event, '_dd.document_version')
        require(type(version) is int and version > 0, 'invalid Browser document version')
        return family, view, version
    return family, view, identifier(field(event, family + '.id'))


def anonymous_identity(rows, native):
    """Keep launch initialization outside the later, stable Browser interval."""
    first_browser=min(r['sequence'] for r in rows if r['kind']=='browser_message')
    values=sorted((v['sequence'],field(v['event'],'usr.anonymous_id')) for v in native['accepted'].values())
    present={value for _,value in values if value is not None}
    require(len(present)==1, 'native anonymous identity absent or changed for Browser join')
    value=next(iter(present));first_present=next(seq for seq,item in values if item is not None)
    require(first_present<first_browser and all(item==value for seq,item in values if seq>=first_present),
            'native anonymous identity not stable before Browser dispatch')
    return value, dict(state='STABLE_BEFORE_BROWSER',first_native_sequence=first_present,
                       first_browser_sequence=first_browser,missing_prefix_events=sum(seq<first_present for seq,_ in values))


def tags(value):
    require(isinstance(value, str), 'Browser tag source unavailable')
    result = {}
    for token in value.split(','):
        name, colon, content = token.partition(':')
        require(colon and name and content and name not in result, 'ambiguous Browser tags')
        result[name] = content
    return result


def context(rows, row, expected):
    before = [r for r in rows if r['sequence'] < row['sequence']]
    result = one([r for r in before if r['kind'] == 'context' and r['sequence'] == row['last_context_sequence']],
                 'Browser preceding native context')
    fields = result['fields']
    require(fields['application_id'] == expected['application_id'] and fields['session_id'] == expected['session_id'],
            'foreign Browser dispatch context')
    offset = fields.get('server_offset')
    require(type(offset) in (int, float) and math.isfinite(offset) and abs(offset) <= 300,
            'unqualified Browser dispatch clock')
    # This is the preceding asynchronous receipt, not a synchronous writer
    # context. A later context change does not invalidate a cached Browser clock.
    # The protected interval independently requires stable Replay and ownership.
    return fields


def local_inventory(rows, expected):
    events, incidental, latest, cached, identities = {}, {}, {}, {}, set()
    native = mapper_inventory(rows, expected)
    require(any(r['kind']=='browser_message' for r in rows), 'missing Browser messages')
    anonymous, anonymous_proof = anonymous_identity(rows,native)
    for row in rows:
        if row['kind'] != 'browser_message':continue
        raw = loads(row['fields']['event_json'])
        require(raw.get('source') == 'browser' and type(raw.get('date')) is int, 'wrong raw Browser identity/date')
        event_key = key(raw)
        partition=incidental if event_key[0] in INCIDENTAL_FAMILIES else events
        require(event_key not in partition, 'duplicate raw Browser event')
        dispatch = context(rows, row, expected)
        if event_key[1] not in cached:
            cached[event_key[1]] = dict(offset_ms=sdk_milliseconds(dispatch['server_offset']),
                                        context_sequence=row['last_context_sequence'], first_message_sequence=row['sequence'])
        offset = cached[event_key[1]]['offset_ms']
        require(-(2**63) <= raw['date'] + offset < 2**63, 'Browser corrected date overflow')
        source_tags = tags(raw.get('ddtags', ''))
        require(isinstance(raw.get('service'), str) and raw['service'] == source_tags.get('service')
                and isinstance(source_tags.get('sdk_version'), str), 'unfrozen Browser service/version source')
        identities.add((raw['service'], source_tags['sdk_version']))
        rewritten = copy.deepcopy(raw)
        rewritten['date'] = raw['date'] + offset
        require(isinstance(rewritten.get('application'), dict) and isinstance(rewritten.get('session'), dict),
                'raw Browser application/session unavailable')
        rewritten['application']['id'] = expected['application_id']
        rewritten['session']['id'] = expected['session_id']
        if dispatch.get('has_replay') is not True:
            if dispatch.get('has_replay') is None:rewritten['session'].pop('has_replay', None)
            else:rewritten['session']['has_replay'] = dispatch['has_replay']
            rewritten.get('_dd', {}).pop('replay_stats', None)
        if 'rule_psr' in rewritten.get('_dd', {}):
            require(expected.get('trace_sample_rate') == 100, 'unbound native trace sample rate')
            rewritten['_dd']['rule_psr'] = 1
        if anonymous is not None:
            rewritten.setdefault('usr', {})['anonymous_id'] = anonymous
        merged = dict(service=expected['service'], version=expected['app_version'],
                      sdk_version=expected['compiled_sdk_version'], env=expected['environment'])
        if expected.get('variant') is not None:merged['variant'] = expected['variant']
        merged.update(source_tags)
        rewritten.pop('ddtags')
        # Container is checked independently below; a source-supplied container
        # cannot silently replace the native injection under test.
        require('container' not in raw, 'raw Browser container requires explicit source review')
        partition[event_key] = dict(sequence=row['sequence'], monotonic_ns=row['monotonic_ns'], raw=raw,
                                 expected=rewritten, tags=merged, context=dispatch)
        if event_key[0] == 'view':
            prior = latest.get(event_key[1])
            require(prior is None or event_key[2] > prior[2], 'Browser view revisions not ordered')
            if prior:
                previous = events[prior]['raw']
                require(all(field(previous, path) == field(raw, path) for path in ['date', 'view.id', 'view.url', 'view.name']),
                        'Browser occurrence identity changed')
            latest[event_key[1]] = event_key
    require(events and latest and len(identities) == 1, 'missing or multiple Browser source partitions')
    require(set(k[1] for k in events.keys() | incidental.keys()) <= set(latest), 'Browser event missing raw view occurrence')
    return dict(events=events, incidental=incidental, latest=latest, clocks=cached,
                source_identity=next(iter(identities)), native=native,anonymous_identity=anonymous_proof)


def attached_dashboard(rows, snapshot, owner):
    require(owner['snapshot_sequence'] == snapshot['sequence'] and owner['has_replay'] is True,
            'dashboard lacks independent native Replay owner')
    return dashboard_attachment(rows, snapshot, owner)


def dashboard_attachment(rows, snapshot, owner):
    require(owner['snapshot_sequence'] == snapshot['sequence'], 'dashboard snapshot owner differs')
    topology = snapshot['fields']['topology']
    web = one([w for w in topology.get('webviews', []) if w.get('window') == owner['native_window']],
              'attached dashboard WebView')
    require(web.get('loading') is False and isinstance(web.get('host'), str) and web['host']
            and isinstance(web.get('bounds'), list) and len(web['bounds']) == 4 and all(v > 0 for v in web['bounds'][2:]),
            'dashboard WebView not ready')
    binding = one([r for r in rows if r['sequence'] < snapshot['sequence'] and r['kind'] == 'owned_webview'
                   and r['fields']['webview'] == web['id'] and r['fields']['controller'] == web['controller']],
                  'source-owned dashboard WebView binding')
    controller = one([c for c in topology['controllers'] if c['id'] == web['controller']], 'dashboard controller')
    require(controller['window'] == owner['native_window'] and controller['scene'] == topology['scene_inventory'][0]['id'],
            'dashboard controller detached')
    appearances = [r for r in rows if r['sequence'] < snapshot['sequence'] and r['kind'] == 'controller_callback'
                   and r['fields']['controller']['id'] == controller['id']]
    require(appearances and appearances[-1]['fields']['callback'] == 'viewDidAppear-exit', 'dashboard appearance not settled')
    return dict(webview=web['id'], controller=controller['id'], binding_sequence=binding['sequence'],
                host=web['host'], path=web['path'], window=owner['native_window'])


def retained_interval(rows, begin, before_input, end, owners, expected):
    require(len(owners) == 3 and begin['sequence'] < before_input['sequence'] < end['sequence'], 'J03 boundary order differs')
    require(before_input['monotonic_ns'] - begin['monotonic_ns'] >= 181_000_000_000, 'dashboard retained less than181seconds')
    require(len({o['view_id'] for o in owners}) == 1, 'dashboard native occurrence changed')
    binding = attached_dashboard(rows, begin, owners[0])
    require(all(attached_dashboard(rows, s, o) == binding for s,o in zip([before_input,end],owners[1:])),
            'dashboard WebView/controller changed')
    native = mapper_inventory([r for r in rows if r['sequence'] < end['sequence']], expected)
    owner_id = owners[0]['view_id']
    owner = native['views'][owner_id]['event']
    require(field(owner,'view.name') == 'DashboardDetails' and field(owner,'view.is_active') is True,
            'dashboard owner no longer active')
    for row in rows:
        if not begin['sequence'] < row['sequence'] < end['sequence']:continue
        if row['kind'] == 'mapper' and row['fields']['family'] == 'view':
            value = loads(row['fields']['event_json'])
            require(not (field(value,'view.id') == owner_id and field(value,'view.is_active') is not True),
                    'dashboard stopped during retained interval')
            require(field(value,'view.id') == owner_id or field(value,'view.is_active') is False,
                    'another native view became active during retained interval')
        if row['kind'] == 'context':
            require(row['fields'].get('view_id') == owner_id and row['fields'].get('has_replay') is True,
                    'dashboard context owner/Replay changed')
        if row['kind'] == 'scene_callback':
            require(row['fields']['activation'] == 0 and row['fields']['app_state'] == 0, 'dashboard lifecycle interrupted')
        if row['kind'] == 'controller_callback' and row['fields']['controller']['id'] == binding['controller']:
            require('Disappear' not in row['fields']['callback'], 'dashboard controller disappeared')
    return dict(owner=owner_id, owner_date=owner['date'], begin=begin['sequence'], before_input=before_input['sequence'],
                end=end['sequence'], wait_ns=before_input['monotonic_ns']-begin['monotonic_ns'], attachment=binding)


def extra_leaves(actual, expected, path=''):
    """Keep backend additions explicit; they are not in the bridge rewrite set."""
    extras = {}
    if isinstance(actual, dict) and isinstance(expected, dict):
        for name, value in actual.items():
            child = path + name
            if name not in expected:
                extras[child] = value
            else:
                extras.update(extra_leaves(value, expected[name], child + '.'))
    return extras


def backend_join(browser_rows, local, interval, expected, *, pending=True):
    state = 'PENDING' if pending else 'INVALID'
    actual, outside, witnesses, additions = {}, [], [], []
    service, version = local['source_identity']
    for row in browser_rows:
        event = backend_event(row)
        require(event.get('source') == 'browser' and event.get('service') == service
                and field(row['attributes'], 'tag.sdk_version') == version, 'foreign Browser source partition')
        event_key = key(event)
        partition=local.get('incidental',{}) if event_key[0] in INCIDENTAL_FAMILIES else local['events']
        require(event_key in partition and event_key not in actual, 'unmapped or duplicate persisted Browser event')
        captured = partition[event_key]
        required = copy.deepcopy(captured['expected'])
        app_version = required.pop('version', None)
        if app_version is not None:require(field(row['attributes'], 'tag.version') == app_version, 'Browser app version differs')
        submitted_fields(event, required)
        compared=copy.deepcopy(event);compared.pop('container',None)
        added=extra_leaves(compared,required)
        if added:additions.append(dict(key=list(event_key),fields=added))
        indexed = row['attributes'].get('tags', [])
        require(isinstance(indexed, list) and all(name+':'+value in indexed for name,value in captured['tags'].items()),
                'merged Browser tags differ')
        container = field(event, 'container.view.id')
        if interval['begin'] < captured['sequence'] < interval['end']:
            require(field(event,'container.source') == 'ios' and container == interval['owner'], 'wrong retained dashboard container')
            require(event['date'] > interval['owner_date'], 'Browser date does not follow native start')
            if captured['sequence'] > interval['before_input'] and event_key[0] in FAMILIES-{'view'}:witnesses.append(event_key)
        else:
            require(container is None or container in local['native']['views'], 'foreign native container outside retained interval')
            outside.append(dict(key=list(event_key), capture_sequence=captured['sequence'], container=container))
        actual[event_key] = row
    needed = {k for k in local['events'] if k[0] != 'view'} | set(local['latest'].values())
    require(needed <= set(actual), 'complete Browser inventory not indexed', state)
    require(witnesses, 'no post-wait Browser event in admitted interaction interval', state)
    return dict(state='J03_INTERVAL_JOINED_OUTSIDE_INTERVAL_REVIEW_REQUIRED', source_identity=list(local['source_identity']),
                persisted_rows=len(actual), cached_offsets=local['clocks'], post_wait_event_keys=[list(k) for k in witnesses],
                outside_interval=outside, backend_additions_requiring_classification=additions, runtime_acceptance=False,
                witness_scope='Temporal retained-owner evidence; not proof that the human gesture caused this event',
                clock_evidence='Source-derived first-message cache invariant using captured server_offset; no direct cache observation')
