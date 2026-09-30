"""Compose H10 in an isolated copy; no SDK, H04/H06 or project edits."""
import hashlib
import json
from pathlib import Path

from acceptance_common import require
import focus_activation_fixture as focus
import scene_background_channel as channel
import scene_background_fixture as base

HERE = Path(__file__).resolve().parent
SCENARIO = 'windows.isolated-background-foreground'
PROFILE = 'physical-isolated-background-foreground'
RECORDER = 'Sources/Harness/ProbeEventRecorder.swift'
MARKERS = [('A.before-background', 'scene-A'), ('B.before-background', 'scene-B'),
           ('B.while-A-background', 'scene-B'), ('A.after-foreground', 'scene-A'),
           ('B.after-A-foreground', 'scene-B')]


def scenario_source():
    steps = ['ProbeStep(.waitForSceneReady, scene: "scene-A")',
             'ProbeStep(.openWindow, scene: "scene-A", value: "scene-B")']
    steps += [f'ProbeStep(.emitSceneContextMarker, scene: "{scene}", value: "{name}")' for name, scene in MARKERS]
    completion = [f'ProbeExpectation(.{kind}, scene: "{scene}", screen: "home", name: "{name}")'
                  for name, scene in MARKERS for kind in ['action', 'resource']]
    return ('    private static let windowsIsolatedBackground = ProbeScenario(\n'
            f'        identifier: "{SCENARIO}",\n        trackingMode: .manual,\n        layout: .stack,\n'
            '        initialWindows: ["scene-A", "scene-B"],\n        requiredCapabilities: [.multipleScenes],\n'
            '        steps: [\n            '+',\n            '.join(steps)+'\n        ],\n'
            '        completionConditions: [\n            '+',\n            '.join(completion)+'\n        ],\n'
            '        expectedSemanticTimeline: []\n    )\n\n')


def startup_source():
    source = focus.startup_source()
    for old, new in [('ProbeFocusStartupFreshness', 'ProbeSceneBackgroundStartupFreshness'),
                     ('DD_PROBE_FOCUS_STARTUP_NONCE', 'DD_PROBE_BACKGROUND_STARTUP_NONCE'),
                     ('DD_PROBE_FOCUS_ACTIVATION_PROFILE', 'DD_PROBE_BACKGROUND_PROFILE'),
                     (focus.SCENARIO, SCENARIO), (focus.PROFILE, PROFILE)]:
        require(old in source, 'missing background startup relocation')
        source = source.replace(old, new)
    return source


def idle_source():
    source = (HERE/'focus_activation_session.swift').read_text()
    require(hashlib.sha256(source.encode()).hexdigest() ==
            'c274d27e11dc8b0d4e630763a56c6a631c27291f366f8d88af105159a763fd2a', 'unreviewed idle source')
    source = source[source.index('    /// Background peers'):]
    return ('@MainActor\nprivate enum ProbeSceneBackgroundIdle {\n'+source).replace(
        'ProbeFocusControl', 'ProbeSceneBackgroundControl')


