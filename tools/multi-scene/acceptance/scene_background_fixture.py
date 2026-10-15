"""Copy H10 witnesses and optional guarded dispatch into isolated existing members.

No original source, catalog, SDK or project membership is changed. Neither mode
admits a scenario: app transport, phase barriers, display and cleanup are separate.
"""
import hashlib
import json
from pathlib import Path
import shutil

from acceptance_common import require

HERE = Path(__file__).resolve().parent
PROBE = HERE.parents[2] / 'Datadog/Example/MultiSceneProbe'
INPUT = 'Sources/Harness/ProbePhysicalTopologyAdmission.swift'
INPUT_SHA256 = '7b4ff1c0a0619c7481ca60c2b67c1021e8aca90ab7dbccd3b87d4f3ca2ebcabd'
WITNESS = HERE / 'scene_background_witness.swift'
DRIVER = 'Sources/Harness/ProbeScenarioDriver.swift'
DRIVER_SHA256 = '3a7dcaeb39a9cf5273e55529fd8047e328da26eed6bb243f96eb9376a8810f6b'


def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def replace_once(source, old, new):
    require(source.count(old) == 1, 'H10 dispatch source anchor changed or repeated')
    return source.replace(old, new, 1)


def guarded_driver(raw):
    require(hashlib.sha256(raw).hexdigest() == DRIVER_SHA256, 'unreviewed H10 driver source')
    source = raw.decode()
    source = replace_once(source, '''    func execute(_ step: ProbeStep) -> ProbeStepExecutionResult {
        guard executeStep != nil else {
            return .rejected(reason: "scene executor is not configured")
        }
        return executeStep?(step) ?? .rejected(
            reason: "scene executor disappeared"
        )
    }''', '''    func execute(_ step: ProbeStep, background: ProbeSceneBackgroundDispatch? = nil) -> ProbeStepExecutionResult {
        guard let executeStep else { return .rejected(reason: "scene executor is not configured") }
        if let background {
            guard let handle else { return .rejected(reason: "scene executor has no handle") }
            return background.execute(step, handle: handle) { executeStep(step) }
        }
        return executeStep(step)
    }''')
    source = replace_once(source, '    private let scenario: ProbeScenario\n',
                          '    private let scenario: ProbeScenario\n    private let backgroundDispatch: ProbeSceneBackgroundDispatch?\n')
    source = replace_once(source, '        stepAdmission: ((Int, ProbeStep, Bool) async -> String?)? = nil\n',
                          '        backgroundDispatch: ProbeSceneBackgroundDispatch? = nil,\n'
                          '        stepAdmission: ((Int, ProbeStep, Bool) async -> String?)? = nil\n')
    source = replace_once(source, '        self.stepAdmission = stepAdmission\n',
                          '        self.stepAdmission = stepAdmission\n        self.backgroundDispatch = backgroundDispatch\n')
    source = replace_once(source, '        return executor.execute(step)\n', '''        if scenario.identifier == ProbeSceneBackgroundDispatch.scenarioID,
           [.emitMarker, .emitSceneContextMarker, .emitExplicitTargetAction].contains(step.kind) {
            guard let backgroundDispatch else { return .rejected(reason: "H10 synchronous dispatch is not configured") }
            return executor.execute(step, background: backgroundDispatch)
        }
        return executor.execute(step)
''')
    return source.encode()


def prepare(destination, *, with_dispatch=False):
    destination = Path(destination)
    require(destination.is_absolute() and destination.resolve() == destination and not destination.exists(),
            'fresh canonical H10 fixture output required')
    require(sha(PROBE / INPUT) == INPUT_SHA256, 'unreviewed native observer source')
    files = sorted((PROBE / 'Sources').rglob('*'))
    require(not any(p.is_symlink() for p in files), 'redirected fixture input')
    original = {str(p.relative_to(PROBE)): sha(p) for p in files if p.is_file()}
    helpers = [WITNESS]
    if with_dispatch:
        helpers += [HERE / 'scene_background_guard.swift', HERE / 'scene_background_dispatch.swift']
    helper_shas = {str(p): sha(p) for p in helpers}
    changes = {INPUT: (PROBE / INPUT).read_bytes() + b'\n' + WITNESS.read_bytes()}
    if with_dispatch:
        changes[DRIVER] = guarded_driver((PROBE / DRIVER).read_bytes()) + b'\n' + b'\n'.join(p.read_bytes() for p in helpers[1:])
    destination.mkdir()
    shutil.copytree(PROBE / 'Sources', destination / 'Sources')
    for member, rendered in changes.items(): (destination / member).write_bytes(rendered)
    result = {str(p.relative_to(destination)): sha(p) for p in sorted((destination / 'Sources').rglob('*'))
              if p.is_file()}
    require(original.keys() == result.keys()
            and {p for p in original if original[p] != result[p]} == set(changes),
            'unrelated fixture source or membership changed')
    require(all(sha(PROBE / p) == digest for p, digest in original.items())
            and all(sha(p) == digest for p, digest in helper_shas.items()),
            'original source or helper changed during copy')
    receipt = dict(state='UNWIRED_GUARDED_EXECUTOR_SOURCE_ONLY' if with_dispatch else 'DORMANT_NATIVE_WITNESS_SOURCE_ONLY',
                   original=original, rendered=result,
                   helpers={str(Path(__file__)): sha(__file__), **helper_shas},
                   compiler_qualified=False, scenario_runnable=False, native_runs=0, gates_closed=[])
    (destination / 'source.json').write_text(json.dumps(receipt, indent=2) + '\n')
    return receipt
