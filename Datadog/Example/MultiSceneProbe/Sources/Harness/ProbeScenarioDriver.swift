/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal enum ProbeStepExecutionResult: Equatable {
    case accepted
    case rejected(reason: String)
}

@MainActor
internal final class ProbeSceneStepExecutor {
    private(set) var handle: ProbeSceneHandle?
    private var executeStep: ((ProbeStep) -> ProbeStepExecutionResult)?

    func configure(
        handle: ProbeSceneHandle,
        execute: @escaping (ProbeStep) -> ProbeStepExecutionResult
    ) {
        self.handle = handle
        self.executeStep = execute
    }

    func execute(_ step: ProbeStep) -> ProbeStepExecutionResult {
        guard executeStep != nil else {
            return .rejected(reason: "scene executor is not configured")
        }
        return executeStep?(step) ?? .rejected(
            reason: "scene executor disappeared"
        )
    }
}

@MainActor
internal final class ProbeScenarioDriver {
    private enum StepOutcome {
        case acknowledged(ProbeSignal)
        case failed(String)
        case inconclusive(String)
    }

    private final class Registration {
        let handle: ProbeSceneHandle
        weak var executor: ProbeSceneStepExecutor?

        init(
            handle: ProbeSceneHandle,
            executor: ProbeSceneStepExecutor
        ) {
            self.handle = handle
            self.executor = executor
        }
    }

    private enum SignalRequirement {
        case any
        case sceneReady(scene: String)
        case path(scene: String, value: String)
        case splitSelection(scene: String, value: String)
        case activation(scene: String, value: ProbeSceneActivationState)
        case transitionBegan(scene: String)
        case transitionProgress(scene: String, value: Double)
        case transitionResolutionRequested(scene: String, outcome: ProbeTransitionOutcome)
        case encoded(scene: String?, value: String)

        func matches(
            _ signal: ProbeSignal,
            recordedSignals: [ProbeSignal]
        ) -> Bool {
            switch self {
            case .any:
                return true
            case .sceneReady(let scene):
                return signal.kind == .sceneReady
                    && signal.semanticContext?.logicalSceneID == scene
                    && signal.scenePhase == ProbeSceneReadiness.ready.rawValue
            case .path(let scene, let value):
                return signal.kind == .navigationPathMutation
                    && signal.semanticContext?.logicalSceneID == scene
                    && signal.navigationPath == Self.path(for: value)
            case .splitSelection(let scene, let value):
                return signal.kind == .navigationPathMutation
                    && signal.semanticContext?.logicalSceneID == scene
                    && signal.navigationPath == [value]
            case .activation(let scene, let value):
                return signal.kind == .sceneLifecycle
                    && signal.semanticContext?.logicalSceneID == scene
                    && signal.activationState == value.rawValue
            case .transitionBegan(let scene):
                return signal.kind == .transitionBegan
                    && signal.semanticContext?.logicalSceneID == scene
                    && signal.interactive == true
            case .transitionProgress(let scene, let value):
                return signal.kind == .transitionProgress
                    && signal.semanticContext?.logicalSceneID == scene
                    && signal.transitionProgress == value
            case .transitionResolutionRequested(let scene, let outcome):
                return signal.kind == .transitionResolutionRequested
                    && signal.semanticContext?.logicalSceneID == scene
                    && signal.outcome == outcome
            case .encoded(let scene, let value):
                return Self.matches(
                    encoded: value,
                    scene: scene,
                    signal: signal,
                    recordedSignals: recordedSignals
                )
            }
        }

        private static func path(for value: String) -> [String]? {
            switch value {
            case "home":
                return ["home"]
            case "alternate", "detail-1", "detail-2":
                return ["home", value]
            default:
                return nil
            }
        }

