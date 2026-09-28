"""Continue only untouched S2 coverage cells, keeping stack evidence separately typed."""
import argparse
import json
from pathlib import Path
import shutil
import time
import human_candidate as candidate
import human_sessions as sessions

KIND = 'AUTOMATIC_S2_REMAINING_SESSION'
OWNER_KEY = 's2_remaining_continuation'
CLASSES = ['ACCEPTED_NATIVE', 'OFFLINE_COMPARISON', 'CANDIDATE_ONLY']
BUILDS = ['baseline-26.5', 'baseline-27.1', 'candidate-27.1']


def check(value, message, runner):
    runner.require(value, 'remaining coverage: ' + message)


def universe(matrix, runner):
    expected = runner.s2_matrix(runner.shared.read(runner.build.OWNER), runner.shared.read(runner.REGISTER))
    check(matrix == expected, 'original finite matrix changed', runner)
    return [row for row in matrix if (row['framework'], row['layout']) != ('UIKit', 'stack')]


def select(matrix, accepted, count, runner):
    check(type(count) is int and 1 <= count <= 3, 'one to three complete cells required', runner)
    check(list(accepted) == [runner.cell_key(row) for row in matrix[:len(accepted)]],
          'predecessors include excluded, missing or reordered cells', runner)
    rows = matrix[len(accepted):len(accepted) + count]
    check(len(rows) == count, 'sitting exceeds the remaining matrix', runner)
    return rows


def predecessors(row, accepted, runner):
    if row['build'] == 'candidate-27.1':
        required = {runner.cell_key(dict(row, build=build)) for build in BUILDS[:2]}
        check(required <= accepted, 'candidate requires both completed same-family baselines', runner)


def excluded(ref, base, runner):
    s = runner.shared; value = sessions.read_reference(ref, s)
    rows = value['rows']
    check(value['state'] == 'REVIEWED_STACK_EXCLUDED' and value['native_cells_credited'] == 0
          and value['gates_closed'] == [] and len(rows) == 3, 'excluded scope expanded or credited', runner)
    check([row['cell'] for row in rows] == [dict(candidate.CELL, build=build) for build in BUILDS]
          and [row['evidence_class'] for row in rows] == CLASSES, 'excluded identities or evidence classes changed', runner)
    refs = dict(accepted_baseline_reference=rows[0]['reference'], offline_comparison_reference=rows[1]['reference'])
    baselines = candidate.reference_inputs(refs, base, runner)
    outcome = sessions.read_reference(rows[2]['reference'], s)
    candidate.nested_references(outcome, s)
    check(outcome['state'] == 'PASS_SCOPED_UIKIT_STACK_COMPARISON' and outcome['cell'] == candidate.CELL
          and outcome['source'] == s.ARMS['B'] and outcome['native_cells_credited'] == 0 and outcome['gate_closures'] == []
          and all(outcome[k] == 'PASS' for k in ['scenario', 'evidence', 'cleanup', 'worker_quiescence']),
          'candidate assessment is incomplete or expanded', runner)
    row, out, runtime, old, stage = candidate.history(outcome['summary'], base, runner)
    check(old['kind'] == candidate.KIND and old['matrix'] == old['universe'] == [candidate.CELL]
          and old['inherited'] == {} and old['previous'] is None
          and old['accepted_baseline_reference'] == outcome['accepted_baseline'] == refs['accepted_baseline_reference']
          and old['offline_comparison_reference'] == outcome['offline_baseline'] == refs['offline_comparison_reference'],
          'candidate reference lineage changed', runner)
    check(outcome['plan'] == sessions.reference(runtime/'runtime-plan.json', s)
          and outcome['local_result'] == sessions.reference(out/'local-result.json', s)
          and outcome['candidate_complete'] == sessions.reference(runtime/'candidate-complete.json', s)
          and outcome['comparison'] == sessions.reference(runtime/'comparison.json', s)
          and outcome['run_id'] == row['identity']['run_id'], 'candidate evidence paths changed', runner)
    native = sessions.cells(runtime.parent, old, stage, runner)
    complete = sessions.read_reference(outcome['candidate_complete'], s)
    check(complete['state'] == 'CANDIDATE_CAPTURE_COMPLETE' and complete['candidate'] == native
          and complete['comparison_sha256'] == outcome['comparison']['sha256']
          and complete['stage_sha256'] == s.sha(runtime/'native-admission.json')
          and complete['release_acceptance'] is False and complete['native_cells_credited'] == 0
          and complete['gates_closed'] == [], 'candidate completion changed', runner)
    run = s.read(runtime/'session-run.json')
    check(run['stage_id'] == stage['stage_id'] and run['plan_sha256'] == stage['runtime_plan_sha256']
          and stage['issued_at'] <= run['started_at'] < complete['finished_at'] <= stage['cleanup_deadline']
          and type(run['pid']) is int and run['pid'] > 1 and not s.process(run['pid']), 'candidate runner still active or terminal changed', runner)
    local = sessions.read_reference(outcome['local_result'], s)
    expected = [dict(reference_class=kind, family=family, **runner.analyze.compare(before, local, family))
                for kind, before in baselines.items() for family in ['views', 'actions']]
    comparison = sessions.read_reference(outcome['comparison'], s)
    check(comparison['state'] == 'CANDIDATE_COMPARISON_CAPTURED' and comparison['comparisons'] == expected
          and comparison['source_differences'] == 0
          and all(row['status'] in ['UNCHANGED_OBSERVED_COVERAGE', 'UNCHANGED_LIMITATION'] for row in expected),
          'stack comparison has unclassified differences', runner)
    review = sessions.read_reference(outcome['review'], s)
    check(review['state'] == 'PASS_SCOPED_PROGRESS' and review['reviewer'] == '/root/c06_runtime_plan'
          and review['findings'] == [] and review['candidate']['summary'] == outcome['summary']
          and review['candidate']['comparison'] == outcome['comparison'], 'stack outcome review changed', runner)
    for key in ['products', 'observer_refresh', 'measurement']:
        check(old[key] == base[key], 'qualified candidate ' + key + ' changed', runner)
    check(value['home_qualification'] == old['home_qualification'] and value['home_provenance'] == old['home_provenance'],
          'Home qualification substituted', runner)
    candidate.verify_home(value, base, runner)
    owner = s.read(runner.build.OWNER)['human_current_composition']
    expected_ledgers = [owner[key]['series'] for key in ['session_continuation', 's2_session_continuation']] + [old['series']]
    check(value['blocked_series'] == expected_ledgers, 'historical claim ledgers changed', runner)
    return value


