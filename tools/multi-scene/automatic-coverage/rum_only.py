"""RUM-only verdicts for human automatic-coverage cells.

Opt-in. A cell passes or fails on its local RUM mapper rows alone: View
occurrences, automatic Actions, their owning views and error rows. Native
input-proof checks (accessibility inventory, visible targets, counter labels,
callback ordering, fold geometry) still run, but only as per-step diagnostics;
they never stop a journey or decide a cell.

Evidence integrity (run identity, contiguous native sequence, durable writer
prefix, window binding) and operational bounds (cell deadline, original process,
interruption) remain hard stops: without them the RUM stream cannot be trusted.
Existing helpers are reused unchanged, so frozen plans keep their bindings.
"""
import hashlib
import json
from pathlib import Path
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / 'acceptance'))
from acceptance_common import Rejected  # noqa: E402
import analyze  # noqa: E402

MODE = 'RUM_ONLY'
FAULTS = ('duplicate_action_ids', 'unknown_action_owners', 'unassigned_actions', 'errors')
INPUT_KINDS = ('human_callback', 'native_input', 'human_scroll_begin', 'human_scroll_end', 'native_background')
LABELS = {'tap': 'Tap', 'toggle': 'Enable', 'scroll': 'the rows', 'next': 'Open detail', 'sheet': 'Present sheet',
          'back': 'Return home', 'close': 'Dismiss sheet'}
PROMPT_RACE = 'readiness consumed before human prompt'


class EvidenceError(RuntimeError):
    """The native evidence stream is invalid, so no RUM verdict can be derived."""


# Never downgraded to a diagnostic. InterruptedError (SIGTERM) is an OSError.
HARD_STOPS = (EvidenceError, OSError)
SUPERVISOR_STOP = 'supervisor stopped execution'


def supervisor_stop(error):
    # Current reviewed opt-in entrypoints use this explicit RuntimeError sentinel
    # for SIGTERM. Preserve it without changing their frozen source bindings.
    return isinstance(error, RuntimeError) and str(error) == SUPERVISOR_STOP


def save(path, value):
    with Path(path).open('x') as stream:
        json.dump(value, stream, indent=2, default=str)
        stream.write('\n')


def record(collector, phase, check, reason):
    if isinstance(reason, BaseException):
        reason = type(reason).__name__ + ': ' + str(reason)
    entry = dict(phase=phase, check=check, reason=reason)
    collector.rum_only_diagnostics.append(entry)
    return entry


def diagnose(collector, phase, check, action, *, allow_rejected=False):
    """Run one input-proof check and return (value, reason); a failure is recorded, not raised.

    Rejected covers deadlines and process identity, so it stays fatal unless the
    caller opts in; even then the cell deadline and process are re-checked first.
    """
    try:
        return action(), None
    except HARD_STOPS:
        raise
    except Rejected as error:
        if not allow_rejected:
            raise
        collector.live(collector.deadline)
        return None, record(collector, phase, check, error)['reason']
    except Exception as error:
        if supervisor_stop(error):
            raise
        collector.live(collector.deadline)
        return None, record(collector, phase, check, error)['reason']


def snapshot(collector, runner, phase, deadline):
    """Durable snapshot whose input-proof validation failure becomes a diagnostic."""
    if phase in collector.phases:
        raise EvidenceError('consumed snapshot phase: ' + phase)
    try:
        return type(collector).snapshot(collector, phase, deadline)
    except (HARD_STOPS + (Rejected,)):
        raise
    except Exception as error:
        if supervisor_stop(error):
            raise
        result = recover(collector, runner, phase, error)
        collector.live(deadline)
        return result