        private static func matches(
            encoded value: String,
            scene: String?,
            signal: ProbeSignal,
            recordedSignals: [ProbeSignal]
        ) -> Bool {
            guard
                scene == nil
                    || signal.semanticContext?.logicalSceneID == scene
                    || signal.sourceContext?.logicalSceneID == scene
            else {
                return false
            }

            if value == "scene:disconnected" {
                return signal.kind == .sceneLifecycle
                    && signal.scenePhase == ProbeSceneReadiness.disconnected.rawValue
            }
            if value.hasPrefix("scene-state:") {
                let activationState = String(
                    value.dropFirst("scene-state:".count)
                )
                return signal.kind == .sceneLifecycle
                    && signal.activationState == activationState
            }
            if value == "reader:remounted" {
                return signal.kind == .rumAction
                    && signal.name == "post-retained-reader-remount"
            }
            if value.hasPrefix("transition:") {
                return signal.kind == .transitionResolved
                    && signal.outcome?.rawValue
                        == String(value.dropFirst("transition:".count))
            }
            if value.hasPrefix("marker:") {
                return signal.kind == .rumAction
                    && signal.name == String(value.dropFirst("marker:".count))
            }
            if value.hasPrefix("rum-view:") {
                let destination = String(value.dropFirst("rum-view:".count))
                let components = destination.split(
                    separator: "#",
                    maxSplits: 1
                )
                guard
                    let scene,
                    let screen = components.first.map(String.init),
                    components.count == 2,
                    let occurrence = Int(components[1]),
                    signal.kind == .rumViewSnapshot,
                    signal.rumContext?.viewActive != false,
                    let viewID = signal.rumContext?.viewID
                else {
                    return false
                }
                return ProbeSemanticTimeline(signals: recordedSignals).viewID(
                    scene: scene,
                    screen: screen,
                    occurrence: occurrence
                ) == viewID
            }

            for prefix in [
                "destination:",
                "split:",
                "uikit-split:",
                "uikit-navigation:"
            ] where value.hasPrefix(prefix) {
                let destination = String(value.dropFirst(prefix.count))
                let components = destination.split(
                    separator: "#",
                    maxSplits: 1
                )
                guard let screen = components.first.map(String.init) else {
                    return false
                }
                let requestedOccurrence = components.count == 2
                    ? Int(components[1])
                    : nil
                let isDestinationSignal =
                    signal.kind == .destinationMaterialized
                    || signal.kind == .destinationAppearanceObserved
                let observedOccurrence = signal.semanticContext?.occurrence
                    ?? recordedSignals.filter {
                        ($0.kind == .destinationMaterialized
                            || $0.kind == .destinationAppearanceObserved)
                            && $0.semanticContext?.logicalSceneID
                                == signal.semanticContext?.logicalSceneID
                            && $0.semanticContext?.screen == screen
                            && $0.sequence <= signal.sequence
                    }.count
                return isDestinationSignal
                    && signal.semanticContext?.screen == screen
                    && (
                        requestedOccurrence == nil
                            || observedOccurrence == requestedOccurrence
                    )
            }
            return false
        }
    }

    private let scenario: ProbeScenario
    private let recorder: ProbeEventRecorder
    private let sceneRegistry: ProbeSceneRegistry
    private let stepTimeoutNanoseconds: UInt64
    private let terminalTimeoutNanoseconds: UInt64
    private var registrations: [String: Registration] = [:]
    private var runTask: Task<Void, Never>?
    private(set) var terminalResult: ProbeSemanticResult?

    init(
        scenario: ProbeScenario,
        recorder: ProbeEventRecorder,
        sceneRegistry: ProbeSceneRegistry,
        stepTimeoutNanoseconds: UInt64 = 10_000_000_000,
        terminalTimeoutNanoseconds: UInt64 = 10_000_000_000
    ) {
        self.scenario = scenario
        self.recorder = recorder
        self.sceneRegistry = sceneRegistry
        self.stepTimeoutNanoseconds = stepTimeoutNanoseconds
        self.terminalTimeoutNanoseconds = terminalTimeoutNanoseconds
    }

    func register(
        handle: ProbeSceneHandle,
        executor: ProbeSceneStepExecutor
    ) {
        registrations[handle.logicalSceneID] = Registration(
            handle: handle,
            executor: executor
        )
    }

    func unregister(handle: ProbeSceneHandle) {
        guard registrations[handle.logicalSceneID]?.handle == handle else {
            return
        }
        registrations.removeValue(forKey: handle.logicalSceneID)
    }

    func startIfNeeded() {
        guard runTask == nil, terminalResult == nil else {
            return
        }
        runTask = Task { @MainActor [weak self] in
            await self?.run()
        }
    }

    func waitUntilFinished() async -> ProbeSemanticResult? {
        await runTask?.value
        return terminalResult
    }

