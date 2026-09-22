"""Ordinary UIKit-hosted SwiftUI evidence. Never grants gesture/fold/physical credit."""
import json
from acceptance_common import require
from app_journey_inventory import field, identifier, source

PHASES = ['root', 'push', 'pop', 'present', 'dismiss']
NAMES = ['RootView', 'DetailView', 'RootView', 'ModalView', 'RootView']
APP_ID = '43cbc59b-0626-438b-a3d9-c6417a4545a3'
SERVICE = 'ios-s2-hosting-validation'


def local(document, expected):
    require(document.get('identity') == expected, 'stale hosting identity')
    for key in ['run_id', 'nonce']: identifier(expected[key])
    require(expected['run_id'] != expected['nonce'], 'aliased identity')
    require(expected['mode'] in ['automatic', 'manual'], 'unqualified tracking mode')
    rows = document.get('records', [])
    require(document.get('persistence_failure') is False and document.get('durable_sequence') == len(rows), 'incomplete durable evidence')
    require(rows and all(r['sequence'] == i for i, r in enumerate(rows, 1)), 'missing/reordered receipt')
    require(all(a['monotonic_ns'] <= b['monotonic_ns'] and a['wall_ms'] <= b['wall_ms'] for a, b in zip(rows, rows[1:])), 'reversed clocks')
    def unique(kind, **wanted):
        matches = [r for r in rows if r['kind'] == kind and all(r.get(k) == v for k, v in wanted.items())]
        require(len(matches) == 1, 'missing/duplicate ' + kind + str(wanted))
        return matches[0]
    terminal = unique('terminal')
    require(terminal['state'] == 'PASS' and terminal is rows[-1], 'native scenario incomplete')
    require(not any(r['kind'] in ['encoding-failure', 'scene-disconnected', 'scene-inactive'] for r in rows), 'native continuity lost')
    launch = unique('launch')
    require(launch['mode'] == expected['mode'] and launch['automatic_uikit'] is False and launch['automatic_swiftui'] == (expected['mode'] == 'automatic'), 'wrong tracking configuration')
    scene = unique('scene-connected'); unique('scene-active')
    mappers = [(r, json.loads(r['event_json'])) for r in rows if r['kind'] == 'mapper']
    require(mappers, 'missing mapper events')
    view_rows = [(r,e) for r,e in mappers if e['type'] == 'view']
    views = {}; sessions = set()
    for receipt, event in mappers:
        require(event['application']['id'] == APP_ID and event['service'] == SERVICE, 'foreign local app/service')
        sessions.add(identifier(event['session']['id']))
        if event['type'] == 'view':
            view = event['view']; vid = identifier(view['id']); previous = views.get(vid)
            require(type(view.get('is_active')) is bool, 'missing view activity')
            require(previous is None or event['_dd']['document_version'] > previous['_dd']['document_version'], 'non-growing view revision')
            require(previous is None or (view['name'],view['url'],event['date']) == (previous['view']['name'],previous['view']['url'],previous['date']), 'changed occurrence identity')
            views[vid] = event
        else:
            require(event['type'] == 'action' and event['action']['type'] == 'application_start', 'unexpected local telemetry')
    require(len(sessions) == 1 and len(views) == 6, 'missing/extra view occurrence or session')
    require(all(not e['view']['is_active'] for e in views.values()), 'unfinished view lifetime')
    launch_views = [e for e in views.values() if e['view']['name'] == 'ApplicationLaunch']
    require(len(launch_views)==1 and launch_views[0]['view']['url']=='com/datadog/application-launch/view', 'wrong incidental launch view')
    launch_id=launch_views[0]['view']['id']
    appearances=[r for r in rows if r['kind']=='swiftui-appear']
    disappearances=[r for r in rows if r['kind']=='swiftui-disappear']
    require([r['name'] for r in appearances]==NAMES and [r['name'] for r in disappearances]==NAMES,
            'missing, extra or reordered SwiftUI lifecycle occurrence')
    for index,(appear,disappear) in enumerate(zip(appearances,disappearances)):
        require(appear['sequence']<disappear['sequence']<terminal['sequence'],'invalid SwiftUI lifetime')
        following=[r for r in appearances[index+1:] if r['name']==appear['name']]
        require(not following or disappear['sequence']<following[0]['sequence'],'overlapping same-content lifetime')
    bounds = [r for r in rows if r['kind'] == 'boundary']
    require([r['phase'] for r in bounds] == PHASES, 'missing/reordered native transitions')
    controllers = []; ids = []; names = []; previous_boundary = launch['sequence']
    for index, (boundary, phase, name) in enumerate(zip(bounds, PHASES, NAMES), 1):
        callback = unique('did-show' if index <= 3 else 'completion', phase=phase)
        require(previous_boundary < callback['sequence'] < boundary['sequence'], 'late or stale actual completion')
        if index > 1:
            start = unique('transition-start', phase=phase)
            require(previous_boundary < start['sequence'] < callback['sequence'], 'completion outside transition')
            require(start['controller'] == callback['controller'], 'transition target changed')
        require(boundary['controller'] == callback['controller'] and boundary['controller_attached'] is True and boundary['transition_finished'] is True, 'wrong/incomplete visible controller')
        require(boundary['occurrence'] == index, 'wrong occurrence ordinal')
        require(boundary['scene'] == scene['scene'] and boundary['window'] == scene['window'], 'scene/window replaced')
        inventory = boundary['inventory']
        require(len(inventory) == 1 and inventory[0]['id'] == scene['scene'] and inventory[0]['activation'] == 0, 'actual scene topology changed')
        windows = inventory[0]['windows']; owned = [w for w in windows if w['owned']]
        require(len(owned) == 1 and owned[0]['id'] == scene['window'], 'owned window missing/duplicated')
        window = owned[0]
        require(window['key'] is True and window['hidden'] is False and window['alpha'] > 0 and window['root'] == scene['navigation'] and window['root_is_navigation'] is True, 'owned key/root lost')
        require(all(w['id'] == window['id'] or (w['key'] is False and not w['contains_fixture_controller']) for w in windows), 'foreign window owns key/content')
        require(all(w['screen'] == boundary['screen']['id'] for w in windows), 'foreign display window')
        require(window['width'] > 0 and window['height'] > 0 and boundary['screen']['width'] > 0 and boundary['screen']['height'] > 0 and boundary['screen']['scale'] > 0, 'missing actual geometry')
        if phase == 'present':
            require(boundary['presented'] == boundary['controller'] and boundary['top'] == scene['root_controller'], 'wrong presented owner')
        else:
            require(boundary['presented'] is None and boundary['top'] == boundary['controller'], 'wrong navigation owner')
        appears = [r for r in rows if r['kind'] == 'swiftui-appear' and r['name'] == name and previous_boundary < r['sequence'] < boundary['sequence']]
        require(len(appears) == 1, 'missing/duplicate native content appearance')
        current = [(r,e) for r,e in view_rows if r['sequence'] < boundary['sequence']][-1]
        event = current[1]; view = event['view']
        require(current[0]['sequence'] > previous_boundary and view == boundary['latest_view'] and view['is_active'] is True, 'stale/current owner not independently mapped')
        require(boundary['session'] == event['session']['id'], 'boundary session differs')
        allowed = [name] if expected['mode'] == 'manual' else [name, 'AutoTracked_HostingController_Fallback']
        require(view['name'] in allowed, 'unexpected automatic/manual view identity')
        ids.append(view['id']); names.append(view['name']); controllers.append(boundary['controller'])
        previous_boundary = boundary['sequence']
    require(len(set(ids)) == 5 and set(ids) | {launch_id} == set(views), 'duplicate/foreign occurrence')
    require(controllers[0] == controllers[2] == controllers[4] == scene['root_controller'] and len(set(controllers)) == 3, 'hosting instance replaced/aliased')
    stop = unique('stop-session'); teardown=unique('native-teardown')
    require(bounds[-1]['sequence'] < teardown['sequence'] < stop['sequence'] < terminal['sequence'], 'wrong terminal boundary')
    require(any(r['kind']=='swiftui-disappear' and r['name']=='RootView' and teardown['sequence'] < r['sequence'] < stop['sequence'] for r in rows), 'missing terminal native disappearance')
    return {'state':'LOCAL_QUALIFIED','identity':expected,'session_id':next(iter(sessions)), 'view_ids':ids,'launch_view_id':launch_id,'names':names,'views':views,'mappers':[e for _,e in mappers], 'pid':launch['pid'], 'scene':scene['scene'], 'window':scene['window']}


