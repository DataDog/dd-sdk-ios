"""One UIKit split candidate, with typed references and a scoped Home limitation."""
import argparse
import json
from pathlib import Path
import shutil
import time
import human_candidate as candidate
import human_sessions as sessions
import split_capture
import split_ownership as ownership

KIND = 'S2_SPLIT_CANDIDATE'
CELL = dict(candidate.CELL, layout='split')
OWNER = 'DatadogRUM/MultiSceneSupport/Results/S2-coverage-remaining-preparation.json'


def check(value, message, runner):
    runner.require(value, 'split candidate: '+message)


def reference_inputs(plan, base, runner):
    s = runner.shared
    qualification = sessions.read_reference(plan['profile_qualification'], s)
    candidate.nested_references(qualification, s)
    check(qualification['state'] == 'PASS_SCOPED_OFFLINE_PROFILE' and qualification['reviewer'] == '/root/c06_runtime_plan'
          and not qualification['findings'] and qualification['native_admitted'] is False,
          'offline profile is not reviewed', runner)
    replay = sessions.read_reference(qualification['saved_replay'], s)
    candidate.nested_references(replay, s)
    native = sessions.read_reference(plan['accepted_baseline_reference'], s)
    offline = sessions.read_reference(plan['offline_comparison_reference'], s)
    candidate.nested_references(native, s); candidate.nested_references(offline, s)
    check(native['state'] == 'PASS_SCOPED_UIKIT_SPLIT_BASELINE' and native['cell'] == dict(CELL, build='baseline-26.5')
          and all(native[key] == 'PASS' for key in ['scenario', 'evidence', 'cleanup', 'worker_quiescence']),
          'wrong accepted split reference', runner)
    check(offline['state'] == 'OFFLINE_SPLIT_OWNER_REPLAY' and offline['original_verdict'] == offline['original_cleanup'] == 'INVALID'
          and offline['native_cells_credited'] == 0 and not offline['gates_closed'], 'offline reference relabeled', runner)
    check(native['source'] == offline['source'] == s.ARMS['A'] and native['run_id'] != offline['run_id']
          and replay['assessment'] == plan['offline_comparison_reference'] and replay['source_prefix'] == offline['source_prefix'],
          'split reference source or run changed', runner)
    row, out, runtime, old, stage = candidate.history(native['summary'], base, runner)
    check(row['identity']['cell'] == native['cell'] and old['matrix'] == [native['cell']], 'accepted cell changed', runner)
    accepted = sessions.cells(runtime.parent, old, stage, runner)
    complete = sessions.read_reference(native['complete'], s)
    check(complete['state'] == 'COMPLETE_SITTING' and complete['accepted'] == accepted
          and complete['stage_sha256'] == s.sha(runtime/'native-admission.json'), 'accepted completion changed', runner)
    failed, failed_out, failed_runtime, failed_plan, _ = candidate.history(offline['original_summary'], base, runner)
    check(failed['state'] == failed['cleanup'] == 'INVALID' and failed['identity']['cell'] == dict(CELL, build='baseline-27.1')
          and failed['identity']['run_id'] == offline['run_id'], 'original failure changed', runner)
    restored = sessions.read_reference(offline['separate_restoration'], s)
    check(restored['state'] == 'PASS' and restored['original_verdicts_unchanged'] is True
          and restored['immutable_inputs_verified'] is True and restored['scenario_credit'] is False
          and all(restored[key] is True for key in ['task_absent', 'original_inventory_restored', 'original_display_restored']),
          'separate restoration changed', runner)
    check(plan['blocked_series'] == [failed_plan['series']], 'historical claim ledger changed', runner)
    for previous in [runtime, failed_runtime]:
        check(not s.process(s.read(previous/'session-run.json')['pid']), 'reference runner is active', runner)
    ownership.native = runner.capture.oracle
    value = ownership.evaluate(Path(replay['source_prefix']['path']).read_bytes(),
        prefix=Path(replay['home_prefix']['path']).read_bytes(), expected=replay['expected'],
        home_request=Path(replay['home_request']['path']).read_bytes(),
        home_idle=s.read(replay['home_idle']['path']), reference_tail=replay['reference_tail'])
    check(value is not None, 'saved owner inventory is pending', runner)
    baseline = ownership.comparison_inventory(dict(run_id=offline['run_id'], **dict(CELL, build='baseline-27.1')),
        value, sessions.read_reference(replay['boundaries'], s)['rows'])
    check(json.loads(json.dumps(baseline)) == sessions.read_reference(replay['comparison_inventory'], s),
          'reviewed owner inventory changed', runner)
    return dict(ACCEPTED_BASELINE_26_5=sessions.read_reference(native['local_result'], s),
                OFFLINE_COMPARISON_27_1=baseline), replay