def app_source(raw):
    require(hashlib.sha256(raw).hexdigest() == focus.ORIGINAL[focus.APP], 'unreviewed H10 app input')
    source = raw.decode()
    source = base.replace_once(source, '''    @MainActor static let physicalOperationInput: ProbePhysicalOperationInput? =
        physicalOperationCaptureRequested && [ProbePhysicalOperationProfile.scenarioID,
            ProbePhysicalOperationSetupProfile.scenarioID].contains(scenario?.identifier ?? "")
        ? .init(registry: sceneRegistry, recordsContinuity: scenario?.identifier == ProbePhysicalOperationSetupProfile.scenarioID) : nil''',
'''    @MainActor static let physicalOperationInput: ProbePhysicalOperationInput? = {
        if scenario?.identifier == ProbeSceneBackgroundControl.scenarioID {
            guard ProcessInfo.processInfo.environment["DD_PROBE_BACKGROUND_PROFILE"] == ProbeSceneBackgroundControl.profile,
                  !physicalOperationCaptureRequested else { return nil }
            return .init(registry: sceneRegistry, recordsContinuity: true)
        }
        return physicalOperationCaptureRequested && [ProbePhysicalOperationProfile.scenarioID,
            ProbePhysicalOperationSetupProfile.scenarioID].contains(scenario?.identifier ?? "")
            ? .init(registry: sceneRegistry, recordsContinuity: scenario?.identifier == ProbePhysicalOperationSetupProfile.scenarioID) : nil
    }()''')
    source = base.replace_once(source, '            try ProbeOperationStartupFreshness.prepareIfRequested(\n',
'''            try ProbeSceneBackgroundStartupFreshness.prepareIfRequested(
                resolution: ProbeRuntime.resolution, environment: ProcessInfo.processInfo.environment,
                container: URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
                processID: ProcessInfo.processInfo.processIdentifier, bundleIdentifier: Bundle.main.bundleIdentifier
            )
            try ProbeOperationStartupFreshness.prepareIfRequested(
''')
    oracle = base.sha(HERE/'scene_background_cycle.py')
    source = base.replace_once(source, '    @MainActor static let scenarioDriver: ProbeScenarioDriver? = {\n',
'''    @MainActor private static let backgroundSession: ProbeSceneBackgroundSession? = {
        guard scenario?.identifier == ProbeSceneBackgroundControl.scenarioID, let input = physicalOperationInput else { return nil }
        return ProbeSceneBackgroundSession.make(input: input, recorder: eventRecorder,
            oracleSourceSHA256: "'''+oracle+'''")
    }()

    @MainActor static let scenarioDriver: ProbeScenarioDriver? = {
''')
    source = base.replace_once(source, '        } else if physicalOperationCaptureRequested {\n',
'''        } else if scenario.identifier == ProbeSceneBackgroundControl.scenarioID {
            stepAdmission = { index, step, after in
                guard let session = backgroundSession else { return "background session is not configured" }
                return await session.admission(index: index, step: step, after: after)
            }
        } else if physicalOperationCaptureRequested {
''')
    source = base.replace_once(source, '            stepAdmission: stepAdmission\n',
'''            terminalTimeoutNanoseconds: scenario.identifier == ProbeSceneBackgroundControl.scenarioID ? 0 : 10_000_000_000,
            backgroundDispatch: backgroundSession?.dispatch,
            backgroundSeal: { backgroundSession?.isSealed == true },
            stepAdmission: stepAdmission
''')
    source += '\n'+channel.source()+'\n'+idle_source()+'\n'+startup_source()
    source += '\n'+'\n'.join((HERE/n).read_text() for n in
                            ['scene_background_phase.swift','scene_background_capture.swift','scene_background_session.swift'])
    return source.encode()


def driver_source(source):
    source = base.replace_once(source, '    private let backgroundDispatch: ProbeSceneBackgroundDispatch?\n',
        '    private let backgroundDispatch: ProbeSceneBackgroundDispatch?\n    private let backgroundSeal: (() -> Bool)?\n')
    source = base.replace_once(source, '        backgroundDispatch: ProbeSceneBackgroundDispatch? = nil,\n',
        '        backgroundDispatch: ProbeSceneBackgroundDispatch? = nil,\n        backgroundSeal: (() -> Bool)? = nil,\n')
    source = base.replace_once(source, '        self.backgroundDispatch = backgroundDispatch\n',
        '        self.backgroundDispatch = backgroundDispatch\n        self.backgroundSeal = backgroundSeal\n')
    anchor = '            if scenario.identifier == ProbePhysicalOperationSetupProfile.scenarioID {\n                guard let signal = recorder.snapshot().first(where: {\n'
    source = base.replace_once(source, anchor, '''            if scenario.identifier == ProbeSceneBackgroundDispatch.scenarioID {
                guard let signal = recorder.snapshot().first(where: {
                    $0.sequence > commandSequence && $0.kind == .assertion && $0.result == .pass
                        && $0.semanticContext?.logicalSceneID == scene && $0.stepKind == step.kind
                        && $0.name == "h10.invoke." + marker
                }) else { return .inconclusive("background marker invocation receipt missing") }
                return .acknowledged(signal)
            }
'''+anchor)
    source = base.replace_once(source, '        terminalResult = result\n        _ = recorder.recordTerminalResult(result)\n',
'''        let selected: ProbeSemanticResult
        if scenario.identifier == ProbeSceneBackgroundDispatch.scenarioID, result.state == .pass,
           backgroundSeal?() != true {
            selected = ProbeSemanticResult(scenarioID: scenario.identifier, state: .inconclusive, matchedExpectationCount: 0,
                issues: [ProbeSemanticIssue(expectationIndex: nil, expectation: nil, signalSequence: nil,
                                           reason: "background terminal lacks its accepted collection seal")])
        } else { selected = result }
        terminalResult = selected
        _ = recorder.recordTerminalResult(selected)
''')
    return source.encode()