def backend(rows, result, *, pending=False):
    """Full app/session inventory; missing ingestion may wait, wrong owners fail."""
    state = 'PENDING' if pending else 'INVALID'
    views = {}; starts=[]; vitals=[]; reducers=[]
    for row in rows:
        e = row['attributes']['custom']
        require(source(row) == 'ios' and field(e,'application.id') == APP_ID and field(e,'session.id') == result['session_id'] and field(e,'service') == SERVICE, 'foreign backend identity')
        kind = field(e,'type')
        if kind == 'session':
            require(field(e,'_dd.origin') == 'reducer', 'unknown session evidence'); reducers.append(row); continue
        require(field(e,'view.id') in result['views'], 'foreign backend view')
        if kind == 'view':
            vid = field(e,'view.id'); ver = field(e,'_dd.document_version')
            require(type(ver) is int and ver > 0, 'missing backend revision')
            key=(vid,ver); require(key not in views, 'duplicate backend view revision'); views[key]=e
        elif kind == 'action':
            require(field(e,'action.type') == 'application_start', 'unexpected backend action'); starts.append(e)
        elif kind == 'vital':
            require(field(e,'vital.type') == 'app_launch' and field(e,'vital.name') == 'time_to_initial_display' and field(e,'vital.app_launch_metric') == 'ttid' and field(e,'view.id') == result['launch_view_id'] and type(field(e,'vital.duration')) is int and field(e,'vital.duration') > 0, 'unexpected vital'); vitals.append(e)
        else: require(False, 'unexpected backend family')
    actual_ids = {v for v,_ in views}; require(actual_ids == set(result['views']), 'backend view inventory incomplete', state)
    for vid, expected in result['views'].items():
        event = max((e for (key,_),e in views.items() if key==vid),key=lambda e:field(e,'_dd.document_version'))
        require(field(event,'view.name') == expected['view']['name'] and field(event,'view.url') == expected['view']['url'], 'backend occurrence identity differs')
        require(field(event,'_dd.document_version') == expected['_dd']['document_version'] and field(event,'view.is_active') is False, 'final backend revision not settled', state)
        for counter in ['action','resource','error','long_task']:
            require(field(event,'view.'+counter+'.count') == expected['view'][counter]['count'], 'backend view counter differs')
    expected_starts=[e for e in result['mappers'] if e['type']=='action']
    require({field(e,'action.id') for e in starts} == {e['action']['id'] for e in expected_starts}, 'application-start inventory incomplete', state)
    require(len(starts)==len(expected_starts) and len(vitals)<=1, 'duplicate app-launch telemetry')
    require(len(vitals)==1,'TTID inventory incomplete',state)
    require(len(reducers)<=1,'duplicate session reducer')
    require(len(reducers)==1,'session reducer missing',state)
    reducer=reducers[0]['attributes']['custom']
    for counter,wanted in [('view',len(result['views'])),('action',len(expected_starts)),('crash',0)]:
        actual=field(reducer,'session.'+counter+'.count')
        require(type(actual) is int and 0<=actual<=wanted,'unexpected session '+counter+' count')
        require(actual==wanted,'session '+counter+' count not settled',state)
    for e in starts:
        match=next(v for v in expected_starts if v['action']['id']==field(e,'action.id'))
        require(field(e,'view.id')==match['view']['id'], 'application start owner differs')
    return {'state':'BACKEND_QUALIFIED','raw_rows':len(rows),'view_occurrences':len(actual_ids),'application_start_actions':len(starts),'incidental_app_launch_vitals':len(vitals),'session_reducers':len(reducers)}
