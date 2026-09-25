"""Namespaced physical capture qualification; never a generic or release PASS."""
from pathlib import Path
import time
import physical_rum_contract as contract
import physical_backend as backend
from capture_io import atomic, encoded
from acceptance_common import require

shared = backend.shared
JOINED = 'RUM_FIELDS_JOINED_SOURCE_CLASSIFICATION_REQUIRED'
QUALIFIED = 'RUM_FIELDS_CAPTURE_QUALIFIED'


def mode(plan, source=None):
    selected = plan.get('evidence_contract')
    require(selected is None or selected == contract.CONTRACT, 'unknown physical evidence contract')
    if selected is not None and source is not None:
        require(all(source.get(k) is True for k in ['observer_cost_partition', 'background_finalization',
                    'public_accessibility_inventory', 'ttid_witness']), 'RUM-fields fixture prerequisites absent')
    return selected


def evidence(folder, plan, summary):
    """Recompute from actual saved exchanges and the immutable sealed native stream."""
    require(mode(plan) == contract.CONTRACT and summary.get('evidence_contract') == contract.CONTRACT,
            'physical RUM-fields summary mode differs')
    require(summary['plan_sha256'] == shared.sha(folder.parent.parent/'plan.json'), 'physical plan hash differs')
    if plan.get('input_mode') is not None:
        import physical_automatic as automatic
        automatic.mode(plan)
        automatic.inputs.worker_quiescence(folder.parent.parent,folder.name,complete=True)
        automatic.validate_end(folder.parent.parent,folder.name)
    joined = shared.read(folder/'backend-joined.json'); seal = shared.read(folder/'terminal-rejoin.json')
    require(joined.get('state') == JOINED and joined.get('evidence_contract') == contract.CONTRACT
            and seal.get('evidence_contract') == contract.CONTRACT, 'physical RUM-fields evidence mode differs')
    require(seal['state'] == 'SEALED_STREAM_EQUALS_FROZEN_BACKEND_INVENTORY'
            and seal['stream_sha256'] == shared.sha(folder/'sealed-events.jsonl')
            and seal['backend_join_sha256'] == shared.sha(folder/'backend-joined.json') == summary['backend_join_sha256']
            and seal['queries_after_termination'] == 0 and seal['release_acceptance'] is False
            and joined['completed_at'] < seal['finished_at'] < seal['deadline'] == joined['deadline'] <= summary['execution_deadline'],
            'physical RUM-fields seal absent, changed or late')
    raw = (folder/'sealed-events.jsonl').read_bytes()
    require(raw == (folder/'terminal-before-collection.jsonl').read_bytes(), 'sealed physical stream differs')
    native = shared.read(folder/'native-summary.json')
    require(native['identity'] == summary['identity'], 'physical RUM-fields identity differs')
    requests = [Path(p) for p in joined['inventory_requests']]
    require(len(requests) == 2 and len(set(requests)) == 2 and all(p.parent == folder for p in requests),
            'physical saved inventories differ')
    require(joined['inventory_bindings'] == backend.inventory_bindings(requests), 'physical inventory hashes changed')
    bounds = [backend.common.transport.binding(p)[0] for p in requests]
    expected = native['expected']; base = '@application.id:'+expected['application_id']+' @session.id:'+expected['session_id']
    require([b['request']['query'] for b in bounds] == [base,base+' service:'+expected['service']+' source:ios']
            and all(b['request']['run_id'] == native['identity']['run_id'] and b['deadline'] == joined['deadline']
                    and b['request']['from'] == joined['query_interval']['start'] and b['request']['to'] == joined['query_interval']['end']
                    for b in bounds), 'physical saved query scope differs')
    saved = [contract.projection.saved_inventory(p) for p in requests]
    rows = backend.common.capture.rows(raw, native['identity']['run_id'])
    assessment = contract.assess(*saved, rows, native['identity'], native['expected'], pending=False)
    require(assessment['state'] == 'RUM_FIELDS_QUALIFIED' and assessment['gate_payload_qualified'] is True
            and assessment == joined['rum_fields'], 'sealed RUM-fields assessment differs or is incomplete')
    require(assessment['runtime_acceptance'] is False and assessment['release_acceptance'] is False
            and assessment['gate_closures'] == [], 'payload assessment claims broader acceptance')
    return joined


def publish(folder, summary, joined, plan):
    """A named capture result still leaves overall source/release acceptance invalid."""
    ready = False
    try:
        require(joined is not None and evidence(folder, plan, summary) == joined, 'physical joined evidence differs')
        require(summary['scenario'] == summary['cleanup'] == 'PASS'
                and summary['evidence'] == 'SOURCE_CLASSIFICATION_REQUIRED' and not summary.get('reason')
                and not summary.get('evidence_errors')
                and time.time() < summary['cleanup_details']['deadline'] <= summary['cleanup_deadline'],
                'physical scenario, evidence, cleanup or deadline incomplete')
        ready = True
    except Exception as error:
        summary['qualification_error'] = str(error)
    summary.update(state='INVALID',release_acceptance=False,gate_closures=[],finished_at=time.time(),
        mechanism=dict(state=QUALIFIED if ready else 'UNQUALIFIED', evidence_contract=contract.CONTRACT,
            scope='Physical capture and required RUM payloads; full projection/source review remains separate',
            permits_planned_candidate=ready,release_acceptance=False))
    summary['artifacts'] = {str(p.relative_to(folder)):shared.sha(p) for p in folder.rglob('*')
                           if p.is_file() and p != folder/'summary.json'}
    atomic(folder/'summary.json',encoded(summary),exclusive=False)
    receipt = dict(summary_sha256=shared.sha(folder/'summary.json'),published_at=time.time(),
        deadline=summary['cleanup_details']['deadline'],evidence_contract=contract.CONTRACT,release_acceptance=False)
    atomic(folder/'summary-publication.json',encoded(receipt))
    timely = time.time() < receipt['deadline']
    if not timely:atomic(folder/'late-summary-publication.json',encoded(dict(state='INVALID',observed_at=time.time(),**receipt)))
    return ready and timely