def verify_home(plan, base, runner):
    """Reuse the native writer protocol; the new host hook has its own review."""
    s = runner.shared
    home = sessions.read_reference(plan['home_qualification'], s)
    candidate.nested_references(plan['home_provenance'], s)
    provenance = {key: sessions.read_reference(value, s) for key, value in plan['home_provenance'].items()}
    check(set(provenance) == {'definition', 'review', 'admission', 'post_exit'}
          and provenance['review']['state'] == 'PASS' and provenance['review']['reviewer'] == '/root/c06_runtime_plan'
          and provenance['admission']['definition_sha256'] == provenance['review']['definition_sha256'] == plan['home_provenance']['definition']['sha256']
          and provenance['admission']['identity'] == home['identity'] and provenance['post_exit']['result'] == plan['home_qualification']
          and provenance['definition']['refresh'] == base['observer_refresh'], 'Home protocol provenance changed', runner)
    check(all(home[key] == 'PASS' for key in ['state', 'scenario', 'evidence', 'cleanup'])
          and home['release_acceptance'] is False and home['native_cells_credited'] == 0
          and provenance['post_exit']['processes_absent'] is True, 'native Home qualification incomplete', runner)
    q = Path(plan['home_qualification']['path']).parent.parent
    for name, digest in home['artifacts'].items():
        check(s.sha(q/'out'/name) == digest, 'Home qualification artifact changed', runner)
    for name in ['HumanObservation.swift', 'human_variant.py']:
        path = 'tools/multi-scene/automatic-coverage/'+name
        expected = provenance['definition']['helpers'].get(path,
            sessions.read_reference(base['observer_refresh'], s)['observer_sha256'] if name == 'HumanObservation.swift' else None)
        check(s.sha(s.REPO/path) == expected, 'native Home writer or fixture changed', runner)


def no_overlap(plan, runner):
    for ref in plan['blocked_series']:
        sessions.read_reference(ref, runner.shared)
        claims = Path(ref['path']).parent/'claims'
        check(claims.is_dir() and not (claims/(runner.cell_key(CELL)+'.json')).exists(),
              'candidate consumed by another series', runner)


def series_record(plan):
    return dict(kind=KIND, native_attempts_per_cell=1, **{key: plan[key] for key in
        ['source_runtime', 'profile_qualification', 'accepted_baseline_reference', 'offline_comparison_reference',
         'home_qualification', 'home_provenance', 'blocked_series', 'helpers', 'universe']})


def verify(root, plan, runner):
    s = runner.shared; source = Path(plan['source_runtime_root']); base = runner.verify(source)
    check(plan['kind'] == KIND and base['kind'] == runner.S2_KIND
          and plan['source_runtime'] == sessions.reference(source/'runtime/runtime-plan.json', s), 'source preparation changed', runner)
    check(plan['matrix'] == plan['universe'] == [CELL] and plan['inherited'] == {} and plan['previous'] is None
          and plan['release_acceptance'] is False and plan['native_cells_credited'] == 0 and plan['gates_closed'] == [],
          'expanded scope or inherited acceptance', runner)
    check(all(plan[key] == base[key] for key in candidate.FIELDS) and s.tree(root/'runtime/helpers') == plan['helpers'],
          'current product/helper binding changed', runner)
    check(plan['contract'] == dict(base['contract'], stage_execution_seconds=sessions.budget([CELL], base['contract'], runner)),
          'collection or cleanup clocks changed', runner)
    check(sessions.read_reference(plan['series'], s) == series_record(plan), 'series changed', runner)
    verify_home(plan, base, runner); reference_inputs(plan, base, runner); no_overlap(plan, runner)
    return plan


def ready(root, plan, operator, runner):
    s = runner.shared; folder = root/'runtime'; owner = s.read(s.REPO/OWNER)['split_continuation']
    check(owner['plan'] == sessions.reference(folder/'runtime-plan.json', s) and owner['series'] == plan['series'],
          'missing owning-record authority', runner)
    check(not (folder/'session-run.json').exists() and not (folder/'candidate-complete.json').exists()
          and not list((folder/'cells').iterdir()), 'candidate already consumed', runner)
    runner.human_operator.ready(folder/'operator', dict(operator, plan_sha256=operator['runtime_plan_sha256']),
                                folder/'runtime-plan.json', device=operator['device'], mode='coverage')
    no_overlap(plan, runner)


def collector(plan, identity, runner, **kwargs):
    qualification = sessions.read_reference(plan['profile_qualification'], runner.shared)
    reference = sessions.read_reference(qualification['saved_replay'], runner.shared)
    check(identity['cell'] == CELL and identity['source'] == runner.shared.ARMS['B'], 'wrong native candidate', runner)
    return split_capture.Collector(identity=identity, reference=reference, **kwargs)


