"""Collect asynchronous mapper work after an immutable native Home boundary.

The final inactive View includes actions drained by RUMStopViewCommand. Compare
that finite inventory instead of assuming a writer checkpoint is the file's EOF.
This module observes bytes only; it never flushes, launches or stops the SDK.
"""
from collections import Counter
import json
import math

from acceptance_common import require


def occurrence(event):
    # RUMViewScope adds locale and session activity/replay metadata that an
    # RUMUserActionScope event need not contain. Only shared ownership fields
    # identify the occurrence; those family-specific fields are not identity.
    return (event['application']['id'], event['service'], event['source'],
            event['session']['id'], event['session']['type'],
            event['view']['id'], event['view']['name'], event['view']['url'])


def terminal_rows(raw, *, run_id, prefix, callbacks=()):
    require(raw.startswith(prefix), 'native collection changed the committed Home prefix')
    if not raw.endswith(b'\n'):
        return None
    rows = [json.loads(line) for line in raw.splitlines()]
    committed = [json.loads(line) for line in prefix.splitlines()]
    require(rows and [r['sequence'] for r in rows] == list(range(1, len(rows) + 1))
            and all(r['run_id'] == run_id for r in rows), 'foreign or incomplete local collection')
    homes=[r for r in committed if r['kind']=='native_background']
    before=[r for r in committed if r['kind']=='human_snapshot' and r['payload'].get('phase')=='background.before']
    require(len(homes) == 1,
            'missing or duplicate committed Home boundary')
    require(len(before)==1 and before[0]['sequence']<homes[0]['sequence'],'missing native pre-Home boundary')
    require(all(r['kind'] in ['rum', 'human_observer_cost'] for r in rows[len(committed):]),
            'native activity after committed Home boundary')
    views, actions, seen, actual_callbacks = {}, Counter(), set(), Counter()
    home_views, delayed_active, last_sequences, action_events, identities = {}, set(), {}, [], set()
    for row in rows:
        if row['kind'] != 'rum':
            continue
        event = row['payload']; family = event['type']
        require(family in ['view', 'action'], 'unplanned mapper family in local collection')
        require(type(event['date']) in [int,float] and math.isfinite(event['date']) and event['date']>0,
                'invalid mapper event date')
        require(event['source']=='ios' and event['session']['type']=='user','foreign mapper source/session')
        identities.add((event['application']['id'],event['service'],event['session']['id']))
        require(len(identities)==1,'foreign application/service/session in local collection')
        owner = event['view']['id']
        if family == 'view':
            view = event['view']; previous = views.get(owner)
            revision = event['_dd']['document_version']
            require(type(revision) is int and revision == (previous['_dd']['document_version'] + 1 if previous else 1),
                    'duplicate or missing View revision in local collection')
            require(type(view['is_active']) is bool and type(view['action']['count']) is int
                    and view['action']['count'] >= 0, 'invalid terminal View state/counter')
            if previous:
                require(occurrence(previous) == occurrence(event) and previous['date'] == event['date'],
                        'local View occurrence identity changed')
            views[owner] = event
            last_sequences[owner]=row['sequence']
            if row['sequence']<homes[0]['sequence']:home_views[owner]=event
            elif view['is_active']:delayed_active.add(owner)
        else:
            action = event['action']; require(action['id'] not in seen, 'duplicate local Action')
            seen.add(action['id']); actions[owner] += 1
            action_events.append(event)
            callback = event.get('context', {}).get('transition_callback')
            if callback is not None:
                actual_callbacks[callback] += 1
                require(actual_callbacks[callback] == 1 and callback in callbacks,
                        'duplicate or foreign transition callback work')
    if not views or any(e['view']['is_active'] for e in views.values()):
        return None
    if set(actions) - set(views) or any(actions[k] != e['view']['action']['count'] for k, e in views.items()):
        return None
    for event in action_events:
        owning=views[event['view']['id']]
        require(occurrence(event) == occurrence(owning),
                'local Action occurrence identity differs')
    # A stop after actual Home accounts for pending actions in this finite
    # View/Action fixture. Balanced older inactive Views alone are insufficient.
    required={k for k,e in home_views.items() if e['view']['is_active']}|delayed_active
    if not required or any(last_sequences[k]<=homes[0]['sequence'] for k in required):
        return None
    if set(actual_callbacks) != set(callbacks):
        return None
    return rows