def no_overlap(plan, runner):
    s = runner.shared; value = sessions.read_reference(plan['excluded_prefix_reference'], s)
    selected = {runner.cell_key(row) for row in plan['matrix']}
    for ref in value['blocked_series']:
        sessions.read_reference(ref, s)
        folder = Path(ref['path']).parent/'claims'
        check(folder.is_dir() and not folder.is_symlink(), 'historical claims missing or redirected', runner)
        check(not any((folder/(key+'.json')).exists() for key in selected), 'cell consumed by a historical series', runner)


def verify(root, plan, runner, seen=()):
    s = runner.shared; root = Path(root); source = Path(plan['source_runtime_root']); base = runner.verify(source)
    check(plan['kind'] == KIND and base['kind'] == runner.S2_KIND
          and plan['source_runtime'] == sessions.reference(source/'runtime/runtime-plan.json', s), 'source runtime changed', runner)
    matrix = universe(base['matrix'], runner)
    check(plan['original_universe'] == base['matrix'] and plan['universe'] == matrix
          and plan['native_admitted'] is False and plan['gates_closed'] == [], 'remaining universe or preparation scope changed', runner)
    check(all(plan[k] == base[k] for k in candidate.FIELDS)
          and plan['helpers'] == s.tree(root/'runtime/helpers'), 'current products or helper closure changed', runner)
    previous = plan['previous']
    if previous:
        old = s.read(Path(previous['root'])/'runtime/runtime-plan.json')
        check(old['kind'] == KIND and all(old[k] == plan[k] for k in
              ['source_runtime', 'series', 'excluded_prefix_reference', 'universe']), 'foreign predecessor or series', runner)
    accepted = sessions.inherited(plan, runner, seen or (str(root),))
    check(plan['inherited'] == accepted and plan['matrix'] == select(matrix, accepted, plan['cell_count'], runner),
          'selected cells or native inheritance changed', runner)
    check(plan['contract'] == dict(base['contract'], stage_execution_seconds=sessions.budget(plan['matrix'], base['contract'], runner)),
          'sitting budget changed', runner)
    series = sessions.read_reference(plan['series'], s)
    check(series == series_record(plan), 'canonical series changed', runner)
    excluded(plan['excluded_prefix_reference'], base, runner)
    no_overlap(plan, runner)
    return plan


def series_record(plan):
    return dict(kind=KIND, native_attempts_per_cell=1, **{k: plan[k] for k in
                ['source_runtime', 'universe', 'original_universe', 'excluded_prefix_reference', 'helpers']})