def recover(collector, runner, phase, error):
    """Re-validate the committed bytes of a failed snapshot without its topology checks."""
    oracle = runner.capture.oracle
    folder = collector.output / phase
    try:
        request_bytes = (folder / 'request.json').read_bytes()
        request = json.loads(request_bytes)
        receipt = json.loads((folder / 'writer-checkpoint.json').read_bytes())
        rows = oracle.checkpoint((folder / 'events.jsonl').read_bytes(), receipt, collector.run, request['request_id'])
        binding = oracle.one([r for r in rows if r['kind'] == 'human_window_binding'], 'window binding')
        taken = oracle.one([r for r in rows if r['kind'] == 'human_snapshot'
                            and r['payload'].get('request_id') == request['request_id']], 'snapshot')
        identity = (request.get('run_id') == collector.run and request.get('phase') == phase
                    and taken['payload'].get('phase') == phase
                    and taken['payload'].get('request_sha256') == hashlib.sha256(request_bytes).hexdigest()
                    and binding['sequence'] < taken['sequence']
                    and type(taken['payload'].get('uptime_ns')) is int and taken['payload']['uptime_ns'] > 0)
        # Reuse the unchanged source/window predicates. Only the accessibility
        # inventory is omitted from this validation projection; the original
        # captured topology and durable rows stay intact below.
        owned_topology = dict(taken['payload']['topology'], accessibility=[])
        oracle.topology(owned_topology, binding['payload'])
    except EvidenceError:
        raise
    except Exception as failure:
        raise EvidenceError('unrecoverable snapshot ' + phase + ': ' + str(failure) + ' (after: ' + str(error) + ')') from error
    if not identity:
        raise EvidenceError('stale or foreign snapshot ' + phase + ' (after: ' + str(error) + ')')
    if collector.binding is None:
        collector.binding = binding['payload']
    elif collector.binding != binding['payload']:
        raise EvidenceError('fixture source binding replaced at ' + phase)
    collector.evidence = rows
    reason = record(collector, phase, 'snapshot', error)['reason']
    save(folder / 'rum-only-capture.json', dict(state='DURABLE_NATIVE_SNAPSHOT_WITH_DIAGNOSTIC', mode=MODE,
         request_id=request['request_id'], sequence=taken['sequence'], diagnostic=reason, captured_at=time.time()))
    return taken, folder


def enable(collector, runner):
    """Route the collector's own snapshots (fold, Home, root) through the tolerant reader."""
    if getattr(collector, 'rum_only', False):
        return
    collector.rum_only = True
    collector.rum_only_diagnostics = []
    collector.snapshot = lambda phase, deadline: snapshot(collector, runner, phase, deadline)


def wait_for(collector, condition, deadline):
    """Poll until the step deadline; unlike Collector.wait, expiry returns None."""
    while time.time() < deadline:
        collector.live(collector.deadline)
        value = condition()
        if value is not None:
            return value
        time.sleep(.1)
    return None


def input_signal(collector, before, step):
    rows = [r for r in collector.pending() if r['sequence'] > before['sequence']]
    if step['kind'] == 'scroll':
        found = [r for r in rows if r['kind'] == 'human_scroll_end']
    elif collector.framework == 'SwiftUI' and step['target'].endswith('.next'):
        found = [r for r in rows if r['kind'] == 'native_appear' and r['payload'].get('screen') == step['after_screen']]
    else:
        found = [r for r in rows if r['kind'] == 'native_input']
    return found or None


def prompt(collector, step, folder, deadline, before):
    phase = step['phase']
    if any(r['sequence'] > before['sequence'] and r['kind'] in INPUT_KINDS for r in collector.pending()):
        record(collector, phase, 'prompt', 'input observed before the prompt; no prompt issued')
        return
    control = step['target'].split('.')[-1]
    instruction = ('On ' + step['screen'] + ', ' + ('scroll ' if control == 'scroll' else 'tap ')
                   + LABELS[control] + ' once, then wait.')
    try:
        collector.prompt(phase, instruction, folder, deadline, before)
    except Rejected as error:
        if str(error) != PROMPT_RACE:
            raise
        record(collector, phase, 'prompt', error)


