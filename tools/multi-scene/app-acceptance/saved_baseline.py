"""Use separately reviewed saved F08 evidence without rewriting a failed run."""
from pathlib import Path

from acceptance_common import require
from capture_build import sha
from capture_contract import loads

HERE = Path(__file__).resolve().parent


def checked(reference):
    require(set(reference) == {'path', 'sha256'}, 'saved baseline reference differs')
    path = Path(reference['path'])
    require(path.is_absolute() and path.is_file() and not path.is_symlink()
            and sha(path) == reference['sha256'], 'saved baseline artifact changed')
    return path


def read(reference):
    return loads(checked(reference).read_bytes())


def verify(reference, plan=None, *, choices=None, device=None):
    """The packet is an offline predecessor, never a successful native summary."""
    require(set(reference) == {'path', 'sha256', 'review', 'contract_transition'}, 'saved baseline review binding missing')
    packet_ref = {k: reference[k] for k in ('path', 'sha256')}
    packet = read(packet_ref);review = read(reference['review'])
    require(review['state'] == 'PASS' and review['reviewer'] == '/root/c06_runtime_plan'
            and review['packet_sha256'] == reference['sha256']
            and review['contract_transition_sha256'] == reference['contract_transition']['sha256']
            and review['permits_candidate_only'] is True and review['release_acceptance'] is False,
            'saved baseline candidate review missing')
    require(packet['state'] == 'SAVED_BASELINE_PREDECESSOR' and packet['gate'] == 'S2:F08'
            and packet['native_runs'] == 0 and packet['gate_closures'] == [], 'wrong saved baseline scope')
    summary = read(packet['original_summary']);original = read(packet['original_plan'])
    transition = read(reference['contract_transition']);controls = read(transition['controls'])
    transition_keys = ('runtime_transition', 'workspace_transition')
    require(transition['state'] == 'F08_CANDIDATE_HOST_TRANSITION'
            and transition['packet_sha256'] == reference['sha256']
            and transition['scope'] == 'host-helper-and-authorized-documentation-only'
            and set(transition['before']) == set(transition_keys) == set(transition['after'])
            and transition['before'] == {key: original[key] for key in transition_keys if key in original}
            and controls['state'] == 'PASS_OFFLINE_ONLY'
            and controls['source_sha256'] == transition['source_sha256']
            and all(sha(name) == digest for name, digest in transition['source_sha256'].items()),
            'saved baseline host transition differs from reviewed controls')
    if transition['after'].get('runtime_transition') is not None:checked(transition['after']['runtime_transition'])
    cell = checked(packet['original_summary']).parent
    require(summary['arm'] == 'baseline' and summary['mode'] == original['mode'] == 'signed-in-smoke'
            and summary['state'] == 'INVALID' and summary['cleanup'] == 'PASS'
            and summary['reason'] == 'missing, repeated or foreign lifecycle boundary'
            and summary['plan_sha256'] == packet['original_plan']['sha256'], 'unqualified original baseline')
    for name, digest in summary['artifacts'].items():
        path = cell/name
        require(path.resolve().is_relative_to(cell.resolve()), 'saved artifact escapes original cell')
        checked(dict(path=str(path), sha256=digest))
    publication = read(packet['original_publication']);worker = read(packet['original_supervisor'])
    require(publication['summary_sha256'] == packet['original_summary']['sha256']
            and publication['published_at'] < publication['deadline'] == summary['cleanup_details']['deadline']
            and summary['cleanup_details']['finished_at'] < publication['deadline'] <= summary['cleanup_deadline']
            and not (cell/'late-summary-publication.json').exists(), 'original cleanup or publication incomplete')
    require(worker['state'] == 'PASS' and worker['quiescent'] is True and not worker['before']
            and not worker['remaining'] and worker['finished_at'] < summary['cleanup_deadline'],
            'original input workers not quiescent')
    retention = loads((cell/'account-retention.json').read_bytes())
    binding = loads((cell/'account-binding.json').read_bytes())
    require(retention['state'] == 'PASS' and retention['account_retained'] is True and retention['uninstalls'] == 0
            and retention['finished_at'] < retention['deadline'] <= summary['cleanup_deadline']
            and binding['state'] == 'AUTHENTICATED_CAPTURE_BOUND', 'saved account not retained')
    require(sha(original['account_setup']['path']) == original['account_setup']['sha256'], 'original account setup changed')
    require(sha(Path(original['build_root'])/'completion.json') == original['completion_sha256'], 'saved product completion changed')
    if original.get('runtime_transition') is not None:checked(original['runtime_transition'])
    selected = read(packet['original_selection'])
    require(summary['selection_sha256'] == packet['original_selection']['sha256'], 'original route selection differs')
    native_review = read(packet['original_review']);admission = read(packet['original_admission'])
    require(native_review['state'] == 'PASS' and native_review['reviewer'] == '/root/c06_runtime_plan'
            and native_review['plan_sha256'] == packet['original_plan']['sha256']
            and admission['state'] == 'ADMITTED' and admission['operator_ready'] is True
            and admission['plan_sha256'] == packet['original_plan']['sha256']
            and admission['review_sha256'] == packet['original_review']['sha256']
            and admission['selection_sha256'] == packet['original_selection']['sha256']
            and admission['device'] == summary['device']['udid'] and summary['started_at'] < admission['expires_at'],
            'original native admission differs')
    local = read(packet['local_assessment']);backend = read(packet['backend_assessment'])
    joined = read(packet['backend_join'])
    require(local['state'] == 'SAVED_BEHAVIOR_QUALIFIED_OFFLINE_ONLY'
            and local['original_summary'] == packet['original_summary']
            and backend['state'] == 'SAVED_BASELINE_BEHAVIOR_AND_BACKEND_QUALIFIED_FOR_REVIEW'
            and backend['original_result_unchanged'] is True and backend['original_verdict'] == 'INVALID'
            and backend['original_cleanup'] == 'PASS' and backend['candidate'] == 'UNRUN'
            and backend['native_runs'] == 0 and backend['gate_closures'] == []
            and joined['state'] == 'SMOKE_SEMANTICS_JOINED_SOURCE_CLASSIFICATION_REQUIRED',
            'saved behavior or backend proof incomplete')
    for item in backend['bindings'] + local['phase_artifacts']:checked(item)
    require(packet['original_summary'] in backend['bindings'] and packet['local_assessment'] in backend['bindings'],
            'saved backend has a different local predecessor')
    require(all(sha(HERE/name) == digest for name, digest in packet['source_bindings'].items())
            and all(packet['source_bindings'].get(name) == digest for name, digest in local['source_bindings'].items()),
            'saved semantic source changed')
    broad = read(packet['broad_scope']);native = read(packet['native_scope'])
    require(broad['state'] == 'POSTMORTEM_INVENTORY_ONLY' and broad['original_summary'] == packet['original_summary']
            and broad['native_launches'] == 0 and broad['original_invalid_unchanged'] is True
            and native['state'] == 'POSTMORTEM_NATIVE_PARTITION_ONLY' and native['native_launches'] == 0
            and native['original_invalid_unchanged'] is True and native['paired_request'] == broad['request']['path']
            and broad['request'] in backend['bindings']
            and any(v['path'] == native['request'] for v in backend['bindings']), 'postmortem collection scope differs')
    if plan is not None:
        require(all(plan[key] == original[key] for key in
                    ('mode', 'definition', 'build_root', 'completion_sha256', 'arms', 'account_setup', 'account_salt')),
                'candidate changes saved baseline source, product or account contract')
        require({key: plan[key] for key in transition_keys if key in plan} == transition['after'],
                'candidate host or protection transition differs')
    if choices is not None:require(choices == selected, 'candidate route selection differs')
    if device is not None:require(device == summary['device']['udid'], 'candidate device differs')
    return dict(process_id=summary['process_id'], session_id=summary['session_id'], identity=summary['identity'],
                account_binding=binding, original_plan=original, selection=selected, predecessor=packet_ref)


def arm(plan, selected):
    require(not plan.get('baseline_reassessment') or selected == 'candidate',
            'saved baseline continuation permits candidate only')


def fresh(basis, identity, *, pid=None, session=None):
    require(all(identity[key] != basis['identity'][key] for key in ('run_id', 'nonce')),
            'candidate reused saved run identity')
    if pid is not None:require(pid != basis['process_id'], 'candidate reused saved process')
    if session is not None:require(session != basis['session_id'], 'candidate restored saved session')