    private func run() async {
        var observationCursor: UInt64 = 0

        for (index, step) in scenario.steps.enumerated() {
            guard !Task.isCancelled else {
                return
            }

            let started = recorder.record(
                ProbeSignal(
                    kind: .stepStarted,
                    semanticContext: semanticContext(for: step.scene),
                    stepIndex: index,
                    stepKind: step.kind,
                    name: step.value ?? step.signal
                )
            )

            let outcome = await execute(
                step,
                after: observationCursor,
                commandSequence: started.sequence
            )
            guard case .acknowledged(let observation) = outcome else {
                if case .inconclusive(let reason) = outcome {
                    finish(
                        state: .inconclusive,
                        matchedExpectationCount: 0,
                        issue: ProbeSemanticIssue(
                            expectationIndex: nil,
                            expectation: nil,
                            signalSequence: started.sequence,
                            reason: "step \(index) \(step.kind.rawValue) was inconclusive: \(reason)"
                        )
                    )
                    return
                }
                let reason: String
                if case .failed(let failureReason) = outcome {
                    reason = failureReason
                } else {
                    reason = "unknown step failure"
                }
                finish(
                    state: .fail,
                    matchedExpectationCount: 0,
                    issue: ProbeSemanticIssue(
                        expectationIndex: nil,
                        expectation: nil,
                        signalSequence: started.sequence,
                        reason: "step \(index) \(step.kind.rawValue) failed: \(reason)"
                    )
                )
                return
            }

            observationCursor = max(
                observationCursor,
                observation.sequence
            )
            recorder.record(
                ProbeSignal(
                    kind: .stepAcknowledged,
                    semanticContext: semanticContext(for: step.scene),
                    stepIndex: index,
                    stepKind: step.kind,
                    acknowledgedSignalSequence: observation.sequence,
                    name: step.value ?? step.signal
                )
            )
        }

        finish(await waitForTerminalSemanticResult())
    }

