"""Separate offline RUM gate assessment; never replaces generic/full acceptance.

Replay content metadata remains unassessed. Every required RUM value must match a
captured mapper revision; only its latest revision can qualify the payload gate.
"""
import copy

import physical_ownership
import physical_projection as projection
from acceptance_common import require

CONTRACT = 's2-physical-transition-rum-fields-v1'


def replay_metadata(actual, submitted):
    """Retain presence and actual values; missing does not mean false."""
    result = dict(path='session.has_replay', disposition='NOT_ASSESSED_REPLAY_METADATA')
    for label, event in [('actual', actual), ('submitted', submitted)]:
        session = event.get('session', {})
        present = 'has_replay' in session
        require(not present or type(session['has_replay']) is bool, 'unsupported Replay metadata type')
        result[label + '_present'] = present
        if present: result[label] = session['has_replay']
    return result


def required_differences(changes):
    return [c for c in changes if c['disposition'].startswith('UNRESOLVED') and c['path'] != 'session.has_replay']


def assess(rows, native_rows, evidence, identity, expected, *, pending=True):
    """Classify saved complete inventories, with no query, mutation or renewed clock.

    The caller must provide its independently frozen writer/stream boundary. This
    function has no runtime authority; pending=False is mandatory at that boundary.
    """
    require(type(pending) is bool, 'invalid pending mode')
    require(type(evidence) is list and evidence, 'native TTID witness stream is required')
    local = physical_ownership.inventory(evidence, identity)
    require(local['session_id'] == expected['session_id'], 'RUM gate session differs')
    full = projection.assess(rows, native_rows, local, expected, native_evidence=(evidence, identity))
    backend_views = {}; reducers = []
    for row in rows:
        event = projection.contract.backend_event(row)
        if event['type'] == 'view': backend_views[event['view']['id']] = (row, event)
        elif event['type'] == 'session': reducers.append(event)
    reducer = reducers[0] if reducers else None
    failures = []; waiting = []; matches = []; replay = []
    for vid, terminal in local['views'].items():
        if vid not in backend_views:
            waiting.append(dict(kind='MISSING_VIEW', view_id=vid))
            continue
        row, actual = backend_views[vid]
        replay.append(dict(raw_id=row['id'], view_id=vid, **replay_metadata(actual, terminal['event'])))
        matched = []
        for key, candidate in local['accepted'].items():
            if key[0] != 'view' or key[1] != vid: continue
            submitted = copy.deepcopy(candidate['event'])
            projection.tags(row, submitted, expected)
            replay_metadata(actual, submitted)
            differences = projection.differences(actual, submitted, view=True, reducer=reducer)
            if not required_differences(differences):
                matched.append(dict(mapper_sequence=candidate['sequence'], mapper_revision=key[2]))
        terminal_key = projection.contract.event_key(terminal['event'])
        is_terminal = any(m['mapper_revision'] == terminal_key[2] for m in matched)
        matches.append(dict(raw_id=row['id'], view_id=vid, backend_revision=actual['_dd']['document_version'],
                            matched_mapper_revisions=matched, latest_mapper_revision=terminal_key[2], terminal=is_terminal))
        if not matched:
            failures.append(dict(kind='VIEW_HAS_NO_EXACT_CAPTURED_REVISION', raw_id=row['id'], view_id=vid,
                required_differences=[c for c in full['unresolved'] if c['event'][0] == 'view' and
                                      c['event'][1] == vid and c['path'] != 'session.has_replay']))
        elif not is_terminal:
            waiting.append(dict(kind='EXACT_EARLIER_MAPPER_REVISION', raw_id=row['id'], view_id=vid,
                                matched_mapper_revisions=matched, required_latest=terminal_key[2]))
    for change in full['unresolved']:
        if change['event'][0] != 'view': failures.append(dict(kind='REQUIRED_EVENT_VALUE_DIFFERS', **change))
    for failure in full['terminal_failures']:
        kind = failure['kind']
        if kind in {'MISSING_TERMINAL_VIEW', 'TERMINAL_VIEW_NOT_SETTLED'}: continue
        if kind == 'SESSION_COUNT_DIFFERS':
            observed, wanted = failure['actual'], failure['submitted']
            if type(observed) is not int or observed < 0 or observed > wanted:
                failures.append(failure)
            else:
                waiting.append(dict(failure, kind='SESSION_REDUCER_NOT_SETTLED'))
        elif kind in {'MISSING_ACCEPTED_EVENT', 'MISSING_SESSION_REDUCER', 'MISSING_WITNESSED_TTID'}:
            waiting.append(failure)
        else:
            failures.append(failure)
    if full['incidental_source_classification_required']:
        failures.append(dict(kind='UNCLASSIFIED_INCIDENTAL_EVENTS', raw_ids=full['incidental_source_classification_required']))
    if waiting and not pending:
        failures.append(dict(kind='INGESTION_INCOMPLETE_AT_FINAL_BOUNDARY', details=copy.deepcopy(waiting)))
    state = 'INVALID' if failures else 'PENDING' if waiting else 'RUM_FIELDS_QUALIFIED'
    return dict(contract=CONTRACT, state=state, gate_payload_qualified=state == 'RUM_FIELDS_QUALIFIED',
                full_projection=full, required_failures=failures, pending=waiting, view_matches=matches,
                replay_metadata=replay, replay_content_correctness='NOT_ASSESSED',
                sdk_regression_established=False, runtime_acceptance=False, release_acceptance=False, gate_closures=[])
