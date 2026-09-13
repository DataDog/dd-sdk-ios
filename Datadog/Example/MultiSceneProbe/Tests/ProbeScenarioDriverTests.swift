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
        let recorder = ProbeEventRecorder(
            runID: "driver-pass",
            scenarioID: "swiftui.stack.return",
            sink: { lines.append($0) },
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
        XCTAssertFalse(recorder.recordTerminalResult(result))
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
