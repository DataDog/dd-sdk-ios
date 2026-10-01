"""Validate the new reader baseline before selecting the final split candidate.

Historical cells keep their original reviewer and source policy. This separate
adapter accepts a replacement reviewer only through the bound assignment, without
changing the already-reviewed baseline's helper closure or admitting native work.
"""
from pathlib import Path

import human_reader_continuation as c

legacy = c.ready.continuation
bound = legacy.bound
require = c.require


def accepted_baseline(item, prior, expected_plan):
    expected = legacy.UNIVERSE[4]
    require(item['selected'] == expected, 'wrong new baseline selection')
    result = bound(item['result'])
    require(result['selected'] == expected and result['state'] == 'NATIVE_CELL_QUALIFIED'
            and all(result[k] == 'PASS' for k in ('scenario', 'evidence', 'cleanup'))
            and result['native_runs'] == result['qualified_cells'] == 1,
            'new baseline is not fully qualified')
    require(result['plan'] == expected_plan, 'new baseline belongs to another reviewed plan')
    runtime = Path(expected_plan['path']).parent
    plan = bound(expected_plan)
    require(plan['kind'] == c.KIND and plan['selected'] == expected
            and plan['completed'] == prior, 'new baseline prefix differs')
    _, verified = c.verify(runtime.parent, reviewed=True)
    require(verified == plan, 'new baseline reviewed source changed')
    review, controls = bound(result['review']), bound(result['controls'])
    require(result['review'] == c.s.reference(runtime/'review.json')
            and result['controls'] == c.s.reference(runtime/'controls.json'),
            'new baseline review is outside its runtime')
    c.reviewer_assignment.require_reviewer(review, expected_plan['sha256'], runtime)
    require(review['state'] == controls['state'] == 'PASS' and not review['findings']
            and review['plan_sha256'] == controls['plan_sha256'] == expected_plan['sha256']
            and review['controls_sha256'] == result['controls']['sha256']
            and controls['helpers'] == plan['helpers'], 'new baseline source review differs')

    snapshot = bound(result['source_at_run'])
    by_original = {m['original']['path']: (name, m) for name, m in snapshot.items()}
    require(snapshot and len(by_original) == len(snapshot), 'ambiguous new baseline source snapshot')
    consumed = set()
    for name, reference in plan['helpers'].items():
        saved = by_original.get(reference['path'])
        if saved is None:
            bound(reference, decode=False)
        else:
            snapshot_name, member = saved
            require(member['original'] == reference
                    and member['copied']['sha256'] == reference['sha256'],
                    'new baseline source-at-run differs')
            bound(member['copied'], decode=False)
            consumed.add(snapshot_name)
    require(consumed == set(snapshot), 'unbound new baseline source snapshot member')

    summary = bound(result['original_summary'])
    legacy.successful(summary)
    identity = summary['identity']; run = identity['run_id']
    require(identity['cell'] == expected and identity['source'] == plan['source']
            and identity['bundle'] == plan['product']['bundle']
            and summary['runtime_plan_sha256'] == expected_plan['sha256'],
            'new baseline native identity differs')
    folder = Path(result['original_summary']['path']).parent
    require(folder == runtime/'cells'/'baseline-27.1-duo-SwiftUI-split-single',
            'foreign new baseline cell directory')
    for name, digest in summary['artifacts'].items():
        path = folder/name
        require(path.resolve().is_relative_to(folder.resolve()), 'artifact escapes new baseline cell')
        bound(dict(path=str(path), sha256=digest), decode=False)
    for key, filename in (('local_result', 'local-result.json'), ('receipts', 'receipts.json'),
                          ('events', 'events.jsonl')):
        require(result[key] == dict(path=str(folder/filename), sha256=summary['artifacts'][filename]),
                'new baseline result escapes its artifact inventory')
    local, receipts = bound(result['local_result']), bound(result['receipts'])
    require(local['run_id'] == run
            and local['cell'] == [expected[k] for k in ('build', 'device', 'framework', 'layout')]
            and local['proof'] == 'LOCAL_MAPPER'
            and not any(local[k] for k in ('duplicate_action_ids', 'unknown_action_owners',
                                         'unassigned_actions', 'errors')),
            'new baseline telemetry ownership is unqualified')
    recaptured = c.ready.human_effect_recapture.observation_summary(receipts)
    cell = c.s.read(folder/'cell-result.json'); legacy.successful(cell)
    require(result['recaptured_effects'] == summary['recaptured_effects']
            == local['recaptured_effects'] == cell['recaptured_effects'] == recaptured
            and cell['identity'] == identity, 'new baseline terminal or recapture evidence differs')
    native = bound(result['native_review'])
    c.reviewer_assignment.require_reviewer(native, expected_plan['sha256'], runtime)
    require(native['state'] == 'PASS' and native['reviewer'] == review['reviewer']
            and not native['findings'] and native['run_id'] == run
            and native['summary_sha256'] == result['original_summary']['sha256']
            and native['local_result_sha256'] == result['local_result']['sha256']
            and native['receipts_sha256'] == result['receipts']['sha256']
            and native['cell_result_sha256'] == summary['artifacts']['cell-result.json'],
            'new baseline native review differs')
    supervisor, post = bound(summary['supervisor']), bound(result['post_exit'])
    require(supervisor['state'] == post['state'] == 'PASS' and supervisor['quiescent'] is True
            and supervisor['remaining'] == [] and supervisor['child_exit'] == 0
            and post['run_id'] == run
            and post['summary_sha256'] == result['original_summary']['sha256']
            and post['supervisor_sha256'] == summary['supervisor']['sha256']
            and all(post[k] is True for k in ('controller_absent', 'app_pid_absent',
                                            'task_container_absent', 'instruction_server_absent')),
            'new baseline cleanup or quiescence is incomplete')
    return plan


def selection(owner, expected_baseline, preserved_helpers):
    require(owner['swiftui_preparation']['universe'] == legacy.UNIVERSE, 'SwiftUI universe changed')
    completed = owner['completed_swiftui_cells']
    require(isinstance(completed, list) and len(completed) == 5,
            'candidate requires exactly four historical cells and one new baseline')
    old = [legacy.accepted(item, legacy.UNIVERSE[i], completed[:i],
                           preserved_helpers=preserved_helpers)
           for i, item in enumerate(completed[:4])]
    baseline = accepted_baseline(completed[4], completed[:4], expected_baseline)
    return legacy.UNIVERSE[5].copy(), completed, old, baseline
