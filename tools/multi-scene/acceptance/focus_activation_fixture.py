"""Render a separate H04 fixture; original SDK, catalog and H06 inputs stay intact."""
import hashlib
import json
from pathlib import Path
import shutil
from acceptance_common import require

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
PROBE = REPO/'Datadog/Example/MultiSceneProbe'
CATALOG = 'Sources/Harness/ProbeScenarioCatalog.swift'
APP = 'Sources/RUMNativeMultiSceneProbeApp.swift'
ORIGINAL = {CATALOG: 'ed8f88eac90a01de6be54e3c92a3ea52f576fa40119e296fb303e66bae338696',
            APP: '74a948580533bdd15a1e4d20c16c5d6c680101a5d4d8f32887a83777b2a4c412'}
SCENARIO = 'windows.focus-activation-only'
PROFILE = 'physical-focus-activation-only'


def contract():
    return json.loads((HERE/'focus-activation-scenario-contract.json').read_text())


def swift_case(value):
    parts = value.split('-')
    return parts[0]+''.join(part.title() for part in parts[1:])


def scenario_source():
    value = contract()
    require(value['identifier'] == SCENARIO and len(value['steps']) == 14
            and len(value['expectedSemanticTimeline']) == 13 and len(value['completionConditions']) == 2,
            'focus scenario scope changed')
    def item(row, name):
        fields = ['.'+swift_case(row['kind'])]
        fields += [key+': '+json.dumps(item) for key, item in row.items() if key != 'kind']
        return '            '+name+'('+', '.join(fields)+')'
    sections = []
    for name, constructor in [('steps','ProbeStep'),('completionConditions','ProbeExpectation'),
                               ('expectedSemanticTimeline','ProbeExpectation')]:
        sections.append('        '+name+': [\n'+',\n'.join(item(row,constructor) for row in value[name])+'\n        ]')
    return ('    private static let windowsFocusActivationOnly = ProbeScenario(\n'
            '        identifier: "'+SCENARIO+'",\n        trackingMode: .manual,\n        layout: .stack,\n'
            '        initialWindows: ["scene-A", "scene-B"],\n        requiredCapabilities: [.multipleScenes],\n'
            +',\n'.join(sections)+'\n    )\n\n')


def replace_once(source, old, new):
    require(source.count(old) == 1, 'focus fixture anchor changed or repeated')
    return source.replace(old,new,1)


def render(path, raw):
    require(path in ORIGINAL and hashlib.sha256(raw).hexdigest() == ORIGINAL[path], 'unreviewed focus fixture input')
    text = raw.decode()
    if path == CATALOG:
        text = replace_once(text,'        "windows.activation-sequence",\n',
                            '        "windows.activation-sequence",\n        "'+SCENARIO+'",\n')
        text = replace_once(text,'        windowsActivationSequence,\n',
                            '        windowsActivationSequence,\n        windowsFocusActivationOnly,\n')
        anchor = '    private static let windowsActivationSequence = ProbeScenario('
        return replace_once(text,anchor,scenario_source()+anchor).encode()
    old = '''    @MainActor static let physicalOperationInput: ProbePhysicalOperationInput? =
        physicalOperationCaptureRequested && [ProbePhysicalOperationProfile.scenarioID,
            ProbePhysicalOperationSetupProfile.scenarioID].contains(scenario?.identifier ?? "")
        ? .init(registry: sceneRegistry, recordsContinuity: scenario?.identifier == ProbePhysicalOperationSetupProfile.scenarioID) : nil'''
    new = '''    @MainActor static let physicalOperationInput: ProbePhysicalOperationInput? = {
        if scenario?.identifier == ProbeFocusActivationAdmission.scenarioID {
            guard ProcessInfo.processInfo.environment["DD_PROBE_FOCUS_ACTIVATION_PROFILE"] == ProbeFocusActivationAdmission.profile,
                  !physicalOperationCaptureRequested else { return nil }
            return .init(registry: sceneRegistry, recordsContinuity: true)
        }
        return physicalOperationCaptureRequested && [ProbePhysicalOperationProfile.scenarioID,
            ProbePhysicalOperationSetupProfile.scenarioID].contains(scenario?.identifier ?? "")
            ? .init(registry: sceneRegistry, recordsContinuity: scenario?.identifier == ProbePhysicalOperationSetupProfile.scenarioID) : nil
    }()'''
    text = replace_once(text,old,new)
    anchor = '        } else if physicalOperationCaptureRequested {\n'
    hook = '''        } else if scenario.identifier == ProbeFocusActivationAdmission.scenarioID {
            let focus = physicalOperationInput.map { ProbeFocusActivationAdmission(input: $0, recorder: eventRecorder) }
            let session = physicalOperationInput.flatMap { ProbeFocusSession.make(input: $0) }
            stepAdmission = { index, step, after in
                guard let focus, let session else { return "focus activation profile is not armed" }
                if let reason = await session.admission(index: index, after: after) { return reason }
                return focus.check(index: index, step: step, after: after)
            }
'''
    text = replace_once(text,anchor,hook+anchor)
    return (text+'\n'+'\n'.join((HERE/name).read_text() for name in
            ['focus_activation_guard.swift','focus_activation_channel.swift','focus_activation_session.swift'])).encode()


def prepare(source, destination):
    """Copy declared fixture inputs only; this does not build or admit execution."""
    source, destination = Path(source), Path(destination)
    require(source.resolve() == PROBE.resolve() and not destination.exists(), 'fresh isolated focus output required')
    changes = {name: render(name,(source/name).read_bytes()) for name in ORIGINAL}
    before = {str(p.relative_to(source)): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in sorted((source/'Sources').rglob('*')) if p.is_file()}
    require(not any(p.is_symlink() for p in (source/'Sources').rglob('*')), 'redirected fixture source')
    destination.mkdir(parents=True)
    shutil.copytree(source/'Sources',destination/'Sources')
    for name, raw in changes.items(): (destination/name).write_bytes(raw)
    after = {str(p.relative_to(destination)): hashlib.sha256(p.read_bytes()).hexdigest()
             for p in sorted((destination/'Sources').rglob('*')) if p.is_file()}
    require(before.keys() == after.keys() and {k for k in before if before[k] != after[k]} == set(ORIGINAL),
            'focus copy changed unrelated fixture inputs')
    require(all(hashlib.sha256((source/k).read_bytes()).hexdigest() == v for k,v in before.items()), 'original fixture changed')
    receipt = dict(state='PREPARED_SOURCE_ONLY',scenario=SCENARIO,profile=PROFILE,original=before,rendered=after,
                   helpers={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in
                            [Path(__file__),HERE/'focus_activation_guard.swift',HERE/'focus_activation_channel.swift',
                             HERE/'focus_activation_session.swift',HERE/'focus-activation-scenario-contract.json']},
                   native_launches=0,builds=0,gates_closed=[])
    (destination/'source.json').write_text(json.dumps(receipt,indent=2)+'\n')
    return receipt