def ready(root, plan, operator, runner):
    s = runner.shared; folder = root/'runtime'
    owner = s.read(runner.build.OWNER)['human_current_composition'].get(OWNER_KEY, {})
    check(owner.get('series') == plan['series'] and owner.get('plan') == sessions.reference(folder/'runtime-plan.json', s),
          'missing canonical owning-record authority', runner)
    check(not (folder/'session-run.json').exists() and not (folder/'session-complete.json').exists()
          and not list((folder/'cells').iterdir()), 'sitting already consumed', runner)
    runner.human_operator.ready(folder/'operator', dict(operator, plan_sha256=operator['runtime_plan_sha256']),
                                folder/'runtime-plan.json', device=operator['device'], mode='coverage')
    for prior in sessions.ancestors(plan, s):
        stage = s.read(prior/'runtime/native-admission.json'); old = s.read(stage['operator_path'])
        check(operator['user_message_reference'] != old['user_message_reference']
              and operator['at'] > s.read(prior/'runtime/session-complete.json')['finished_at'], 'consumed operator readiness', runner)
    no_overlap(plan, runner)


def claim(root, plan, stage, runner):
    no_overlap(plan, runner)
    return sessions.claim(root, plan, stage, runner)


def prepare(args, runner):
    s = runner.shared; source = args.original.resolve(); root = args.root.resolve(); base = runner.verify(source)
    check(base['kind'] == runner.S2_KIND and not root.exists(), 'fresh remaining sitting required', runner)
    ref = sessions.reference(args.excluded, s); excluded(ref, base, runner)
    previous = args.previous.resolve() if args.previous else None
    accepted = sessions.completed(previous, runner) if previous else {}
    matrix = universe(base['matrix'], runner); selected = select(matrix, accepted, args.cells, runner)
    plan = {**{k: base[k] for k in candidate.FIELDS}, 'kind': KIND, 'prepared_at': time.time(),
            'source_runtime_root': str(source), 'source_runtime': sessions.reference(source/'runtime/runtime-plan.json', s),
            'excluded_prefix_reference': ref, 'original_universe': base['matrix'], 'universe': matrix,
            'matrix': selected, 'cell_count': args.cells, 'inherited': accepted,
            'contract': dict(base['contract'], stage_execution_seconds=sessions.budget(selected, base['contract'], runner)),
            'previous': {'root': str(previous), **{name+'_sha256': s.sha(previous/'runtime'/(name+'.json'))
                         for name in ['runtime-plan', 'session-complete']}} if previous else None,
            'native_admitted': False, 'gates_closed': []}
    if previous:
        old = s.read(previous/'runtime/runtime-plan.json'); plan['series'] = old['series']
        check(old['kind'] == KIND and old['excluded_prefix_reference'] == ref
              and (args.series is None or args.series.resolve() == Path(old['series']['path']).parent), 'foreign predecessor series', runner)
    else:
        owner = s.read(runner.build.OWNER)['human_current_composition']
        check(OWNER_KEY not in owner and args.series is not None and not args.series.exists(), 'canonical remaining series already exists', runner)
        args.series.mkdir(); (args.series/'claims').mkdir()
        s.save(args.series/'series.json', series_record(plan), exclusive=True)
        plan['series'] = sessions.reference(args.series/'series.json', s)
    no_overlap(plan, runner)
    folder = root/'runtime'; folder.mkdir(parents=True)
    for name in ['cells', 'operator']: (folder/name).mkdir()
    shutil.copytree(source/'runtime/helpers', folder/'helpers')
    plan['publication'] = runner.transport.publication_preflight(folder)
    runner.human_operator.publish(folder/'operator', {'instruction': 'Waiting for review and fresh readiness for untouched coverage cells.'})
    s.save(folder/'runtime-plan.json', plan, exclusive=True); verify(root, plan, runner)
    print(json.dumps(dict(state='REMAINING_SITTING_PREPARED_NOT_ADMITTED', root=str(root), cells=len(selected),
                          preserved_native_cells=len(accepted), excluded_stack_cells=3, native_launches=0)))


if __name__ == '__main__':
    import human_runtime as runner
    parser = argparse.ArgumentParser()
    for name in ['root', 'original', 'excluded']: parser.add_argument('--'+name, type=Path, required=True)
    for name in ['series', 'previous']: parser.add_argument('--'+name, type=Path)
    parser.add_argument('--cells', type=int, default=1)
    prepare(parser.parse_args(), runner)
