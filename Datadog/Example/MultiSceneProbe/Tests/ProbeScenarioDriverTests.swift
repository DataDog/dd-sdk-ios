/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import XCTest

@MainActor
final class ProbeScenarioDriverTests: XCTestCase {
    func testDrivesHomeDetailHomeFromObservedSignalsAndEmitsOnePass() async throws {
        let lines = DriverLockedLines()
        let terminalLines = DriverLockedLines()
        let recorder = ProbeEventRecorder(
            runID: "driver-pass",
            scenarioID: "swiftui.stack.return",
            sink: { lines.append($0) },
            terminalSink: { terminalLines.append($0) },
            clock: { 42 }
        )
        let registry = ProbeSceneRegistry()
        let window = UIWindow()
        let handle = try registeredHandle(
            registry.register(
                logicalSceneID: "scene-A",
                nativeSceneID: "native-A",
                window: window,
                currentRoute: ["home"]
            )
        )
        XCTAssertNotNil(registry.markReady(handle))

        recorder.record(
            viewSignal(
                id: "home-1",
                screen: "home",
                active: true,
                documentVersion: 1
            )
        )
        recorder.record(
            ProbeSignal(
                kind: .sceneReady,
                semanticContext: semanticContext(screen: "home"),
                scenePhase: ProbeSceneReadiness.ready.rawValue
            )
        )

        var requestedPaths: [String] = []
        let executor = ProbeSceneStepExecutor()
        executor.configure(handle: handle) { step in
            switch (step.kind, step.value) {
            case (.setSwiftUIPath, "detail-1"):
                requestedPaths.append("detail-1")
                recorder.record(
                    self.pathSignal(
                        previous: ["home"],
                        current: ["home", "detail-1"]
                    )
                )
                recorder.record(
                    self.viewSignal(
                        id: "home-1",
                        screen: "home",
                        active: false,
                        documentVersion: 2
                    )
                )
                recorder.record(
                    self.viewSignal(
                        id: "detail-1",
                        screen: "detail-1",
                        active: true,
                        documentVersion: 1
                    )
                )
                recorder.record(
                    ProbeSignal(
                        kind: .destinationMaterialized,
                        semanticContext: self.semanticContext(screen: "detail-1")
                    )
                )
            case (.setSwiftUIPath, "home"):
                requestedPaths.append("home")
                recorder.record(
                    self.pathSignal(
                        previous: ["home", "detail-1"],
                        current: ["home"]
                    )
                )
                recorder.record(
                    self.viewSignal(
                        id: "detail-1",
                        screen: "detail-1",
                        active: false,
                        documentVersion: 2
                    )
                )
                recorder.record(
                    self.viewSignal(
                        id: "home-2",
                        screen: "home",
                        active: true,
                        documentVersion: 1
                    )
                )
            case (.emitMarker, "navigation-appearance-2"):
                recorder.record(
                    ProbeSignal(
                        kind: .rumAction,
                        evidenceSource: .rumMapper,
                        semanticContext: self.semanticContext(
                            screen: "home",
                            occurrence: 2
                        ),
                        rumContext: ProbeRUMContext(
                            sessionID: "session",
                            viewID: "home-2"
                        ),
                        name: "navigation-appearance-2"
                    )
                )
            default:
                return .rejected(reason: "unsupported step")
            }
            return .accepted
        }

        let driver = ProbeScenarioDriver(
            scenario: try scenario(named: "swiftui.stack.return"),
            recorder: recorder,
            sceneRegistry: registry,
            stepTimeoutNanoseconds: 100_000_000,
            terminalTimeoutNanoseconds: 100_000_000
        )
        driver.register(handle: handle, executor: executor)
        driver.startIfNeeded()
        driver.startIfNeeded()

        let completedResult = await driver.waitUntilFinished()
        let result = try XCTUnwrap(completedResult)

        XCTAssertEqual(result.state, .pass, result.issues.map(\.reason).joined(separator: "\n"))
        XCTAssertEqual(requestedPaths, ["detail-1", "home"])
        XCTAssertEqual(
            recorder.snapshot().filter { $0.kind == .stepAcknowledged }.count,
            6
        )
        XCTAssertEqual(
            recorder.snapshot()
                .compactMap(\.acknowledgedSignalSequence)
                .count,
            6
        )
        XCTAssertEqual(
            lines.snapshot().filter { $0.contains(#""type":"semantic-result""#) }.count,
            1
        )
        XCTAssertEqual(terminalLines.snapshot(), lines.snapshot().filter {
            $0.contains(#""type":"semantic-result""#)
        })
        XCTAssertFalse(recorder.recordTerminalResult(result))
    }

    func testDrivesSwiftUIPresentationSeparatelyFromNavigationPath() async throws {
        let recorder = ProbeEventRecorder(
            runID: "driver-presentation",
            scenarioID: "driver-presentation",
            sink: { _ in }
        )
        let registry = ProbeSceneRegistry()
        let window = UIWindow()
        let handle = try registeredHandle(
            registry.register(
                logicalSceneID: "scene-A",
                nativeSceneID: "native-A",
                window: window,
                currentRoute: ["home"]
            )
        )
        XCTAssertNotNil(registry.markReady(handle))

        var requestedPresentations: [String] = []
        let executor = ProbeSceneStepExecutor()
        executor.configure(handle: handle) { step in
            guard
                step.kind == .setSwiftUIPresentation,
                let value = step.value
            else {
                return .rejected(reason: "unsupported step")
            }
            requestedPresentations.append(value)
            recorder.record(
                self.pathSignal(
                    previous: value == "sheet" ? ["home"] : ["home", "sheet"],
                    current: value == "sheet" ? ["home", "sheet"] : ["home"]
                )
            )
            return .accepted
        }

        let driver = ProbeScenarioDriver(
            scenario: ProbeScenario(
                identifier: "driver-presentation",
                trackingMode: .automatic,
                layout: .stack,
                steps: [
                    ProbeStep(
                        .setSwiftUIPresentation,
                        scene: "scene-A",
                        value: "sheet"
                    ),
                    ProbeStep(
                        .setSwiftUIPresentation,
                        scene: "scene-A",
                        value: "home"
                    )
                ],
                completionConditions: [],
                expectedSemanticTimeline: []
            ),
            recorder: recorder,
            sceneRegistry: registry,
            stepTimeoutNanoseconds: 100_000_000,
            terminalTimeoutNanoseconds: 100_000_000
        )
        driver.register(handle: handle, executor: executor)
        driver.startIfNeeded()

        let completedResult = await driver.waitUntilFinished()
        let result = try XCTUnwrap(completedResult)

        XCTAssertEqual(result.state, .pass)
        XCTAssertEqual(requestedPresentations, ["sheet", "home"])
        XCTAssertEqual(
            recorder.snapshot().filter { $0.kind == .stepAcknowledged }.count,
            2
        )
    }

    func testDrivesAbortedPathWithoutSpeculativeView() async throws {
        let recorder = ProbeEventRecorder(
            runID: "driver-abort",
            scenarioID: "swiftui.stack.abort",
            sink: { _ in }
        )
        let registry = ProbeSceneRegistry()
        let window = UIWindow()
        let handle = try registeredHandle(
            registry.register(
                logicalSceneID: "scene-A",
                nativeSceneID: "native-A",
                window: window,
                currentRoute: ["home"]
            )
        )
        XCTAssertNotNil(registry.markReady(handle))
        recorder.record(
            viewSignal(
                id: "home-1",
                screen: "home",
                active: true,
                documentVersion: 1
            )
        )
        recorder.record(
            ProbeSignal(
                kind: .sceneReady,
                semanticContext: semanticContext(screen: "home"),
                scenePhase: ProbeSceneReadiness.ready.rawValue
            )
        )

        let executor = ProbeSceneStepExecutor()
        executor.configure(handle: handle) { step in
            guard step.kind == .pushAndRevertSwiftUIPath else {
                return .rejected(reason: "unsupported step")
            }
            recorder.record(
                ProbeSignal(
                    kind: .intervalBegan,
                    semanticContext: self.semanticContext(screen: "home"),
                    interval: "aborted-navigation"
                )
            )
            recorder.record(
                self.pathSignal(
                    previous: ["home"],
                    current: ["home", "detail-1"]
                )
            )
            recorder.record(
                self.pathSignal(
                    previous: ["home", "detail-1"],
                    current: ["home"]
                )
            )
            recorder.record(
                ProbeSignal(
                    kind: .intervalEnded,
                    semanticContext: self.semanticContext(screen: "home"),
                    interval: "aborted-navigation"
                )
            )
            recorder.record(
                ProbeSignal(
                    kind: .rumAction,
                    evidenceSource: .rumMapper,
                    semanticContext: self.semanticContext(
                        screen: "home",
                        occurrence: 1
                    ),
                    rumContext: ProbeRUMContext(
                        sessionID: "session",
                        viewID: "home-1"
                    ),
                    name: "post-aborted-navigation"
                )
            )
            recorder.record(
                self.workSignal(
                    kind: .rumResource,
                    id: "post-abort-resource",
                    name: "post-aborted-navigation",
                    viewID: "home-1",
                    screen: "home",
                    occurrence: 1
                )
            )
            return .accepted
        }

        let driver = ProbeScenarioDriver(
            scenario: try scenario(named: "swiftui.stack.abort"),
            recorder: recorder,
            sceneRegistry: registry,
            stepTimeoutNanoseconds: 100_000_000,
            terminalTimeoutNanoseconds: 100_000_000
        )
        driver.register(handle: handle, executor: executor)
        driver.startIfNeeded()

        let completedResult = await driver.waitUntilFinished()
        let result = try XCTUnwrap(completedResult)

        XCTAssertEqual(
            result.state,
            .pass,
            result.issues.map(\.reason).joined(separator: "\n")
        )
        XCTAssertEqual(result.matchedExpectationCount, 5)
        XCTAssertEqual(
            recorder.snapshot().filter { $0.kind == .stepAcknowledged }.count,
            3
        )
    }

    func testDrivesSameTypeReplacementFromObservedSignals() async throws {
        let recorder = ProbeEventRecorder(
            runID: "driver-replacement",
            scenarioID: "swiftui.stack.same-type-replacement",
            sink: { _ in }
        )
        let registry = ProbeSceneRegistry()
        let window = UIWindow()
        let handle = try registeredHandle(
            registry.register(
                logicalSceneID: "scene-A",
                nativeSceneID: "native-A",
                window: window,
                currentRoute: ["home"]
            )
        )
        XCTAssertNotNil(registry.markReady(handle))
        recorder.record(
            viewSignal(
                id: "home-1",
                screen: "home",
                active: true,
                documentVersion: 1
            )
        )
        recorder.record(
            ProbeSignal(
                kind: .sceneReady,
                semanticContext: semanticContext(screen: "home"),
                scenePhase: ProbeSceneReadiness.ready.rawValue
            )
        )

        let executor = ProbeSceneStepExecutor()
        executor.configure(handle: handle) { step in
            switch (step.kind, step.value) {
            case (.setSwiftUIPath, "detail-1"):
                recorder.record(
                    self.pathSignal(
                        previous: ["home"],
                        current: ["home", "detail-1"]
                    )
                )
                recorder.record(
                    self.viewSignal(
                        id: "home-1",
                        screen: "home",
                        active: false,
                        documentVersion: 2
                    )
                )
                recorder.record(
                    self.viewSignal(
                        id: "detail-1",
                        screen: "detail-1",
                        active: true,
                        documentVersion: 1
                    )
                )
                recorder.record(
                    ProbeSignal(
                        kind: .destinationMaterialized,
                        semanticContext: self.semanticContext(screen: "detail-1")
                    )
                )
            case (.replaceSwiftUIDestination, "detail-2"):
                recorder.record(
                    self.pathSignal(
                        previous: ["home", "detail-1"],
                        current: ["home", "detail-2"]
                    )
                )
                recorder.record(
                    self.viewSignal(
                        id: "detail-1",
                        screen: "detail-1",
                        active: false,
                        documentVersion: 2
                    )
                )
                recorder.record(
                    self.viewSignal(
                        id: "detail-2",
                        screen: "detail-2",
                        active: true,
                        documentVersion: 1
                    )
                )
                recorder.record(
                    ProbeSignal(
                        kind: .destinationMaterialized,
                        semanticContext: self.semanticContext(screen: "detail-2")
                    )
                )
                recorder.record(
                    self.workSignal(
                        kind: .rumAction,
                        id: "detail-2-action",
                        name: "binding-update-2",
                        viewID: "detail-2",
                        screen: "detail-2",
                        occurrence: 1
                    )
                )
                recorder.record(
                    self.workSignal(
                        kind: .rumResource,
                        id: "detail-2-resource",
                        name: "binding-update-2",
                        viewID: "detail-2",
                        screen: "detail-2",
                        occurrence: 1
                    )
                )
            default:
                return .rejected(reason: "unsupported step")
            }
            return .accepted
        }

        let driver = ProbeScenarioDriver(
            scenario: try scenario(named: "swiftui.stack.same-type-replacement"),
            recorder: recorder,
            sceneRegistry: registry,
            stepTimeoutNanoseconds: 100_000_000,
            terminalTimeoutNanoseconds: 100_000_000
        )
        driver.register(handle: handle, executor: executor)
        driver.startIfNeeded()

        let completedResult = await driver.waitUntilFinished()
        let result = try XCTUnwrap(completedResult)

        XCTAssertEqual(
            result.state,
            .pass,
            result.issues.map(\.reason).joined(separator: "\n")
        )
        XCTAssertEqual(result.matchedExpectationCount, 6)
        XCTAssertEqual(
            recorder.snapshot().filter { $0.kind == .stepAcknowledged }.count,
            5
        )
    }

    func testDrivesSplitSelectionFromObservedMaterialization() async throws {
        let recorder = ProbeEventRecorder(
            runID: "driver-split",
            scenarioID: "swiftui.split.same-type-selection",
            sink: { _ in }
        )
        let registry = ProbeSceneRegistry()
        let window = UIWindow()
        let handle = try registeredHandle(
            registry.register(
                logicalSceneID: "scene-A",
                nativeSceneID: "native-A",
                window: window,
                currentRoute: ["detail-1"]
            )
        )
        XCTAssertNotNil(registry.markReady(handle))
        recorder.record(
            viewSignal(
                id: "split-detail-1",
                screen: "detail-1",
                active: true,
                documentVersion: 1
            )
        )
        recorder.record(
            ProbeSignal(
                kind: .sceneReady,
                semanticContext: semanticContext(screen: "detail-1"),
                scenePhase: ProbeSceneReadiness.ready.rawValue
            )
        )
        recordSplitMaterialization(
            recorder: recorder,
            screen: "detail-1",
            viewID: "split-detail-1",
            occurrence: 1
        )

        var requestedSelections: [String] = []
        let executor = ProbeSceneStepExecutor()
        executor.configure(handle: handle) { step in
            switch (step.kind, step.value) {
            case (.setSplitSelection, "detail-2"):
                requestedSelections.append("detail-2")
                recorder.record(
                    self.pathSignal(
                        previous: ["detail-1"],
                        current: ["detail-2"]
                    )
                )
                recorder.record(
                    self.viewSignal(
                        id: "split-detail-1",
                        screen: "detail-1",
                        active: false,
                        documentVersion: 2
                    )
                )
                recorder.record(
                    self.viewSignal(
                        id: "split-detail-2",
                        screen: "detail-2",
                        active: true,
                        documentVersion: 1
                    )
                )
                self.recordSplitMaterialization(
                    recorder: recorder,
                    screen: "detail-2",
                    viewID: "split-detail-2",
                    occurrence: 1
                )
            case (.setSplitSelection, "placeholder"):
                requestedSelections.append("placeholder")
                recorder.record(
                    self.pathSignal(
                        previous: ["detail-2"],
                        current: ["placeholder"]
                    )
                )
                recorder.record(
                    self.viewSignal(
                        id: "split-detail-2",
                        screen: "detail-2",
                        active: false,
                        documentVersion: 2
                    )
                )
                recorder.record(
                    self.viewSignal(
                        id: "split-placeholder",
                        screen: "placeholder",
                        active: true,
                        documentVersion: 1
                    )
                )
                self.recordSplitMaterialization(
                    recorder: recorder,
                    screen: "placeholder",
                    viewID: "split-placeholder",
                    occurrence: 1
                )
            default:
                return .rejected(reason: "unsupported step")
            }
            return .accepted
        }

        let driver = ProbeScenarioDriver(
            scenario: try scenario(named: "swiftui.split.same-type-selection"),
            recorder: recorder,
            sceneRegistry: registry,
            stepTimeoutNanoseconds: 100_000_000,
            terminalTimeoutNanoseconds: 100_000_000
        )
        driver.register(handle: handle, executor: executor)
        driver.startIfNeeded()

        let completedResult = await driver.waitUntilFinished()
        let result = try XCTUnwrap(completedResult)

        XCTAssertEqual(
            result.state,
            .pass,
            result.issues.map(\.reason).joined(separator: "\n")
        )
        XCTAssertEqual(result.matchedExpectationCount, 10)
        XCTAssertEqual(requestedSelections, ["detail-2", "placeholder"])
        XCTAssertEqual(
            recorder.snapshot().filter { $0.kind == .stepAcknowledged }.count,
            6
        )
    }

    func testDrivesUIKitInteractiveCancellationFromObservedSignals() async throws {
        let result = try await driveUIKitInteractiveTransition(outcome: .cancel)

        XCTAssertEqual(
            result.semanticResult.state,
            .pass,
            result.semanticResult.issues.map(\.reason).joined(separator: "\n")
        )
        XCTAssertEqual(result.semanticResult.matchedExpectationCount, 11)
        XCTAssertEqual(
            result.recorder.snapshot().filter { $0.kind == .stepAcknowledged }.count,
            6
        )
    }

    func testDrivesUIKitInteractiveCompletionFromObservedSignals() async throws {
        let result = try await driveUIKitInteractiveTransition(outcome: .finish)

        XCTAssertEqual(
            result.semanticResult.state,
            .pass,
            result.semanticResult.issues.map(\.reason).joined(separator: "\n")
        )
        XCTAssertEqual(result.semanticResult.matchedExpectationCount, 13)
        XCTAssertEqual(
            result.recorder.snapshot().filter { $0.kind == .stepAcknowledged }.count,
            6
        )
    }

    func testOpensActivatesAndClosesExactPeerBeforeContinuingOnSourceScene() async throws {
        let recorder = ProbeEventRecorder(
            runID: "driver-scene-lifecycle",
            scenarioID: "driver-scene-lifecycle",
            sink: { _ in }
        )
        let registry = ProbeSceneRegistry()
        let windowA = UIWindow()
        let windowB = UIWindow()
        let handleA = try registeredHandle(
            registry.register(
                logicalSceneID: "scene-A",
                nativeSceneID: "native-A",
                window: windowA,
                currentRoute: ["home"]
            )
        )
        XCTAssertNotNil(registry.markReady(handleA))
        recorder.record(
            ProbeSignal(
                kind: .sceneReady,
                semanticContext: ProbeSemanticContext(
                    logicalSceneID: "scene-A",
                    nativeSceneID: "native-A",
                    screen: "home"
                ),
                scenePhase: ProbeSceneReadiness.ready.rawValue
            )
        )

        let scenario = ProbeScenario(
            identifier: "driver-scene-lifecycle",
            trackingMode: .manual,
            layout: .stack,
            initialWindows: ["scene-A", "scene-B"],
            steps: [
                ProbeStep(.waitForSceneReady, scene: "scene-A"),
                ProbeStep(.openWindow, scene: "scene-A", value: "scene-B"),
                ProbeStep(.activateWindow, scene: "scene-A"),
                ProbeStep(.activateWindow, scene: "scene-B"),
                ProbeStep(
                    .emitMarker,
                    scene: "scene-B",
                    value: "before-close"
                ),
                ProbeStep(.closeWindow, scene: "scene-B"),
                ProbeStep(
                    .emitMarker,
                    scene: "scene-A",
                    value: "after-peer-close"
                )
            ],
            completionConditions: [],
            expectedSemanticTimeline: []
        )
        let driver = ProbeScenarioDriver(
            scenario: scenario,
            recorder: recorder,
            sceneRegistry: registry,
            stepTimeoutNanoseconds: 100_000_000,
            terminalTimeoutNanoseconds: 100_000_000
        )
        let executorA = ProbeSceneStepExecutor()
        let executorB = ProbeSceneStepExecutor()
        var commandsA: [ProbeStepKind] = []
        var commandsB: [ProbeStepKind] = []
        var registeredHandleB: ProbeSceneHandle?

        executorA.configure(handle: handleA) { step in
            commandsA.append(step.kind)
            switch step.kind {
            case .openWindow:
                guard
                    step.scene == "scene-A",
                    step.value == "scene-B"
                else {
                    return .rejected(reason: "wrong scene open command")
                }
                let registration = registry.register(
                    logicalSceneID: "scene-B",
                    nativeSceneID: "native-B",
                    window: windowB,
                    currentRoute: ["home"]
                )
                guard case .registered(let handleB) = registration else {
                    return .rejected(reason: "failed to register scene-B")
                }
                registeredHandleB = handleB
                XCTAssertNotNil(registry.markReady(handleB))
                executorB.configure(handle: handleB) { step in
                    commandsB.append(step.kind)
                    switch step.kind {
                    case .activateWindow:
                        recorder.record(
                            ProbeSignal(
                                kind: .sceneLifecycle,
                                semanticContext: ProbeSemanticContext(
                                    logicalSceneID: "scene-B",
                                    nativeSceneID: "native-B",
                                    screen: "home"
                                ),
                                activationState: ProbeSceneActivationState.foregroundActive.rawValue
                            )
                        )
                    case .emitMarker:
                        recorder.record(
                            ProbeSignal(
                                kind: .rumAction,
                                evidenceSource: .rumMapper,
                                semanticContext: ProbeSemanticContext(
                                    logicalSceneID: "scene-B",
                                    nativeSceneID: "native-B",
                                    screen: "home"
                                ),
                                name: "before-close"
                            )
                        )
                    case .closeWindow:
                        guard let snapshot = registry.disconnect(handleB) else {
                            return .rejected(reason: "failed to disconnect scene-B")
                        }
                        recorder.record(
                            ProbeSignal(
                                kind: .sceneLifecycle,
                                semanticContext: ProbeSemanticContext(
                                    logicalSceneID: "scene-B",
                                    nativeSceneID: "native-B"
                                ),
                                scenePhase: snapshot.readiness.rawValue,
                                sceneDisconnectGeneration: snapshot.disconnectGeneration
                            )
                        )
                        driver.unregister(handle: handleB)
                    default:
                        return .rejected(reason: "unexpected scene-B command")
                    }
                    return .accepted
                }
                driver.register(handle: handleB, executor: executorB)
                recorder.record(
                    ProbeSignal(
                        kind: .sceneReady,
                        semanticContext: ProbeSemanticContext(
                            logicalSceneID: "scene-B",
                            nativeSceneID: "native-B",
                            screen: "home"
                        ),
                        scenePhase: ProbeSceneReadiness.ready.rawValue
                    )
                )
            case .activateWindow:
                recorder.record(
                    ProbeSignal(
                        kind: .sceneLifecycle,
                        semanticContext: ProbeSemanticContext(
                            logicalSceneID: "scene-A",
                            nativeSceneID: "native-A",
                            screen: "home"
                        ),
                        activationState: ProbeSceneActivationState.foregroundActive.rawValue
                    )
                )
            case .emitMarker:
                recorder.record(
                    ProbeSignal(
                        kind: .rumAction,
                        evidenceSource: .rumMapper,
                        semanticContext: ProbeSemanticContext(
                            logicalSceneID: "scene-A",
                            nativeSceneID: "native-A",
                            screen: "home"
                        ),
                        name: "after-peer-close"
                    )
                )
            default:
                return .rejected(reason: "unexpected scene-A command")
            }
            return .accepted
        }

        driver.register(handle: handleA, executor: executorA)
        driver.startIfNeeded()

        let completedResult = await driver.waitUntilFinished()
        let result = try XCTUnwrap(completedResult)

        XCTAssertEqual(
            result.state,
            .pass,
            result.issues.map(\.reason).joined(separator: "\n")
        )
        XCTAssertEqual(commandsA, [.openWindow, .activateWindow, .emitMarker])
        XCTAssertEqual(commandsB, [.activateWindow, .emitMarker, .closeWindow])
        XCTAssertEqual(registry.handle(logicalSceneID: "scene-A"), handleA)
        XCTAssertNil(registry.handle(logicalSceneID: "scene-B"))
        XCTAssertNotNil(registeredHandleB)
        XCTAssertEqual(
            recorder.snapshot().filter { $0.kind == .stepAcknowledged }.count,
            7
        )
    }

    func testMissingCommandAcknowledgementFailsInsteadOfSleepingThrough() async throws {
        let lines = DriverLockedLines()
        let recorder = ProbeEventRecorder(
            runID: "driver-timeout",
            scenarioID: "driver-timeout",
            sink: { lines.append($0) }
        )
        let registry = ProbeSceneRegistry()
        let window = UIWindow()
        let handle = try registeredHandle(
            registry.register(
                logicalSceneID: "scene-A",
                nativeSceneID: "native-A",
                window: window,
                currentRoute: ["home"]
            )
        )
        XCTAssertNotNil(registry.markReady(handle))
        recorder.record(
            ProbeSignal(
                kind: .sceneReady,
                semanticContext: semanticContext(screen: "home"),
                scenePhase: ProbeSceneReadiness.ready.rawValue
            )
        )

        let executor = ProbeSceneStepExecutor()
        executor.configure(handle: handle) { _ in .accepted }
        let driver = ProbeScenarioDriver(
            scenario: ProbeScenario(
                identifier: "driver-timeout",
                trackingMode: .manual,
                layout: .stack,
                steps: [
                    ProbeStep(.waitForSceneReady, scene: "scene-A"),
                    ProbeStep(
                        .setSwiftUIPath,
                        scene: "scene-A",
                        value: "detail-1"
                    )
                ],
                completionConditions: [],
                expectedSemanticTimeline: []
            ),
            recorder: recorder,
            sceneRegistry: registry,
            stepTimeoutNanoseconds: 5_000_000,
            terminalTimeoutNanoseconds: 5_000_000
        )
        driver.register(handle: handle, executor: executor)
        driver.startIfNeeded()

        let completedResult = await driver.waitUntilFinished()
        let result = try XCTUnwrap(completedResult)

        XCTAssertEqual(result.state, .fail)
        XCTAssertTrue(
            result.issues[0].reason.contains("step 1"),
            result.issues[0].reason
        )
        XCTAssertEqual(
            recorder.snapshot().filter { $0.kind == .stepAcknowledged }.count,
            1
        )
        XCTAssertEqual(
            lines.snapshot().filter { $0.contains(#""type":"semantic-result""#) }.count,
            1
        )
    }

    func testObservedCurrentSceneStateAcknowledgesRegardlessOfSignalOrder() async throws {
        let recorder = ProbeEventRecorder(
            runID: "driver-scene-state",
            scenarioID: "driver-scene-state",
            sink: { _ in }
        )
        let registry = ProbeSceneRegistry()
        recorder.record(
            ProbeSignal(
                kind: .sceneReady,
                semanticContext: semanticContext(screen: "home"),
                scenePhase: ProbeSceneReadiness.ready.rawValue
            )
        )
        recorder.record(
            ProbeSignal(
                kind: .sceneLifecycle,
                semanticContext: semanticContext(screen: "home"),
                activationState: ProbeSceneActivationState.background.rawValue
            )
        )
        recorder.record(
            ProbeSignal(
                kind: .sceneLifecycle,
                semanticContext: ProbeSemanticContext(
                    logicalSceneID: "scene-B",
                    nativeSceneID: "native-B",
                    screen: "home"
                ),
                activationState: ProbeSceneActivationState.foregroundActive.rawValue
            )
        )
        let driver = ProbeScenarioDriver(
            scenario: ProbeScenario(
                identifier: "driver-scene-state",
                trackingMode: .manual,
                layout: .stack,
                initialWindows: ["scene-A", "scene-B"],
                steps: [
                    ProbeStep(.waitForSceneReady, scene: "scene-A"),
                    ProbeStep(
                        .waitForSignal,
                        scene: "scene-B",
                        signal: "scene-state:foreground-active"
                    ),
                    ProbeStep(
                        .waitForSignal,
                        scene: "scene-A",
                        signal: "scene-state:background"
                    )
                ],
                completionConditions: [],
                expectedSemanticTimeline: []
            ),
            recorder: recorder,
            sceneRegistry: registry,
            stepTimeoutNanoseconds: 100_000_000,
            terminalTimeoutNanoseconds: 100_000_000
        )

        driver.startIfNeeded()

        let completedResult = await driver.waitUntilFinished()
        let result = try XCTUnwrap(completedResult)

        XCTAssertEqual(result.state, .pass)
        XCTAssertEqual(
            recorder.snapshot().filter { $0.kind == .stepAcknowledged }.count,
            3
        )
    }

    func testUnavailableSceneStateIsInconclusive() async throws {
        let recorder = ProbeEventRecorder(
            runID: "driver-scene-state-timeout",
            scenarioID: "driver-scene-state-timeout",
            sink: { _ in }
        )
        let registry = ProbeSceneRegistry()
        recorder.record(
            ProbeSignal(
                kind: .sceneReady,
                semanticContext: semanticContext(screen: "home"),
                scenePhase: ProbeSceneReadiness.ready.rawValue
            )
        )
        let driver = ProbeScenarioDriver(
            scenario: ProbeScenario(
                identifier: "driver-scene-state-timeout",
                trackingMode: .manual,
                layout: .stack,
                steps: [
                    ProbeStep(.waitForSceneReady, scene: "scene-A"),
                    ProbeStep(
                        .waitForSignal,
                        scene: "scene-A",
                        signal: "scene-state:background"
                    )
                ],
                completionConditions: [],
                expectedSemanticTimeline: []
            ),
            recorder: recorder,
            sceneRegistry: registry,
            stepTimeoutNanoseconds: 5_000_000,
            terminalTimeoutNanoseconds: 5_000_000
        )
        driver.startIfNeeded()

        let completedResult = await driver.waitUntilFinished()
        let result = try XCTUnwrap(completedResult)

        XCTAssertEqual(result.state, .inconclusive)
        XCTAssertTrue(
            result.issues[0].reason.contains("scene-state:background"),
            result.issues[0].reason
        )
        XCTAssertEqual(
            recorder.snapshot().filter { $0.kind == .stepAcknowledged }.count,
            1
        )
    }

    func testDisconnectedRegistrationCannotExecuteAStaleSceneCommand() async throws {
        let recorder = ProbeEventRecorder(
            runID: "driver-stale",
            scenarioID: "driver-stale",
            sink: { _ in }
        )
        let registry = ProbeSceneRegistry()
        let window = UIWindow()
        let handle = try registeredHandle(
            registry.register(
                logicalSceneID: "scene-A",
                nativeSceneID: "native-A",
                window: window,
                currentRoute: ["home"]
            )
        )

        var invocationCount = 0
        let executor = ProbeSceneStepExecutor()
        executor.configure(handle: handle) { _ in
            invocationCount += 1
            return .accepted
        }
        let driver = ProbeScenarioDriver(
            scenario: ProbeScenario(
                identifier: "driver-stale",
                trackingMode: .manual,
                layout: .stack,
                steps: [
                    ProbeStep(
                        .setSwiftUIPath,
                        scene: "scene-A",
                        value: "detail-1"
                    )
                ],
                completionConditions: [],
                expectedSemanticTimeline: []
            ),
            recorder: recorder,
            sceneRegistry: registry,
            stepTimeoutNanoseconds: 5_000_000,
            terminalTimeoutNanoseconds: 5_000_000
        )
        driver.register(handle: handle, executor: executor)
        XCTAssertNotNil(registry.disconnect(handle))
        driver.startIfNeeded()

        let completedResult = await driver.waitUntilFinished()
        let result = try XCTUnwrap(completedResult)

        XCTAssertEqual(result.state, .fail)
        XCTAssertEqual(invocationCount, 0)
        XCTAssertTrue(
            result.issues[0].reason.contains("no live executor for scene-A"),
            result.issues[0].reason
        )
    }

    private func scenario(named identifier: String) throws -> ProbeScenario {
        try XCTUnwrap(
            ProbeScenarioCatalog.scenario(identifier: identifier),
            "missing catalog scenario \(identifier)"
        )
    }

    private func driveUIKitInteractiveTransition(
        outcome: ProbeTransitionOutcome
    ) async throws -> (
        semanticResult: ProbeSemanticResult,
        recorder: ProbeEventRecorder
    ) {
        let scenarioID = "uikit.split.pop-\(outcome.rawValue)"
        let recorder = ProbeEventRecorder(
            runID: "driver-uikit-\(outcome.rawValue)",
            scenarioID: scenarioID,
            sink: { _ in }
        )
        let registry = ProbeSceneRegistry()
        let window = UIWindow()
        let handle = try registeredHandle(
            registry.register(
                logicalSceneID: "scene-A",
                nativeSceneID: "native-A",
                window: window,
                currentRoute: ["secondary-2"]
            )
        )
        XCTAssertNotNil(registry.markReady(handle))

        recorder.record(
            ProbeSignal(
                kind: .sceneReady,
                semanticContext: semanticContext(screen: "secondary-2"),
                scenePhase: ProbeSceneReadiness.ready.rawValue
            )
        )
        recordUIKitOccurrence(
            recorder: recorder,
            screen: "secondary-1",
            occurrence: 1,
            viewID: "secondary-1-first",
            marker: "post-materialization"
        )
        recordUIKitOccurrence(
            recorder: recorder,
            screen: "secondary-2",
            occurrence: 1,
            viewID: "secondary-2",
            marker: "post-materialization"
        )
        recorder.record(
            ProbeSignal(
                kind: .destinationAppearanceObserved,
                semanticContext: semanticContext(
                    screen: "secondary-2",
                    occurrence: 1
                )
            )
        )

        let transitionID = "transition-\(outcome.rawValue)"
        let interval = outcome == .cancel ? "cancelled-pop" : "finished-pop"
        let executor = ProbeSceneStepExecutor()
        executor.configure(handle: handle) { step in
            switch step.kind {
            case .beginUIKitInteractiveTransition:
                recorder.record(
                    ProbeSignal(
                        kind: .intervalBegan,
                        semanticContext: self.semanticContext(screen: "secondary-2"),
                        interval: interval,
                        transitionID: transitionID
                    )
                )
                recorder.record(
                    ProbeSignal(
                        kind: .transitionBegan,
                        semanticContext: self.semanticContext(screen: "secondary-2"),
                        interval: interval,
                        transitionID: transitionID,
                        interactive: true,
                        outcome: outcome
                    )
                )
            case .updateUIKitInteractiveTransition:
                recorder.record(
                    ProbeSignal(
                        kind: .transitionProgress,
                        semanticContext: self.semanticContext(screen: "secondary-2"),
                        interval: interval,
                        transitionID: transitionID,
                        interactive: true,
                        transitionProgress: step.percentage
                    )
                )
            case .resolveUIKitInteractiveTransition:
                recorder.record(
                    ProbeSignal(
                        kind: .transitionResolutionRequested,
                        semanticContext: self.semanticContext(screen: "secondary-2"),
                        interval: interval,
                        transitionID: transitionID,
                        interactive: true,
                        outcome: outcome
                    )
                )
                if outcome == .finish {
                    recorder.record(
                        self.viewSignal(
                            id: "secondary-2",
                            screen: "secondary-2",
                            active: false,
                            documentVersion: 2
                        )
                    )
                    self.recordUIKitOccurrence(
                        recorder: recorder,
                        screen: "secondary-1",
                        occurrence: 2,
                        viewID: "secondary-1-returned",
                        marker: "post-return-materialization"
                    )
                }
                let resolvedScreen = outcome == .cancel
                    ? "secondary-2"
                    : "secondary-1"
                recorder.record(
                    ProbeSignal(
                        kind: .transitionResolved,
                        semanticContext: self.semanticContext(screen: resolvedScreen),
                        interval: interval,
                        transitionID: transitionID,
                        interactive: true,
                        outcome: outcome
                    )
                )
                recorder.record(
                    ProbeSignal(
                        kind: .intervalEnded,
                        semanticContext: self.semanticContext(screen: resolvedScreen),
                        interval: interval,
                        transitionID: transitionID
                    )
                )
                self.recordUIKitWork(
                    recorder: recorder,
                    screen: resolvedScreen,
                    occurrence: outcome == .cancel ? 1 : 2,
                    viewID: outcome == .cancel
                        ? "secondary-2"
                        : "secondary-1-returned",
                    marker: "post-\(outcome.rawValue)-resolution"
                )
            default:
                return .rejected(reason: "unsupported step")
            }
            return .accepted
        }

        let driver = ProbeScenarioDriver(
            scenario: try scenario(named: scenarioID),
            recorder: recorder,
            sceneRegistry: registry,
            stepTimeoutNanoseconds: 100_000_000,
            terminalTimeoutNanoseconds: 100_000_000
        )
        driver.register(handle: handle, executor: executor)
        driver.startIfNeeded()

        let completedResult = await driver.waitUntilFinished()

        return (
            semanticResult: try XCTUnwrap(completedResult),
            recorder: recorder
        )
    }

    private func recordUIKitOccurrence(
        recorder: ProbeEventRecorder,
        screen: String,
        occurrence: Int,
        viewID: String,
        marker: String
    ) {
        recorder.record(
            ProbeSignal(
                kind: .rumViewSnapshot,
                evidenceSource: .rumMapper,
                semanticContext: semanticContext(
                    screen: screen,
                    occurrence: occurrence
                ),
                rumContext: ProbeRUMContext(
                    sessionID: "session",
                    viewID: viewID,
                    viewName: screen,
                    viewActive: true,
                    viewDocumentVersion: 1
                )
            )
        )
        recordUIKitWork(
            recorder: recorder,
            screen: screen,
            occurrence: occurrence,
            viewID: viewID,
            marker: marker
        )
    }

    private func recordUIKitWork(
        recorder: ProbeEventRecorder,
        screen: String,
        occurrence: Int,
        viewID: String,
        marker: String
    ) {
        recorder.record(
            workSignal(
                kind: .rumAction,
                id: "\(screen)-\(occurrence)-\(marker)-action",
                name: marker,
                viewID: viewID,
                screen: screen,
                occurrence: occurrence
            )
        )
        recorder.record(
            workSignal(
                kind: .rumResource,
                id: "\(screen)-\(occurrence)-\(marker)-resource",
                name: marker,
                viewID: viewID,
                screen: screen,
                occurrence: occurrence
            )
        )
    }

    private func registeredHandle(
        _ result: ProbeSceneRegistrationResult
    ) throws -> ProbeSceneHandle {
        guard case .registered(let handle) = result else {
            throw NSError(
                domain: "ProbeScenarioDriverTests",
                code: 1
            )
        }
        return handle
    }

    private func semanticContext(
        screen: String,
        occurrence: Int? = nil
    ) -> ProbeSemanticContext {
        ProbeSemanticContext(
            logicalSceneID: "scene-A",
            nativeSceneID: "native-A",
            screen: screen,
            occurrence: occurrence
        )
    }

    private func pathSignal(
        previous: [String],
        current: [String]
    ) -> ProbeSignal {
        ProbeSignal(
            kind: .navigationPathMutation,
            semanticContext: semanticContext(
                screen: current.last ?? "home"
            ),
            previousNavigationPath: previous,
            navigationPath: current
        )
    }

    private func viewSignal(
        id: String,
        screen: String,
        active: Bool,
        documentVersion: Int64
    ) -> ProbeSignal {
        ProbeSignal(
            kind: .rumViewSnapshot,
            evidenceSource: .rumMapper,
            semanticContext: semanticContext(screen: screen),
            rumContext: ProbeRUMContext(
                sessionID: "session",
                viewID: id,
                viewName: screen,
                viewActive: active,
                viewDocumentVersion: documentVersion
            )
        )
    }

    private func workSignal(
        kind: ProbeSignalKind,
        id: String,
        name: String,
        viewID: String,
        screen: String,
        occurrence: Int
    ) -> ProbeSignal {
        ProbeSignal(
            kind: kind,
            evidenceSource: .rumMapper,
            semanticContext: semanticContext(
                screen: screen,
                occurrence: occurrence
            ),
            rumContext: ProbeRUMContext(
                sessionID: "session",
                viewID: viewID
            ),
            eventID: id,
            name: name
        )
    }

    private func recordSplitMaterialization(
        recorder: ProbeEventRecorder,
        screen: String,
        viewID: String,
        occurrence: Int
    ) {
        recorder.record(
            ProbeSignal(
                kind: .destinationMaterialized,
                semanticContext: semanticContext(screen: screen)
            )
        )
        recorder.record(
            workSignal(
                kind: .rumAction,
                id: "\(viewID)-action",
                name: "selection-committed",
                viewID: viewID,
                screen: screen,
                occurrence: occurrence
            )
        )
        recorder.record(
            workSignal(
                kind: .rumResource,
                id: "\(viewID)-resource",
                name: "selection-committed",
                viewID: viewID,
                screen: screen,
                occurrence: occurrence
            )
        )
    }
}

private final class DriverLockedLines: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func append(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        lines.append(line)
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }
}
