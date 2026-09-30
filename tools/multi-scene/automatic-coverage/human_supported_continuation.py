"""Reuse reviewed completed cells and select one untouched SwiftUI successor."""
from pathlib import Path

import human_effect_recapture
import human_supported_session as supported

require = supported.require
UNIVERSE = [dict(build=build, device='duo', framework='SwiftUI', layout=layout, multiple_scenes=False)
            for layout in ('stack', 'split')
            for build in ('baseline-26.5', 'baseline-27.1', 'candidate-27.1')]


def bound(reference, *, decode=True):
    path = Path(reference['path'])
    require(path.is_file() and not path.is_symlink() and supported.reference(path) == reference,
            'completed evidence changed: ' + str(path))
    return supported.read(path) if decode else path


def successful(value):
    require(all(value[key] == 'PASS' for key in ('state', 'scenario', 'evidence', 'cleanup')),
            'completed cell is not fully qualified')


def accepted(item, expected, prior):
    require(item['selected'] == expected, 'completed prefix is skipped, repeated or reordered')
    result = bound(item['result'])
    require(result['selected'] == expected and result['state'] in ('NATIVE_BASELINE_QUALIFIED', 'NATIVE_CELL_QUALIFIED')
            and all(result[key] == 'PASS' for key in ('scenario', 'evidence', 'cleanup'))
            and result['native_runs'] == result['qualified_cells'] == 1, 'unqualified completed result')
    plan = bound(result['plan'])
    require(plan['selected'] == expected and plan.get('completed', []) == prior,
            'completed plan selection or prefix differs')
    review, controls = bound(result['review']), bound(result['controls'])
    require(review['reviewer'] == '/root/c06_runtime_plan' and review['state'] == controls['state'] == 'PASS'
            and review['findings'] == [] and review['plan_sha256'] == controls['plan_sha256'] == result['plan']['sha256']
            and review['controls_sha256'] == result['controls']['sha256'] and controls['helpers'] == plan['helpers'],
            'completed source review differs')
    # The current adapter may evolve. Only its preserved exact source can prove
    # what ran; other frozen dependencies must still match their bound bytes.
    snapshot = bound(result['source_at_run'])
    by_original = {member['original']['path']: (name, member) for name, member in snapshot.items()}
    require(snapshot and len(by_original) == len(snapshot), 'ambiguous source snapshot members')
    consumed = set()
    for name, reference in plan['helpers'].items():
        saved = by_original.get(reference['path'])
        if saved is None:
            bound(reference, decode=False)
        else:
            snapshot_name, member = saved
            require(member['original'] == reference and member['copied']['sha256'] == reference['sha256'],
                    'source-at-run differs from reviewed helper')
            bound(member['copied'], decode=False)
            consumed.add(snapshot_name)
    require(consumed == set(snapshot), 'unbound source snapshot member')
    summary = bound(result['original_summary'])
    successful(summary)
    run = summary['identity']['run_id']
    require(summary['identity']['cell'] == expected and summary['identity']['source'] == plan['source']
            and summary['identity']['bundle'] == plan['product']['bundle']
            and summary['runtime_plan_sha256'] == result['plan']['sha256'], 'completed native identity differs')
    folder = Path(result['original_summary']['path']).parent
    require(folder == Path(result['plan']['path']).parent/'cells'/
            '-'.join([expected['build'], 'duo', 'SwiftUI', expected['layout'], 'single']), 'foreign cell directory')
    for name, digest in summary['artifacts'].items():
        path = folder/name
        require(path.resolve().is_relative_to(folder.resolve()), 'artifact escapes completed cell')
        bound(dict(path=str(path), sha256=digest), decode=False)
    for key, filename in (('local_result', 'local-result.json'), ('receipts', 'receipts.json'), ('events', 'events.jsonl')):
        require(result[key] == dict(path=str(folder/filename), sha256=summary['artifacts'][filename]),
                'completed result points outside its inventory')
    local, receipts = bound(result['local_result']), bound(result['receipts'])
    require(local['run_id'] == run and local['cell'] == [expected[k] for k in ('build', 'device', 'framework', 'layout')]
            and local['proof'] == 'LOCAL_MAPPER'
            and not any(local[k] for k in ('duplicate_action_ids', 'unknown_action_owners', 'unassigned_actions', 'errors')),
            'completed telemetry ownership is unqualified')
    recaptured = human_effect_recapture.observation_summary(receipts)
    require(result['recaptured_effects'] == summary['recaptured_effects'] == local['recaptured_effects'] == recaptured,
            'completed recapture classification changed')
    cell = supported.read(folder/'cell-result.json')
    successful(cell)
    require(cell['identity'] == summary['identity'] and cell['recaptured_effects'] == recaptured,
            'cell and terminal summary differ')
    native_review = bound(result['native_review'])
    require(native_review['state'] == 'PASS' and native_review['reviewer'] == '/root/c06_runtime_plan'
            and native_review['findings'] == [] and native_review['run_id'] == run
            and native_review['summary_sha256'] == result['original_summary']['sha256']
            and native_review['local_result_sha256'] == result['local_result']['sha256']
            and native_review['receipts_sha256'] == result['receipts']['sha256']
            and native_review['cell_result_sha256'] == summary['artifacts']['cell-result.json'],
            'completed native review differs')
    supervisor = bound(summary['supervisor'])
    post = bound(result['post_exit'])
    require(supervisor['state'] == post['state'] == 'PASS' and supervisor['quiescent'] is True
            and supervisor['remaining'] == [] and supervisor['child_exit'] == 0
            and post['run_id'] == run and post['summary_sha256'] == result['original_summary']['sha256']
            and post['supervisor_sha256'] == summary['supervisor']['sha256']
            and all(post[k] is True for k in ('controller_absent', 'app_pid_absent', 'task_container_absent', 'instruction_server_absent')),
            'completed cleanup or quiescence is incomplete')
    if not prior:
        require(result['state'] == 'NATIVE_BASELINE_QUALIFIED'
                and result['counts']['native_effects'] == 29 and result['counts']['folds'] == 3,
                'first baseline scope differs')
    return plan


def selection(owner):
    require(owner['swiftui_preparation']['universe'] == UNIVERSE, 'SwiftUI universe changed')
    completed = owner['completed_swiftui_cells']
    require(isinstance(completed, list) and 1 <= len(completed) < len(UNIVERSE), 'no untouched SwiftUI successor')
    plans = [accepted(item, UNIVERSE[i], completed[:i]) for i, item in enumerate(completed)]
    return UNIVERSE[len(completed)].copy(), completed, plans


def current_selection(plan, plan_reference):
    owner = supported.read(plan['coverage_owner'])
    require(owner['completed_swiftui_cells'] == plan['completed']
            and owner['current']['plan'] == plan_reference
            and owner['current']['remaining_matrix'] == UNIVERSE[len(plan['completed']):]
            and owner['swiftui_preparation']['matrix'] == [plan['selected']],
            'current continuation was replaced or already advanced')