def perform(collector, runner, step):
    """Drop-in for Collector.perform: one prompt and observation; input proof is diagnostic."""
    enable(collector, runner)
    journey, oracle = runner.journey, runner.capture.oracle
    budget = collector.budget
    deadline = min(collector.deadline, time.time() + budget['human_step_seconds'])
    phase = step['phase']
    before, folder = snapshot(collector, runner, phase + '.before', deadline)
    diagnose(collector, phase, 'readiness.screen', lambda: journey.visible(before, step['screen'], collector.binding))
    diagnose(collector, phase, 'readiness.target', lambda: oracle.target(before, step['target'], collector.binding))
    if step['kind'] in ('tap', 'toggle'):
        diagnose(collector, phase, 'readiness.counter',
                 lambda: journey.counter(before, step['screen'], collector.binding, collector.framework))
    collector.receipts.append(dict(run_id=collector.run, phase=phase + '.before', timestamp=before['timestamp'],
                                   payload=dict(target=step['target'])))
    prompt(collector, step, folder, deadline, before)
    signal = wait_for(collector, lambda: input_signal(collector, before, step), deadline)
    if signal is None:
        record(collector, phase, 'input', 'no native input observed before the step deadline')
    else:
        print(json.dumps({'human_status': {'instruction': 'Input observed. Capturing its effect; wait for the next ready step.'}}), flush=True)
        if time.time() + budget['settle_seconds'] < deadline:
            time.sleep(budget['settle_seconds'])
        else:
            record(collector, phase, 'settle', 'effect left no settled observation interval')
    after, effect = None, None
    if signal is not None:
        # One snapshot interval may exceed the step budget; the cell deadline stays binding.
        effect_deadline = min(collector.deadline, max(deadline, time.time() + budget['snapshot_seconds']))
        after, _ = snapshot(collector, runner, phase + '.effect', effect_deadline)
        effect, _ = diagnose(collector, phase, 'effect', lambda: journey.effect(
            collector.evidence, before, after, step, collector.binding, collector.framework))
    payload = dict(mode=MODE, target=step['target'], input_observed=signal is not None,
                   input_sequence=signal[0]['sequence'] if signal else None,
                   effect_state='NATIVE_EFFECT_QUALIFIED' if effect else 'NOT_QUALIFIED_DIAGNOSTIC',
                   effect=effect, diagnostics=[d for d in collector.rum_only_diagnostics if d['phase'] == phase])
    collector.receipts.append(dict(run_id=collector.run, phase=phase + '.effect',
                                   timestamp=(after or before)['timestamp'], payload=payload))
    save(folder / 'rum-only-step.json', dict(payload, phase=phase))
    return payload


def ensure_root(collector, runner, layout, prefix):
    """First-screen readiness; for SwiftUI an unobservable root is a diagnostic."""
    enable(collector, runner)
    if collector.framework != 'SwiftUI':
        # UIKit split reveals Sidebar through its own prompt; keep that flow intact.
        diagnose(collector, prefix + '.root.readiness', 'readiness.root',
                 lambda: type(collector).ensure_root(collector, layout, prefix), allow_rejected=True)
        return
    deadline = min(collector.deadline, time.time() + collector.budget['human_step_seconds'])
    phase = prefix + '.root.readiness'
    initial, _ = snapshot(collector, runner, phase, deadline)
    root = 'sidebar' if layout == 'split' else 'home'
    proof, reason = diagnose(collector, phase, 'readiness.controls',
                             lambda: runner.journey.ready_controls(initial, root, collector.binding, collector.framework))
    save(collector.output / (prefix + '.rum-only-readiness.json'), dict(mode=MODE, proof=proof, diagnostic=reason))


