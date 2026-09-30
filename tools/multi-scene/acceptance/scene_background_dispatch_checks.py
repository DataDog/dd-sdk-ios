"""Prepare controls for the actual isolated executor and synchronous H10 wrapper."""
import copy
import json
from pathlib import Path

from acceptance_common import require
from scene_background_fixture import DRIVER, DRIVER_SHA256, PROBE, guarded_driver, sha
from scene_background_guard_checks import between, model_source, positive

HERE = Path(__file__).resolve().parent


def controls():
    source = positive()
    base = dict(name='complete-cycle', runID=source['runID'], mode='ordinary',
                arm=source['steps'][0]['witness'],
                markers=[dict(marker=source['steps'][i]['marker'], scene=source['steps'][i]['scene'],
                              nativeSceneID=source['steps'][i]['nativeSceneID'],
                              before=source['steps'][i]['witness'], after=source['steps'][i + 2]['witness'])
                         for i in range(1, len(source['steps']), 3)],
                invocations=5, accepted=5, complete=True, reason=None, proofs=16)
    cases = [copy.deepcopy(base)]

    def add(name, mode, reason, *, calls=0, accepted=0, proofs=1, change=None):
        value = copy.deepcopy(base)
        value.update(name=name, mode=mode, invocations=calls, accepted=accepted,
                     complete=False, reason=reason, proofs=proofs)
        if change: change(value)
        cases.append(value)

    def drift(value, member):
        # The observed root really changes; no expected-value substitution.
        value['markers'][0][member]['snapshot']['scenes'][1]['rootIdentity'] = 'replaced-root'

    add('owner-drift-during-admission', 'suspended', 'owner input', proofs=2, change=lambda v: drift(v, 'before'))
    add('stop-during-admission', 'stop-wait', 'stopped or cancelled')
    add('cancel-during-admission', 'cancel-wait', 'stopped or cancelled')
    add('executor-rebound-during-admission', 'rebind-wait', 'observed native owner', proofs=2)
    add('stop-during-before-publication', 'stop-publication', 'stopped or cancelled', proofs=2)
    add('executor-rejected', 'executor-rejected', 'scene executor rejected', calls=1, proofs=4)
    add('owner-drift-inside-dispatch', 'ordinary', 'owner input', calls=1, proofs=4, change=lambda v: drift(v, 'after'))
    add('stop-inside-dispatch', 'stop-dispatch', 'stopped or cancelled', calls=1, proofs=4)
    add('arm-publication-failed', 'fail-arm-publication', 'publication failed', proofs=0)
    add('before-publication-failed', 'fail-before-publication', 'publication failed')
    add('invocation-publication-failed', 'fail-invoke-publication', 'publication failed', calls=1, proofs=3)
    add('after-publication-failed', 'fail-after-publication', 'publication failed', calls=1, proofs=3)
    add('reentrant-publication', 'reenter-publication', 'reentered', proofs=2)
    add('reentrant-dispatch', 'reenter-dispatch', 'reentered', calls=1, proofs=4)
    add('wrong-step-kind', 'wrong-step', 'wrong step or executor')
    add('wrong-handle-generation', 'wrong-generation', 'observed native owner', proofs=2)
    add('missing-arm', 'missing-arm', 'marker missing', proofs=1)
    add('repeated-arm', 'repeated-arm', 'arm reused', proofs=2)
    add('repeated-marker', 'repeated-marker', 'marker missing', calls=1, accepted=1, proofs=5)
    return cases


def prepare(destination):
    destination = Path(destination)
    require(destination.is_absolute() and destination.resolve() == destination and not destination.exists(),
            'fresh dispatch control output required')
    raw = (PROBE / DRIVER).read_bytes()
    rendered = guarded_driver(raw).decode()
    executor = between(rendered, 'internal enum ProbeStepExecutionResult:', '\n@MainActor\ninternal final class ProbeScenarioDriver')
    step = (PROBE / 'Sources/Harness/ProbeStep.swift').read_text()
    registry = (PROBE / 'Sources/Harness/ProbeSceneRegistry.swift').read_text()
    models = model_source() + '\n' + '\n'.join([
        between(step, 'enum ProbeStepKind:', '\nenum ProbeSwiftUIButtonStructuredTaskContract'),
        between(step, 'enum ProbeTransitionOutcome:', '\nenum ProbeResourceContract'),
        between(registry, 'internal struct ProbeSceneHandle:', '\ninternal struct ProbeScenePresentation:')])
    cases = controls()
    destination.mkdir()
    (destination / 'models.swift').write_text(models)
    (destination / 'executor.swift').write_text(executor)
    (destination / 'rendered-driver.swift').write_text(rendered)
    (destination / 'controls.json').write_text(json.dumps(cases, indent=2) + '\n')
    paths = [HERE / n for n in ['scene_background_dispatch.swift', 'scene_background_fixture.py',
             'scene_background_dispatch_checks.py', 'scene_background_dispatch_check_main.swift',
             'scene_background_guard.swift', 'scene_background_guard_checks.py', 'scene_background_witness.swift',
             'test_scene_background_cycle.py', 'test_focus_activation_contract.py', 'scene_background_cycle.py']]
    paths += [PROBE / 'Sources/Harness' / n for n in ['ProbeStep.swift', 'ProbeSceneRegistry.swift',
              'ProbePhysicalTopologyAdmission.swift', 'ProbeSignal.swift', 'ProbeScenarioDriver.swift']]
    receipt = dict(state='PREPARED_SYNTHETIC_EXECUTOR_CONTROLS', controls=len(cases),
                   source={str(p): sha(p) for p in paths}, original_driver_sha256=DRIVER_SHA256,
                   output={p.name: sha(p) for p in destination.iterdir()},
                   scope='Actual rendered synchronous executor; driver body, UIKit and SDK do not execute',
                   native_runs=0, gates_closed=[])
    (destination / 'preparation.json').write_text(json.dumps(receipt, indent=2) + '\n')
    return receipt
