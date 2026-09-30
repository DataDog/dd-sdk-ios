"""The original thirteen-step prefix, with no human prompts or input retries."""
import json
import time

import human_supported_session as evidence
import prefix_input as selection

require = evidence.require
journey = selection.journey


def phases():
    return tuple(step['phase'] + suffix for step in journey.flow('split', 'initial') for suffix in ('.before', '.effect'))


def effect_ready(rows, before, step):
    selected = [r for r in rows if r['sequence'] > before['sequence']]
    require(not any(r['kind'] in ('human_failure', 'native_background') for r in selected), 'prefix observer or lifecycle failed')
    if step['kind'] == 'scroll':
        return any(r['kind'] == 'human_scroll_end' for r in selected)
    if step['target'].endswith('.next'):
        return any(r['kind'] == 'native_appear' and r['payload']['screen'] == step['after_screen'] for r in selected)
    return any(r['kind'] == 'native_input' for r in selected)


def idle(capture, name, deadline, *, after=None):
    # The frozen observer publishes input_state only for this exact phase.
    row, rows = capture.snapshot(name, 'cleanup.idle', deadline)
    journey.h.topology(row['payload']['topology'], capture.binding)
    require(capture.module.human_release.input_idle(row['payload']['input_state'], capture.binding), 'prefix native input is not idle')
    if after is not None:
        require(not any(r['kind'] in selection.INPUT_KINDS for r in rows if after['sequence'] < r['sequence']),
                'input changed before idle observation')
    return row


def run(capture, session, folder, budget, deadline):
    folder.mkdir(); completed = []; allowed = set()
    for index, step in enumerate(journey.flow('split', 'initial'), 1):
        fixed = min(deadline, time.time() + budget['step'])
        ready_idle=idle(capture,f'prefix-{index:02d}-idle-before',min(fixed,time.time()+budget['passive_snapshot']))
        before, before_rows = capture.snapshot(f'prefix-{index:02d}-before', step['phase'] + '.before', min(fixed, time.time() + budget['passive_snapshot']))
        journey.h.topology(before['payload']['topology'], capture.binding)
        journey.visible(before, step['screen'], capture.binding)
        journey.h.target(before, step['target'], capture.binding)
        require(not any(r['kind'] in selection.INPUT_KINDS for r in before_rows if r['sequence'] > ready_idle['sequence']),
                'idle readiness consumed before input boundary')
        session.input(index, step, capture, before, fixed)
        while True:
            capture.live(fixed)
            raw = (capture.documents / 'events.jsonl').read_bytes()
            require(raw.startswith(capture.prefix), 'prefix changed while waiting for effect')
            complete = raw[:raw.rfind(b'\n') + 1]
            rows = [json.loads(line) for line in complete.splitlines()]
            require(all(r['run_id'] == capture.run for r in rows)
                    and [r['sequence'] for r in rows] == list(range(1, len(rows)+1)), 'foreign or gapped prefix effect')
            if effect_ready(rows, before, step): break
            time.sleep(.1)
        # Existing capture settling is a bounded observation interval, not an
        # acceptance threshold or permission for another native command.
        require(time.time() + budget['settle'] < fixed, 'no observation interval remains')
        time.sleep(budget['settle'])
        after, rows = capture.snapshot(f'prefix-{index:02d}-effect', step['phase'] + '.effect', min(fixed, time.time() + budget['passive_snapshot']))
        effect = journey.effect(rows, before, after, step, capture.binding, 'SwiftUI')
        selection.scroll_direction(rows, before, after, step)
        allowed.update(r['sequence'] for r in journey.interval(rows, before, after) if r['kind'] in selection.INPUT_KINDS)
        idle(capture,f'prefix-{index:02d}-idle-after',min(fixed,time.time()+budget['passive_snapshot']),after=after)
        completed.append(dict(step=step, before=before['sequence'], after=after['sequence'], effect=effect))
        evidence.save(folder / f'{index:02d}-effect.json', completed[-1])
    require(len(completed) == session.input_commands == 13, 'incomplete original input sequence')
    require({r['sequence'] for r in rows if r['kind'] in selection.INPUT_KINDS} == allowed,
            'input outside qualified prefix boundaries')
    selection.final_state(after, capture.binding)
    evidence.save(folder / 'result.json', dict(state='PREFIX_NATIVE_EFFECTS_QUALIFIED', steps=completed,
        input_commands=13, original_trajectory_reproduced=False, scenario_credit=False, gates_closed=[]))
    return after