    private func execute(
        _ step: ProbeStep,
        after observationCursor: UInt64,
        commandSequence: UInt64
    ) async -> StepOutcome {
        switch step.kind {
        case .openWindow:
            guard
                let sourceScene = step.scene,
                let targetScene = step.value
            else {
                return .failed("source or target scene is missing")
            }
            guard sourceScene != targetScene else {
                return .failed("source and target scene must differ")
            }
            guard sceneRegistry.handle(logicalSceneID: targetScene) == nil else {
                return .failed("scene \(targetScene) is already live")
            }
            if case .rejected(let reason) = executeOnExactScene(
                step,
                scene: sourceScene
            ) {
                return .failed(reason)
            }
            guard let signal = await wait(
                for: .sceneReady(scene: targetScene),
                after: commandSequence,
                timeoutNanoseconds: stepTimeoutNanoseconds
            ) else {
                return .failed("timed out waiting for scene-ready in \(targetScene)")
            }
            return .acknowledged(signal)

        case .closeWindow:
            guard let scene = step.scene else {
                return .failed("scene is missing")
            }
            if case .rejected(let reason) = executeOnExactScene(
                step,
                scene: scene
            ) {
                return .failed(reason)
            }
            guard let signal = await wait(
                for: .encoded(scene: scene, value: "scene:disconnected"),
                after: commandSequence,
                timeoutNanoseconds: stepTimeoutNanoseconds
            ) else {
                return .failed("timed out waiting for disconnect in \(scene)")
            }
            return .acknowledged(signal)

        case .activateWindow:
            guard let scene = step.scene else {
                return .failed("scene is missing")
            }
            if case .rejected(let reason) = executeOnExactScene(
                step,
                scene: scene
            ) {
                return .failed(reason)
            }
            guard let signal = await wait(
                for: .activation(scene: scene, value: .foregroundActive),
                after: commandSequence,
                timeoutNanoseconds: stepTimeoutNanoseconds
            ) else {
                return .failed("timed out waiting for foreground activation in \(scene)")
            }
            return .acknowledged(signal)

        case .waitForSceneReady:
            guard let scene = step.scene else {
                return .failed("scene is missing")
            }
            guard let signal = await wait(
                for: .sceneReady(scene: scene),
                after: observationCursor,
                timeoutNanoseconds: stepTimeoutNanoseconds
            ) else {
                return .failed("timed out waiting for scene-ready in \(scene)")
            }
            return .acknowledged(signal)

        case .waitForSignal:
            guard let signal = step.signal else {
                return .failed("signal requirement is missing")
            }

            if signal.hasPrefix("scene-state:") {
                guard
                    let scene = step.scene,
                    let activationState = ProbeSceneActivationState(
                        rawValue: String(signal.dropFirst("scene-state:".count))
                    )
                else {
                    return .failed("scene state requirement is invalid")
                }
                if let currentStateSignal = latestLifecycleSignal(
                    scene: scene,
                    activationState: activationState
                ) {
                    return .acknowledged(currentStateSignal)
                }
                guard let observation = await wait(
                    for: .activation(scene: scene, value: activationState),
                    after: observationCursor,
                    timeoutNanoseconds: stepTimeoutNanoseconds
                ) else {
                    return .inconclusive(
                        "timed out waiting for \(signal) in \(scene)"
                    )
                }
                return .acknowledged(observation)
            }

            guard let observation = await wait(
                for: .encoded(scene: step.scene, value: signal),
                after: observationCursor,
                timeoutNanoseconds: stepTimeoutNanoseconds
            ) else {
                return .failed("timed out waiting for \(signal)")
            }
            return .acknowledged(observation)

        case .setSwiftUIPath, .replaceSwiftUIDestination:
            guard
                let scene = step.scene,
                let value = step.value
            else {
                return .failed("scene or path is missing")
            }
            if case .rejected(let reason) = executeOnExactScene(
                step,
                scene: scene
            ) {
                return .failed(reason)
            }
            guard let signal = await wait(
                for: .path(scene: scene, value: value),
                after: commandSequence,
                timeoutNanoseconds: stepTimeoutNanoseconds
            ) else {
                return .failed("timed out waiting for path \(value) in \(scene)")
            }
            return .acknowledged(signal)

        case .pushAndRevertSwiftUIPath:
            guard
                let scene = step.scene,
                step.value != nil
            else {
                return .failed("scene or path is missing")
            }
            if case .rejected(let reason) = executeOnExactScene(
                step,
                scene: scene
            ) {
                return .failed(reason)
            }
            guard let signal = await wait(
                for: .path(scene: scene, value: "home"),
                after: commandSequence,
                timeoutNanoseconds: stepTimeoutNanoseconds
            ) else {
                return .failed(
                    "timed out waiting for reverted Home path in \(scene)"
                )
            }
            return .acknowledged(signal)

        case .setSplitSelection:
            guard
                let scene = step.scene,
                let value = step.value
            else {
                return .failed("scene or split selection is missing")
            }
            if case .rejected(let reason) = executeOnExactScene(
                step,
                scene: scene
            ) {
                return .failed(reason)
            }
            guard let signal = await wait(
                for: .splitSelection(scene: scene, value: value),
                after: commandSequence,
                timeoutNanoseconds: stepTimeoutNanoseconds
            ) else {
                return .failed(
                    "timed out waiting for split selection \(value) in \(scene)"
                )
            }
            return .acknowledged(signal)

        case .beginUIKitInteractiveTransition:
            guard let scene = step.scene else {
                return .failed("scene is missing")
            }
            if case .rejected(let reason) = executeOnExactScene(
                step,
                scene: scene
            ) {
                return .failed(reason)
            }
            guard let signal = await wait(
                for: .transitionBegan(scene: scene),
                after: commandSequence,
                timeoutNanoseconds: stepTimeoutNanoseconds
            ) else {
                return .failed("timed out waiting for UIKit transition begin in \(scene)")
            }
            return .acknowledged(signal)

        case .updateUIKitInteractiveTransition:
            guard
                let scene = step.scene,
                let percentage = step.percentage
            else {
                return .failed("scene or transition percentage is missing")
            }
            if case .rejected(let reason) = executeOnExactScene(
                step,
                scene: scene
            ) {
                return .failed(reason)
            }
            guard let signal = await wait(
                for: .transitionProgress(scene: scene, value: percentage),
                after: commandSequence,
                timeoutNanoseconds: stepTimeoutNanoseconds
            ) else {
                return .failed(
                    "timed out waiting for UIKit transition progress \(percentage) in \(scene)"
                )
            }
            return .acknowledged(signal)

        case .resolveUIKitInteractiveTransition:
            guard
                let scene = step.scene,
                let outcome = step.outcome
            else {
                return .failed("scene or transition outcome is missing")
            }
            if case .rejected(let reason) = executeOnExactScene(
                step,
                scene: scene
            ) {
                return .failed(reason)
            }
            guard let signal = await wait(
                for: .transitionResolutionRequested(
                    scene: scene,
                    outcome: outcome
                ),
                after: commandSequence,
                timeoutNanoseconds: stepTimeoutNanoseconds
            ) else {
                return .failed(
                    "timed out waiting for UIKit transition resolution request in \(scene)"
                )
            }
            return .acknowledged(signal)

        case .emitMarker:
            guard
                let scene = step.scene,
                let marker = step.value
            else {
                return .failed("scene or marker is missing")
            }
            if case .rejected(let reason) = executeOnExactScene(
                step,
                scene: scene
            ) {
                return .failed(reason)
            }
            guard let signal = await wait(
                for: .encoded(
                    scene: scene,
                    value: "marker:\(marker)"
                ),
                after: commandSequence,
                timeoutNanoseconds: stepTimeoutNanoseconds
            ) else {
                return .failed("timed out waiting for marker \(marker) in \(scene)")
            }
            return .acknowledged(signal)

        default:
            return .failed("unsupported driver step \(step.kind.rawValue)")
        }
    }