RECORDER_EXTENSION = '''
extension ProbeEventRecorder {
    func h10Snapshot() -> (signals: [ProbeSignal], terminal: ProbeSemanticResult?) {
        lock.lock()
        defer { lock.unlock() }
        return (signals, terminalResult)
    }

    func h10RecordChecked(_ draft: ProbeSignal, validate: ([ProbeSignal]) throws -> Void) throws -> ProbeSignal {
        lock.lock()
        defer { lock.unlock() }
        try validate(signals)
        return record(draft)
    }
}
'''


def prepare(destination):
    destination = Path(destination)
    catalog = (base.PROBE/focus.CATALOG).read_bytes()
    require(hashlib.sha256(catalog).hexdigest() == focus.ORIGINAL[focus.CATALOG], 'unreviewed H10 catalog')
    source = catalog.decode()
    source = base.replace_once(source, '        "windows.activation-sequence",\n',
                               '        "windows.activation-sequence",\n        "'+SCENARIO+'",\n')
    source = base.replace_once(source, '        windowsActivationSequence,\n',
                               '        windowsActivationSequence,\n        windowsIsolatedBackground,\n')
    source = base.replace_once(source, '    private static let windowsActivationSequence = ProbeScenario(',
                               scenario_source()+'    private static let windowsActivationSequence = ProbeScenario(')
    recorder = (base.PROBE/RECORDER).read_bytes()
    require(hashlib.sha256(recorder).hexdigest() == 'e8deb4823b0041acc2c8b9dd298558adc1272a17c318767d55de23cad713e270', 'unreviewed H10 recorder')
    changes = {focus.APP: app_source((base.PROBE/focus.APP).read_bytes()), focus.CATALOG: source.encode(),
               RECORDER: recorder+RECORDER_EXTENSION.encode()}
    receipt = base.prepare(destination, with_dispatch=True)
    changes[base.DRIVER] = driver_source((destination/base.DRIVER).read_text())
    for path, raw in changes.items(): (destination/path).write_bytes(raw)
    rendered = {str(p.relative_to(destination)): base.sha(p) for p in sorted((destination/'Sources').rglob('*')) if p.is_file()}
    require(rendered.keys() == receipt['original'].keys() and
            {p for p in rendered if rendered[p] != receipt['original'][p]} == set(changes).union([base.INPUT]),
            'H10 membership or unrelated source changed')
    require(all(base.sha(base.PROBE/p) == sha for p,sha in receipt['original'].items()), 'original source changed')
    receipt.update(state='COMPOSED_SESSION_SOURCE_ONLY', rendered=rendered, scenario_runnable=False,
                   native_admitted=False, scope='App/session source only; actual display, host runner and cleanup admission unqualified')
    for name in ['scene_background_session_fixture.py','scene_background_session.swift','scene_background_capture.swift',
                 'scene_background_phase.swift','scene_background_channel.py','scene_background_cycle.py',
                 'focus_activation_fixture.py','focus_activation_session.swift','focus_activation_channel.swift']:
        receipt['helpers'][str(HERE/name)] = base.sha(HERE/name)
    (destination/'source.json').write_text(json.dumps(receipt,indent=2)+'\n')
    return receipt