def comparison(folder, plan, stage, runner):
    references, _ = reference_inputs(plan, runner.verify(Path(plan['source_runtime_root'])), runner)
    attempted = runner.prior_cells(folder, plan, stage); comparisons = []
    if attempted:
        current = runner.shared.read(folder/'cells'/runner.cell_key(CELL)/'local-result.json')
        check(current['run_id'] not in {value['run_id'] for value in references.values()}, 'restored baseline run', runner)
        comparisons.append(dict(reference_class='OFFLINE_COMPARISON_27_1',
                                **ownership.compare(references['OFFLINE_COMPARISON_27_1'], current)))
    differences = [row for row in comparisons if row['state'] != 'OWNER_RELATIONSHIPS_UNCHANGED']
    return dict(state='REVIEW_REQUIRED' if differences else 'SCOPED_CANDIDATE_CAPTURED' if attempted else 'CANDIDATE_NOT_RUN',
        runtime_plan_sha256=stage['runtime_plan_sha256'], stage_id=stage['stage_id'], qualified_cells=len(attempted), required_cells=1,
        reference_classes=list(references), historical_26_5=references['ACCEPTED_BASELINE_26_5'], comparisons=comparisons,
        source_differences=len(differences), cross_compiler_equality_required=False, home_lifecycle_qualified=False,
        release_acceptance=False, native_cells_credited=0, gates_closed=[], updated_at=time.time())


def finish(root, plan, stage, runner):
    s = runner.shared; folder = root/'runtime'; native = runner.prior_cells(folder, plan, stage)
    result = comparison(folder, plan, stage, runner)
    check(set(native) == {runner.cell_key(CELL)} and not result['source_differences']
          and time.time() <= stage['cleanup_deadline'], 'candidate incomplete or requires classification', runner)
    out = folder/'cells'/runner.cell_key(CELL)
    check(s.read(out/'split-cleanup-observations.json')['comparison_unchanged'] is True
          and s.read(out/'split-comparison-cutoff.json')['cleanup_authorized'] is False,
          'missing separate cleanup fence', runner)
    s.save(folder/'comparison.json', result)
    s.save(folder/'candidate-complete.json', dict(state='SCOPED_SPLIT_CAPTURE_COMPLETE', finished_at=time.time(),
        candidate={runner.cell_key(CELL): sessions.reference(out/'summary.json', s)},
        comparison_sha256=s.sha(folder/'comparison.json'), stage_sha256=s.sha(folder/'native-admission.json'),
        home_lifecycle_qualified=False, release_acceptance=False, native_cells_credited=0, gates_closed=[]), exclusive=True)


def prepare(args, runner):
    s = runner.shared; source = args.original.resolve(); base = runner.verify(source); root = args.root.resolve()
    check(base['kind'] == runner.S2_KIND and not root.exists() and not args.series.exists(), 'fresh split preparation required', runner)
    check('split_continuation' not in s.read(s.REPO/OWNER), 'canonical split candidate already prepared', runner)
    refs = {key: sessions.reference(getattr(args, arg), s) for key, arg in
            [('accepted_baseline_reference', 'accepted'), ('offline_comparison_reference', 'offline'),
             ('profile_qualification', 'profile'), ('home_qualification', 'home')]}
    qualification = args.home.resolve().parent.parent
    refs['home_provenance'] = {key: sessions.reference(qualification/(key.replace('_', '-')+'.json'), s)
                              for key in ['definition', 'review', 'admission', 'post_exit']}
    offline = sessions.read_reference(refs['offline_comparison_reference'], s)
    old = sessions.read_reference(offline['provenance']['runtime_plan'], s)
    folder = root/'runtime'; folder.mkdir(parents=True)
    for name in ['cells', 'operator']: (folder/name).mkdir()
    shutil.copytree(source/'runtime/helpers', folder/'helpers'); args.series.mkdir(); (args.series/'claims').mkdir()
    plan = {**{key: base[key] for key in candidate.FIELDS}, **refs, 'kind': KIND, 'prepared_at': time.time(),
        'source_runtime_root': str(source), 'source_runtime': sessions.reference(source/'runtime/runtime-plan.json', s),
        'blocked_series': [old['series']], 'matrix': [CELL], 'universe': [CELL], 'inherited': {}, 'previous': None,
        'contract': dict(base['contract'], stage_execution_seconds=sessions.budget([CELL], base['contract'], runner)),
        'release_acceptance': False, 'native_cells_credited': 0, 'gates_closed': [],
        'publication': runner.transport.publication_preflight(folder)}
    s.save(args.series/'series.json', series_record(plan), exclusive=True); plan['series'] = sessions.reference(args.series/'series.json', s)
    runner.human_operator.publish(folder/'operator', {'instruction': 'Waiting for split comparison review and fresh readiness.'})
    s.save(folder/'runtime-plan.json', plan, exclusive=True); verify(root, plan, runner)
    print(json.dumps(dict(state='SPLIT_CANDIDATE_PREPARED_NOT_ADMITTED', root=str(root), native_launches=0)))


if __name__ == '__main__':
    import human_runtime as runner
    parser = argparse.ArgumentParser()
    for name in ['root', 'original', 'series', 'accepted', 'offline', 'profile', 'home']:
        parser.add_argument('--'+name, type=Path, required=True)
    prepare(parser.parse_args(), runner)