def run_journey(collector, runner, selected, *, duo=True):
    """Execute the unchanged step list; only evidence and operational failures end it early.

    A navigation step without observed input leaves the app on an unknown screen,
    so later input steps are skipped. Home always runs: it collects the terminal
    RUM inventory, and its failure makes the cell INCOMPLETE.
    """
    enable(collector, runner)
    layout, sdk = selected['layout'], selected['build'].split('-')[1]
    reserve = collector.budget['human_step_seconds'] + collector.budget.get('event_collection_seconds', 120)
    stopped = None
    for step in runner.journey.steps(layout, duo):
        if step['kind'] == 'home':
            collector.home()
            continue
        if stopped is None and time.time() + reserve >= collector.deadline:
            stopped = 'cell deadline reserve reached; Home collection keeps its budget'
        if stopped is not None:
            record(collector, step['phase'], 'skipped', stopped)
            continue
        if step['kind'] == 'fold':
            diagnose(collector, step['phase'], 'fold', lambda: collector.fold(step['phase'], sdk), allow_rejected=True)
            continue
        if step['phase'] in ('initial.root.tap', 'inner.root.tap'):
            ensure_root(collector, runner, layout, step['phase'].split('.')[0])
        if not perform(collector, runner, step)['input_observed'] and step['kind'] == 'navigate':
            stopped = 'navigation input was not observed at ' + step['phase']
    return collector.evidence


def windows(receipts):
    dates = sorted((r['timestamp'], r['phase'][:-len('.before')]) for r in receipts
                   if r['phase'].endswith('.before') and r['phase'] != 'background.before')
    end = next(r['timestamp'] for r in receipts if r['phase'] == 'complete')
    return [(start, dates[i + 1][0] if i + 1 < len(dates) else end, phase) for i, (start, phase) in enumerate(dates)]


def input_steps(receipts):
    steps = {}
    for receipt in receipts:
        if receipt['phase'].endswith('.before') and receipt['phase'] != 'background.before':
            steps.setdefault(receipt['phase'][:-len('.before')], dict(input_observed=False, effect_state=None, diagnostics=0))
    for receipt in receipts:
        payload = receipt.get('payload') or {}
        stem = receipt['phase'][:-len('.effect')]
        if receipt['phase'].endswith('.effect') and stem in steps:
            if payload.get('mode') == MODE:
                steps[stem] = dict(input_observed=payload['input_observed'], effect_state=payload['effect_state'],
                                   diagnostics=len(payload['diagnostics']))
            else:  # Strict collector receipt: its input and effect qualified.
                steps[stem] = dict(input_observed=True, effect_state='NATIVE_EFFECT_QUALIFIED', diagnostics=0)
    return steps


def view_phases(views, receipts):
    spans = windows(receipts)
    result = []
    for view in views:
        at = view['date'] / 1000
        phase = next((p for start, end, p in spans if start <= at < end),
                     'launch' if not spans or at < spans[0][0] else 'after-journey')
        result.append(dict(phase=phase, name=view['name'], url=view['url'], index=view['index']))
    return result


def verdict(run, rows, receipts, diagnostics=()):
    """Grade one cell from its RUM rows; input-proof diagnostics are reported, never graded."""
    base = dict(mode=MODE, run_id=run['run_id'], cell=[run['build'], run['device'], run['framework'], run['layout']],
                input_steps=input_steps(receipts), diagnostics=list(diagnostics), proof='LOCAL_MAPPER')
    if not any(r['kind'] == 'rum' for r in rows):
        return dict(base, rum_verdict='INCOMPLETE', reasons=['no local RUM rows'])
    if not any(r['phase'] == 'complete' for r in receipts):
        return dict(base, rum_verdict='INCOMPLETE', reasons=['terminal RUM inventory was not collected'])
    try:
        local = analyze.summarize(run, rows, receipts)
    except ValueError as error:  # A manual Action contaminates an automatic-only fixture.
        return dict(base, rum_verdict='FAIL', reasons=[str(error)])
    faults = sorted(k for k in FAULTS if local[k])
    if local['view_count'] == 0:
        state, reasons = 'INCOMPLETE', ['no RUM view occurrence']
    else:
        state, reasons = ('FAIL', faults) if faults else ('PASS', [])
    return dict(local, **base, rum_verdict=state, reasons=reasons, view_phases=view_phases(local['views'], receipts))


