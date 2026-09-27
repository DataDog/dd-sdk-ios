"""Exact existing manual baseline pattern; never qualifies the failed semantics."""
import s2_local_contract as local

original = local.original
require = original.native.require
CONTRACT = 's2-existing-manual-foreground-v1'
STATE = 'EXISTING_MANUAL_TRANSITION_OBSERVED'
LIMITATIONS = ['pop.cancel', 'dismiss.finish']


def transition(rows, before, after, native, *, phase):
    require(phase in local.PHASES and native['cancelled'] is phase.endswith('cancel'), 'foreign manual native phase')
    value = original.transition_owners(rows, before, after, native)
    a = original.native.one(value['before'], 'one manual outgoing occurrence')
    b = original.native.one(value['after'], 'one manual returning occurrence')
    callback = value['callback']
    require(a['session'] == b['session'] == callback['session'], 'manual callback crossed sessions')
    names = {'pop.finish': ('detail', 'home'), 'pop.cancel': ('detail', 'detail'),
             'dismiss.finish': ('sheet', 'detail'), 'dismiss.cancel': ('sheet', 'sheet')}
    require((a['name'], b['name']) == names[phase], 'manual native destination owner differs')
    if phase not in LIMITATIONS:
        local.transition(rows, before, after, native)
    elif phase == 'pop.cancel':
        owners = { (r['payload']['view']['name'], r['payload']['session']['id']) for r in rows
                   if r['kind'] == 'rum' and r['payload']['type'] == 'view'
                   and r['payload']['view']['id'] == callback['view'] }
        require(value['relation'] == 'fresh' and value['expected_relation'] == 'preserved'
                and owners == {('home', a['session'])} and callback['view'] not in [a['id'], b['id']]
                and value['callback_owner_matches'] is False and value['semantic_expectation'] == 'FAIL',
                'cancelled manual pop differs from declared baseline limitation')
    else:
        require(value['relation'] == value['expected_relation'] == 'fresh' and callback['view'] == a['id']
                and value['callback_owner_matches'] is False and value['semantic_expectation'] == 'FAIL',
                'completed manual dismissal differs from declared baseline limitation')
    return dict(contract=CONTRACT, state=STATE, original_observation=value,
                inherited_limitation=phase in LIMITATIONS, release_acceptance=False)


def paired(a, b):
    for value in [a, b]:
        require(value['contract'] == CONTRACT and value['state'] == 'EXISTING_MANUAL_INVENTORY_OBSERVED'
                and value['tracking'] == 'manual', 'unbound existing-manual pair')
    require(all(a[k] == b[k] for k in ['views', 'actions', 'transitions', 'current']),
            'candidate differs from complete existing-manual baseline inventory')
    return dict(state='EXISTING_MANUAL_PAIR_MATCH_REQUIRES_SOURCE_REVIEW', inherited_limitations=LIMITATIONS,
                release_acceptance=False, gate_closures=[])