def summary_record(root, key, plan):
    folder = root/'cells'/key; summary = shared.read(folder/'summary.json')
    receipt = shared.read(folder/'summary-publication.json')
    require(summary['mechanism']['state'] == QUALIFIED and summary['mechanism']['evidence_contract'] == contract.CONTRACT
            and summary['mechanism']['permits_planned_candidate'] is True and summary['mechanism']['release_acceptance'] is False
            and summary['state'] == 'INVALID' and summary['release_acceptance'] is False and summary['gate_closures'] == []
            and summary['scenario'] == summary['cleanup'] == 'PASS' and summary['evidence'] == 'SOURCE_CLASSIFICATION_REQUIRED'
            and not summary.get('reason') and not summary.get('evidence_errors') and not summary.get('qualification_error'),
            'physical RUM-fields mechanism not qualified')
    require(receipt.get('evidence_contract') == contract.CONTRACT and receipt['release_acceptance'] is False
            and receipt['summary_sha256'] == shared.sha(folder/'summary.json')
            and summary['finished_at'] <= receipt['published_at'] < receipt['deadline'] == summary['cleanup_details']['deadline'] <= summary['cleanup_deadline']
            and (folder/'summary-publication.json').stat().st_mtime < receipt['deadline']
            and not (folder/'late-summary-publication.json').exists(), 'physical RUM-fields publication changed or late')
    artifacts = summary['artifacts']
    require({'backend-joined.json','terminal-rejoin.json','sealed-events.jsonl','native-summary.json'} <= set(artifacts)
            and {str(p.relative_to(folder)) for p in folder.rglob('*') if p.is_file()} == set(artifacts)|{'summary.json','summary-publication.json'}
            and all(shared.sha(folder/name) == digest for name,digest in artifacts.items()), 'physical evidence inventory changed')
    evidence(folder, plan, summary)
    return summary


def qualify(root, key, plan, *, error=None):
    """Bind the real supervisor to this named result without generic qualification."""
    folder = root/'cells'/key; worker_path = root/(key+'-driver.supervisor.json'); ready = False
    try:
        require(not error, 'physical supervisor error: '+str(error))
        summary = summary_record(root,key,plan); worker = shared.read(worker_path)
        require(worker['state'] == 'PASS' and not worker['before'] and not worker['remaining']
                and worker['finished_at'] < time.time() < summary['cleanup_deadline'], 'physical supervisor not quiescent or late')
        ready = True
    except Exception as failure:error = str(failure)
    record = dict(state=QUALIFIED if ready else 'UNQUALIFIED',arm=key,finished_at=time.time(),
        evidence_contract=contract.CONTRACT,plan_sha256=shared.sha(root/'plan.json'),
        summary_sha256=shared.sha(folder/'summary.json') if (folder/'summary.json').exists() else None,
        publication_sha256=shared.sha(folder/'summary-publication.json') if (folder/'summary-publication.json').exists() else None,
        supervisor=dict(path=str(worker_path),sha256=shared.sha(worker_path)) if worker_path.exists() else None,
        error=error,release_acceptance=False,gates_closed=[])
    atomic(root/(key+'-qualification.json'),encoded(record))
    if ready and time.time() >= summary['cleanup_deadline']:
        atomic(root/(key+'-late-qualification.json'),encoded(dict(state='INVALID',observed_at=time.time(),deadline=summary['cleanup_deadline'])))
        return False
    return ready


def qualification(root, key, plan):
    summary = summary_record(root,key,plan); folder = root/'cells'/key
    result = shared.read(root/(key+'-qualification.json')); worker_path = root/(key+'-driver.supervisor.json')
    worker = shared.read(worker_path)
    require(result['state'] == QUALIFIED and result.get('evidence_contract') == contract.CONTRACT
            and result['plan_sha256'] == shared.sha(root/'plan.json')
            and result['summary_sha256'] == shared.sha(folder/'summary.json')
            and result['publication_sha256'] == shared.sha(folder/'summary-publication.json')
            and result['supervisor'] == dict(path=str(worker_path),sha256=shared.sha(worker_path))
            and result['release_acceptance'] is False and result['gates_closed'] == [] and not result['error']
            and worker['state'] == 'PASS' and not worker['before'] and not worker['remaining']
            and worker['finished_at'] < result['finished_at'] < summary['cleanup_deadline']
            and (root/(key+'-qualification.json')).stat().st_mtime < summary['cleanup_deadline']
            and not (root/(key+'-late-qualification.json')).exists(), 'physical RUM-fields supervisor qualification differs')
    return summary