def compare(before, after):
    """Compare two graded cells within phases whose input was observed in both runs."""
    if before['rum_verdict'] != 'PASS' or after['rum_verdict'] != 'PASS':
        return {family: dict(status='REVIEW_REQUIRED', reasons=dict(before=before['reasons'], after=after['reasons']))
                for family in ('views', 'actions')}
    def observed(cell): return {p for p, s in cell['input_steps'].items() if s['input_observed']}
    excluded = sorted((set(before['input_steps']) | set(after['input_steps'])) - (observed(before) & observed(after)))
    def views(cell): return [(v['phase'], v['name'], v['url']) for v in cell['view_phases'] if v['phase'] not in excluded]
    def actions(cell):
        return [(c['phase'], [(a['type'], a['name'], a['owner_index'], a['owner_name']) for a in c['actions']])
                for c in cell['coverage'] if c['phase'] not in excluded]
    result = {}
    for family, normalize in (('views', views), ('actions', actions)):
        a, b = normalize(before), normalize(after)
        if a != b:
            result[family] = dict(status='DIFFERENCE_REQUIRES_CLASSIFICATION', before=a, after=b)
        elif family == 'actions':
            if not b:
                result[family] = dict(status='INSUFFICIENT_OBSERVED_INPUT',
                                     reasons=['no comparable input phases'])
            else:
                limited = any(not found for _, found in b)
                result[family] = dict(status='UNCHANGED_LIMITATION' if limited else 'UNCHANGED_OBSERVED_COVERAGE')
        else:
            limited = not b or any('Fallback' in (name or '') for _, name, _ in b)
            result[family] = dict(status='UNCHANGED_LIMITATION' if limited else 'UNCHANGED_OBSERVED_COVERAGE')
        result[family]['excluded_phases'] = excluded
    return result


def cell_key(row):
    return '-'.join([row['build'], row['device'], row['framework'], row['layout'], 'multi' if row['multiple_scenes'] else 'single'])


def comparison_result(accepted, matrix):
    """SDK-change and rebuild pairs from human_runtime.comparison_result, graded by RUM rows only.

    The remaining S2 SwiftUI cells are single-scene Duo cells. Device and scene
    declaration axes keep their existing strict comparison.
    """
    comparisons = []
    for row in matrix:
        key = cell_key(row)
        if key not in accepted:
            continue
        source, sdk = row['build'].split('-')
        pairs = []
        if source == 'candidate':
            pairs.append(('SDK change', dict(row, build='baseline-' + sdk)))
        if sdk == '27.1':
            pairs.append(('rebuild', dict(row, build=source + '-26.5')))
        for axis, other in pairs:
            if cell_key(other) in accepted:
                for family, value in compare(accepted[cell_key(other)], accepted[key]).items():
                    # A difference carries normalized before/after inventories; cell keys stay distinct.
                    comparisons.append(dict(axis=axis, family=family, before_cell=cell_key(other), after_cell=key, **value))
    pending = [c for c in comparisons if c['status'] in ('REVIEW_REQUIRED', 'DIFFERENCE_REQUIRES_CLASSIFICATION',
                                                       'INSUFFICIENT_OBSERVED_INPUT')]
    state = ('REVIEW_REQUIRED' if pending else 'COMPLETE_LOCAL_COMPARISON' if len(accepted) == len(matrix)
             else 'PARTIAL_LOCAL_COMPARISON')
    return dict(mode=MODE, state=state, qualified_cells=len(accepted), required_cells=len(matrix),
                comparisons=comparisons, source_differences=sum(c['axis'] == 'SDK change' for c in pending),
                boundary='Local mapper only; input-proof diagnostics annotate but never grade.', gates_closed=[])
