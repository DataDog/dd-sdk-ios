"""Scoped S2 local semantics, separate from historical full-backend verdicts.

Callers must verify source, installed code, durable boundaries and cleanup. This
module has no native admission authority and cannot close a release gate.
"""
import json

import ownership_contract as original

require = original.native.require
PHASES = {'pop.finish', 'pop.cancel', 'dismiss.finish', 'dismiss.cancel'}
CONTRACT = 's2-local-transitions-v1'


def transition(rows, before, after, native):
    """Judge emitted action ownership without requiring synchronous mapper delivery."""
    observed = original.transition_owners(rows, before, after, native)
    require(observed['relation'] == observed['expected_relation'],
            'outgoing/return occurrence differs from actual cancellation')
    require(observed['callback_owner_matches'], 'emitted callback action has wrong owner')
    return dict(contract=CONTRACT, state='LOCAL_TRANSITION_QUALIFIED',
                original_observation=observed,
                mapper_before_callback='MATCH' if observed['callback_boundary_matches'] else 'ASYNCHRONOUS_DIAGNOSTIC',
                release_acceptance=False)


def inventory(local, transitions, *, run_id, tracking):
    """Keep every local occurrence and action, normalized only across run identities."""
    require(tracking in ['automatic', 'manual'], 'unknown local tracking mode')
    require(set(transitions) == PHASES, 'incomplete local transition inventory')
    observed = {phase: value['original_observation'] for phase, value in transitions.items()}
    require(all(value['contract'] == CONTRACT and value['state'] == 'LOCAL_TRANSITION_QUALIFIED'
                for value in transitions.values()), 'unqualified local transition')
    callbacks = {value['callback_id']: phase for phase, value in observed.items()}
    require(len(callbacks) == len(PHASES), 'aliased callback identity')
    order = local['occurrence_order']; rank = {identifier: n for n, identifier in enumerate(order)}
    require(set(rank) == set(local['views']) and len(rank) == len(order), 'incomplete occurrence inventory')
    views = []
    for identifier in order:
        event = local['views'][identifier]['event']; view = event['view']
        require(view['is_active'] is False and event['session']['id'] == local['session_id'],
                'active or foreign terminal occurrence')
        views.append(dict(name=view['name'], path=view['url'] if tracking == 'automatic' else None,
                          counts={key: view.get(key) for key in ['action', 'resource', 'error']}))
    actions = []; seen = []
    for key, value in local['accepted'].items():
        event = value['event']; family = event['type']
        if family == 'view':
            continue
        require(family == 'action' and event['view']['id'] in rank
                and event['session']['id'] == local['session_id'], 'foreign or unexpected local event')
        action = event['action']; context = event.get('context', {}); callback = context.get('transition_callback')
        if action['type'] == 'custom':
            require(callback in callbacks and action['target']['name'] == 'transition.callback'
                    and context.get('transition_run') == run_id, 'unbound custom callback action')
            phase = callbacks[callback]; expected = observed[phase]['callback']
            require(action['id'] == expected['action'] and event['view']['id'] == expected['view']
                    and event['session']['id'] == expected['session'], 'callback inventory substituted')
            seen.append(callback)
        else:
            require(callback is None and 'transition_run' not in context, 'automatic action carries callback identity')
        actions.append(dict(type=action['type'], target=action.get('target'),
                            owner=rank[event['view']['id']], callback_phase=callbacks.get(callback)))
    require(len(seen) == len(callbacks) and set(seen) == set(callbacks), 'missing or duplicate callback action')
    owners = {}
    for phase, value in observed.items():
        owners[phase] = dict(relation=value['relation'], callback_expected_side=value['callback_expected_side'],
            before=[rank[v['id']] for v in value['before']], after=[rank[v['id']] for v in value['after']],
            callback=rank[value['callback']['view']])
    return dict(contract=CONTRACT, state='LOCAL_INVENTORY_QUALIFIED', tracking=tracking,
                views=views, actions=sorted(actions, key=lambda row: json.dumps(row, sort_keys=True)),
                transitions=owners, release_acceptance=False)


def paired(baseline, candidate):
    """A local match still needs exact source/environment and gate classification."""
    for value in [baseline, candidate]:
        require(value['contract'] == CONTRACT and value['state'] == 'LOCAL_INVENTORY_QUALIFIED',
                'unqualified paired inventory')
    require(all(baseline[key] == candidate[key] for key in ['tracking', 'views', 'actions', 'transitions']),
            'paired S2 capture or ownership differs')
    return dict(state='PAIRED_LOCAL_MATCH_REQUIRES_SOURCE_CLASSIFICATION',
                release_acceptance=False, gate_closures=[])
