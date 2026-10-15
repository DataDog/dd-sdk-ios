"""Seal the H04 scenario prefix without discarding later captured bytes.

This module has no device or cleanup authority. The caller must still qualify
installed code, the physical process, original transfer and the final idle state.
"""
from pathlib import Path
import time

from acceptance_common import require
import focus_activation_contract as contract
import operation_setup as setup
import operation_transport as t

MAX_BYTES = 16 * 1024 * 1024
SOURCE = 'Library/Application Support/ProbeAcceptance/probe.jsonl'


class Pending(ValueError):
    """The same native recorder has not published a complete capture yet."""


def validate(raw, run_id, *, previous=b''):
    require(isinstance(raw, bytes) and len(raw) <= MAX_BYTES, 'oversized or absent focus recorder')
    require(isinstance(previous, bytes) and raw.startswith(previous), 'focus recorder replaced or truncated')
    end = raw.rfind(b'\n') + 1
    if not end: raise Pending('focus recorder has no complete line')
    lines = raw[:end].splitlines(keepends=True)
    rows = [t.load(line, maximum=t.MAX_CONTEXT_BYTES) for line in lines]
    require(all(isinstance(row, dict) and row.get('type') in {'manifest', 'signal', 'semantic-result'} for row in rows),
            'unknown focus recorder row')
    require(rows[0]['type'] == 'manifest' and sum(r['type'] == 'manifest' for r in rows) == 1,
            'missing, repeated or late focus manifest')
    manifest = rows[0]['manifest']
    require(type(manifest.get('schemaVersion')) is int and manifest['schemaVersion'] == 3
            and manifest.get('runID') == run_id and manifest.get('scenario') == contract.contract(),
            'foreign focus recorder manifest')
    terminals = [i for i, r in enumerate(rows) if r['type'] == 'semantic-result']
    require(len(terminals) <= 1, 'multiple focus terminals')
    signals = [r['signal'] for r in rows if r['type'] == 'signal']
    require(all(type(s.get('schemaVersion')) is int and s['schemaVersion'] == 5
                and s.get('runID') == run_id and s.get('scenarioID') == contract.SCENARIO
                and type(s.get('sequence')) is int and s['sequence'] == i + 1
                for i, s in enumerate(signals)), 'foreign or incomplete focus signal stream')
    require(not any(s.get('result') in {'FAIL','INCONCLUSIVE','SKIPPED'} or s.get('kind') == 'rum-error'
                    for s in signals), 'failed assertion or error in captured focus stream')
    if not terminals: raise Pending('focus semantic terminal has not been persisted')
    terminal = terminals[0]
    local = contract.validate_local(rows[:terminal + 1], run_id, profile=contract.PROFILE)
    views = {v['view_id']: v for v in local['views']}
    tail = rows[terminal + 1:]
    # Ordinary View document updates and known-scene lifecycle callbacks may
    # follow completion. Never let them provide missing scenario evidence.
    for row in tail:
        require(row['type'] == 'signal', 'non-signal follows focus terminal')
        signal = row['signal']; kind = signal.get('kind')
        require(kind in {'rum-view-snapshot', 'scene-lifecycle'}, 'critical or unknown signal follows focus terminal')
        context = signal.get('semanticContext') or {}
        if context:
            scene = context.get('logicalSceneID')
            require(scene in local['native_scenes'] and context.get('nativeSceneID') in
                    [None, local['native_scenes'][scene]], 'foreign post-terminal scene')
        if kind == 'scene-lifecycle':
            require(context.get('nativeSceneID') == local['native_scenes'].get(context.get('logicalSceneID'))
                    and context.get('logicalSceneID') in local['native_scenes']
                    and signal.get('scenePhase') != 'disconnected', 'unbound or disconnected post-terminal scene')
        else:
            value = signal.get('rumContext', {}); owner = views.get(value.get('viewID'))
            require(signal.get('evidenceSource') == 'rum-mapper' and owner is not None
                    and value.get('sessionID') == owner['session_id'] and value.get('viewName') == owner['name'],
                    'new or changed post-terminal View owner')
    # A partial tail cannot conceal an additional guard, work item or error.
    # Poll the same append-only file; do not launch or repeat the scenario.
    if end != len(raw): raise Pending('focus recorder ends in an incomplete row')
    cutoff = sum(map(len, lines[:terminal + 1]))
    return dict(state='SEALED_FOCUS_PREFIX', run_id=run_id, scenario=contract.SCENARIO, profile=contract.PROFILE,
                raw_sha256=t.sha(raw), bytes=len(raw), cutoff_bytes=cutoff, cutoff_sha256=t.sha(raw[:cutoff]),
                postterminal_signals=len(tail), local=local, native_process_qualified=False,
                backend='PENDING', cleanup='PENDING', overall='UNQUALIFIED', teardown_authorized=False)


def seal(raw_path, folder, run_id):
    """Persist exact received bytes before validation; a fresh folder is mandatory."""
    raw_path, folder = Path(raw_path), Path(folder)
    require(not folder.exists() and not any(p.is_symlink() for p in [folder, *folder.parents]),
            'focus capture output consumed or redirected')
    raw = setup.read(raw_path, maximum=MAX_BYTES)
    folder.mkdir()
    t.save(folder/'raw.jsonl', raw)
    t.save(folder/'definition.json', t.encode(dict(run_id=run_id, source=str(raw_path), raw_sha256=t.sha(raw),
        recorded_at=time.time(), native_admission=False, teardown_authorized=False)))
    try:
        result = validate(raw, run_id)
        t.save(folder/'result.json', t.encode(result))
        return result
    except Exception as error:
        t.save(folder/'failure.json', t.encode(dict(state='PENDING' if isinstance(error, Pending) else 'INVALID',
            error_type=type(error).__name__, reason=str(error), raw_sha256=t.sha(raw), teardown_authorized=False)))
        raise


def verified(folder):
    folder = Path(folder)
    definition = t.load(setup.read(folder/'definition.json'))
    raw = setup.read(folder/'raw.jsonl', maximum=MAX_BYTES)
    require(t.sha(raw) == definition['raw_sha256'], 'sealed focus bytes changed')
    result = validate(raw, definition['run_id'])
    require(t.load(setup.read(folder/'result.json', maximum=t.MAX_CONTEXT_BYTES)) == result,
            'sealed focus result was substituted')
    return raw, result