    private func executeOnExactScene(
        _ step: ProbeStep,
        scene: String
    ) -> ProbeStepExecutionResult {
        guard
            let registration = registrations[scene],
            let executor = registration.executor,
            executor.handle == registration.handle,
            sceneRegistry.handle(logicalSceneID: scene) == registration.handle
        else {
            return .rejected(reason: "no live executor for \(scene)")
        }
        return executor.execute(step)
    }

    private func semanticContext(
        for scene: String?
    ) -> ProbeSemanticContext? {
        guard let scene else {
            return nil
        }
        let snapshot = sceneRegistry.snapshot(
            logicalSceneID: scene
        )
        return ProbeSemanticContext(
            logicalSceneID: scene,
            nativeSceneID: snapshot?.nativeSceneID,
            screen: snapshot?.currentRoute.last
        )
    }

    private func waitForTerminalSemanticResult() async -> ProbeSemanticResult {
        var result = ProbeSemanticOracle.evaluate(
            scenario: scenario,
            signals: recorder.snapshot()
        )
        if result.state != .fail {
            return result
        }

        var cursor = recorder.snapshot().last?.sequence ?? 0
        let deadline = Date().addingTimeInterval(
            Double(terminalTimeoutNanoseconds) / 1_000_000_000
        )

        while Date() < deadline {
            let remaining = max(0, deadline.timeIntervalSinceNow)
            guard
                let signal = await wait(
                    for: .any,
                    after: cursor,
                    timeoutNanoseconds: UInt64(
                        remaining * 1_000_000_000
                    )
                )
            else {
                break
            }
            cursor = signal.sequence
            result = ProbeSemanticOracle.evaluate(
                scenario: scenario,
                signals: recorder.snapshot()
            )
            if result.state != .fail {
                return result
            }
        }
        return result
    }

    private func wait(
        for requirement: SignalRequirement,
        after sequence: UInt64,
        timeoutNanoseconds: UInt64
    ) async -> ProbeSignal? {
        let stream = recorder.signalStream()
        return await withTaskGroup(of: ProbeSignal?.self) { group in
            group.addTask {
                for await signal in stream {
                    guard !Task.isCancelled else {
                        return nil
                    }
                    if
                        signal.sequence > sequence,
                        requirement.matches(
                            signal,
                            recordedSignals: self.recorder.snapshot()
                        ) {
                        return signal
                    }
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return nil
            }

            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private func latestLifecycleSignal(
        scene: String,
        activationState: ProbeSceneActivationState
    ) -> ProbeSignal? {
        let latest = recorder.snapshot().last {
            $0.kind == .sceneLifecycle
                && $0.semanticContext?.logicalSceneID == scene
        }
        return latest?.activationState == activationState.rawValue
            ? latest
            : nil
    }

    private func finish(_ result: ProbeSemanticResult) {
        guard terminalResult == nil else {
            return
        }
        terminalResult = result
        _ = recorder.recordTerminalResult(result)
    }

    private func finish(
        state: ProbeSemanticResultState,
        matchedExpectationCount: Int,
        issue: ProbeSemanticIssue
    ) {
        finish(
            ProbeSemanticResult(
                scenarioID: scenario.identifier,
                state: state,
                matchedExpectationCount: matchedExpectationCount,
                issues: [issue]
            )
        )
    }
}
