/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

final class ProbeSemanticOracleTests: XCTestCase {
    func testEXP098ReturnedHomeAttributionPasses() throws {
        let scenario = try scenario(named: "swiftui.stack.return")
        let signals = try fixtureSignals(named: "exp-098-pass")

        let result = ProbeSemanticOracle.evaluate(
            scenario: scenario,
            signals: signals
        )
        let timeline = ProbeSemanticTimeline(signals: signals)

        XCTAssertEqual(Set(signals.map(\.schemaVersion)), [1])
        XCTAssertEqual(result.state, .pass, result.issues.map(\.reason).joined(separator: "\n"))
        XCTAssertEqual(
            timeline.viewID(scene: "scene-A", screen: "home", occurrence: 1),
            "view-home-1"
        )
        XCTAssertEqual(
            timeline.viewID(scene: "scene-A", screen: "home", occurrence: 2),
            "view-home-2"
        )
    }

    func testEXP092WrongReturnedHomeViewFailsWithBothViewIDs() throws {
        let result = ProbeSemanticOracle.evaluate(
            scenario: try scenario(named: "swiftui.stack.return"),
            signals: try fixtureSignals(named: "exp-092-wrong-view")
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertTrue(result.issues[0].reason.contains("view-home-2"))
        XCTAssertTrue(result.issues[0].reason.contains("view-detail-1"))
    }

    func testIgnoredNativeGestureIsInconclusive() throws {
        let result = ProbeSemanticOracle.evaluate(
            scenario: try scenario(named: "swiftui.stack.native-pop-cancel"),
            signals: try fixtureSignals(named: "ignored-native-gesture")
        )

        XCTAssertEqual(result.state, .inconclusive)
        XCTAssertTrue(result.issues[0].reason.contains("no transition or path signal"))
    }

    func testMissingExpectedEventFailsWithUsefulReason() throws {
        let result = ProbeSemanticOracle.evaluate(
            scenario: try scenario(named: "swiftui.stack.return"),
            signals: try fixtureSignals(named: "missing-expected-event")
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertTrue(result.issues[0].reason.contains("missing expected action"))
        XCTAssertTrue(result.issues[0].reason.contains("navigation-appearance-2"))
    }

    func testViewStopMayBeObservedAfterNextViewStarts() {
        let recorder = ProbeEventRecorder(
            runID: "overlapping-transition",
            scenarioID: "overlapping-transition",
            sink: { _ in },
            clock: { 42 }
        )
        recorder.record(viewSignal(id: "home-1", screen: "home", active: true))
        recorder.record(viewSignal(id: "detail-1", screen: "detail-1", active: true))
        recorder.record(viewSignal(id: "home-1", screen: "home", active: false))

        let scenario = ProbeScenario(
            identifier: "overlapping-transition",
            trackingMode: .navigationOccurrence,
            layout: .stack,
            steps: [],
            completionConditions: [],
            expectedSemanticTimeline: [
                ProbeExpectation(
                    .viewStarted,
                    scene: "scene-A",
                    screen: "home",
                    occurrence: 1
                ),
                ProbeExpectation(
                    .viewStopped,
                    scene: "scene-A",
                    screen: "home",
                    occurrence: 1
                ),
                ProbeExpectation(
                    .viewStarted,
                    scene: "scene-A",
                    screen: "detail-1",
                    occurrence: 1
                )
            ]
        )

        let result = ProbeSemanticOracle.evaluate(
            scenario: scenario,
            signals: recorder.snapshot()
        )

        XCTAssertEqual(
            result.state,
            .pass,
            result.issues.map(\.reason).joined(separator: "\n")
        )
    }

    func testResourceCompletionMayBeObservedAfterNextViewStarts() {
        let recorder = ProbeEventRecorder(
            runID: "overlapping-resource",
            scenarioID: "overlapping-resource",
            sink: { _ in },
            clock: { 42 }
        )
        recorder.record(viewSignal(id: "detail-1", screen: "detail-1", active: true))
        recorder.record(
            workSignal(
                kind: .rumAction,
                id: "detail-1-action",
                name: "selection-committed",
                viewID: "detail-1",
                screen: "detail-1",
                occurrence: 1
            )
        )
        recorder.record(viewSignal(id: "detail-2", screen: "detail-2", active: true))
        recorder.record(
            workSignal(
                kind: .rumResource,
                id: "detail-1-resource",
                name: "selection-committed",
                viewID: "detail-1",
                screen: "detail-1",
                occurrence: 1
            )
        )

        let scenario = ProbeScenario(
            identifier: "overlapping-resource",
            trackingMode: .navigationOccurrence,
            layout: .splitSelection,
            steps: [],
            completionConditions: [],
            expectedSemanticTimeline: [
                ProbeExpectation(
                    .viewStarted,
                    scene: "scene-A",
                    screen: "detail-1",
                    occurrence: 1
                ),
                ProbeExpectation(
                    .action,
                    scene: "scene-A",
                    screen: "detail-1",
                    occurrence: 1,
                    name: "selection-committed"
                ),
                ProbeExpectation(
                    .resource,
                    scene: "scene-A",
                    screen: "detail-1",
                    occurrence: 1,
                    name: "selection-committed"
                ),
                ProbeExpectation(
                    .viewStarted,
                    scene: "scene-A",
                    screen: "detail-2",
                    occurrence: 1
                )
            ]
        )

        let result = ProbeSemanticOracle.evaluate(
            scenario: scenario,
            signals: recorder.snapshot()
        )

        XCTAssertEqual(
            result.state,
            .pass,
            result.issues.map(\.reason).joined(separator: "\n")
        )
    }

    func testCompletionConditionFindsLaterSameNamedOccurrence() {
        let recorder = ProbeEventRecorder(
            runID: "repeated-completion",
            scenarioID: "repeated-completion",
            sink: { _ in },
            clock: { 42 }
        )
        recorder.record(viewSignal(id: "detail-2-1", screen: "detail-2", active: true))
        recorder.record(
            workSignal(
                kind: .rumAction,
                id: "detail-2-1-action",
                name: "selection-committed",
                viewID: "detail-2-1",
                screen: "detail-2",
                occurrence: 1
            )
        )
        recorder.record(viewSignal(id: "placeholder", screen: "placeholder", active: true))
        recorder.record(viewSignal(id: "detail-2-2", screen: "detail-2", active: true))
        recorder.record(
            workSignal(
                kind: .rumAction,
                id: "detail-2-2-action",
                name: "selection-committed",
                viewID: "detail-2-2",
                screen: "detail-2",
                occurrence: 2
            )
        )

        let scenario = ProbeScenario(
            identifier: "repeated-completion",
            trackingMode: .navigationOccurrence,
            layout: .splitSelection,
            steps: [],
            completionConditions: [
                ProbeExpectation(
                    .action,
                    scene: "scene-A",
                    screen: "detail-2",
                    occurrence: 2,
                    name: "selection-committed"
                )
            ],
            expectedSemanticTimeline: []
        )

        let result = ProbeSemanticOracle.evaluate(
            scenario: scenario,
            signals: recorder.snapshot()
        )

        XCTAssertEqual(
            result.state,
            .pass,
            result.issues.map(\.reason).joined(separator: "\n")
        )
    }

    func testExplicitlyForbiddenViewFailsWithSignalSequence() throws {
        let result = ProbeSemanticOracle.evaluate(
            scenario: try scenario(named: "swiftui.stack.abort"),
            signals: try fixtureSignals(named: "forbidden-view-start")
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertEqual(result.issues[0].signalSequence, 3)
        XCTAssertTrue(result.issues[0].reason.contains("forbidden no-view-started"))
    }

    func testUnavailableRequiredCapabilityIsSkipped() throws {
        let scenario = try scenario(named: "swiftui.stack.native-pop-cancel")
        let signal = ProbeSignal(
            kind: .capability,
            sequence: 1,
            timestampMilliseconds: 1,
            runID: "unavailable-capability",
            scenarioID: scenario.identifier,
            capability: .nativeSwiftUIGesture,
            available: false
        )

        let result = ProbeSemanticOracle.evaluate(
            scenario: scenario,
            signals: [signal]
        )

        XCTAssertEqual(result.state, .skipped)
        XCTAssertTrue(result.issues[0].reason.contains("native-swiftui-gesture"))
    }

    func testResultStateVocabularyIsExact() {
        XCTAssertEqual(
            Set(ProbeSemanticResultState.allCases.map(\.rawValue)),
            Set(["PASS", "FAIL", "SKIPPED", "INCONCLUSIVE"])
        )
    }

    func testRecorderSerializesOrderedEnvelopeWithoutConflatingSourceAndOwner() throws {
        let lines = LockedLines()
        let recorder = ProbeEventRecorder(
            runID: "recorder-run",
            scenarioID: "recorder-scenario",
            sink: { lines.append($0) },
            clock: { 42 }
        )

        recorder.record(
            ProbeSignal(
                kind: .rumAction,
                evidenceSource: .rumMapper,
                sequence: 99,
                timestampMilliseconds: 99,
                runID: "draft-run",
                scenarioID: "draft-scenario",
                sourceContext: ProbeSourceContext(
                    logicalSceneID: "scene-A",
                    nativeSceneID: "native-A",
                    screen: "home",
                    phase: "marker"
                ),
                rumContext: ProbeRUMContext(
                    sessionID: "session",
                    viewID: "view-detail"
                ),
                name: "marker"
            )
        )
        recorder.record(
            ProbeSignal(
                kind: .sceneReady,
                sceneDisconnectGeneration: 3
            )
        )

        let recorded = recorder.snapshot()
        let encoded = lines.snapshot()
        let first = try JSONDecoder().decode(
            ProbeSignalRecord.self,
            from: XCTUnwrap(encoded.first).data(using: .utf8)!
        )

        XCTAssertEqual(recorded.map(\.sequence), [1, 2])
        XCTAssertEqual(recorded.map(\.schemaVersion), [4, 4])
        XCTAssertEqual(recorded.map(\.timestampMilliseconds), [42, 42])
        XCTAssertEqual(recorded.map(\.runID), ["recorder-run", "recorder-run"])
        XCTAssertEqual(
            recorded.map(\.scenarioID),
            ["recorder-scenario", "recorder-scenario"]
        )
        XCTAssertEqual(first.signal.sourceContext?.logicalSceneID, "scene-A")
        XCTAssertEqual(first.signal.rumContext?.viewID, "view-detail")
        XCTAssertNil(first.signal.semanticContext)
        XCTAssertEqual(recorded[1].sceneDisconnectGeneration, 3)
    }

    func testAutomaticViewOriginKeepsSourceAndOwnerEvidenceSeparate() {
        let recorder = ProbeEventRecorder(
            runID: "automatic-owner",
            scenarioID: "automatic-owner",
            sink: { _ in },
            clock: { 42 }
        )
        recorder.record(
            ProbeSignal(
                kind: .stepStarted,
                stepKind: .openWindow,
                name: "scene-B"
            )
        )
        recorder.record(
            ProbeSignal(
                kind: .rumViewSnapshot,
                evidenceSource: .rumMapper,
                rumContext: ProbeRUMContext(
                    sessionID: "session",
                    viewID: "automatic-b",
                    viewName: "NavigationStackHostingController",
                    viewActive: true,
                    viewDocumentVersion: 1
                )
            )
        )
        recorder.record(
            ProbeSignal(
                kind: .rumAction,
                evidenceSource: .rumMapper,
                sourceContext: ProbeSourceContext(
                    logicalSceneID: "scene-B",
                    nativeSceneID: "native-B",
                    screen: "home",
                    phase: "automatic-b-marker"
                ),
                rumContext: ProbeRUMContext(
                    sessionID: "session",
                    viewID: "automatic-b"
                ),
                name: "automatic-b-marker"
            )
        )

        let scenario = ProbeScenario(
            identifier: "automatic-owner",
            trackingMode: .navigationOccurrence,
            layout: .stack,
            steps: [],
            completionConditions: [],
            expectedSemanticTimeline: [
                ProbeExpectation(
                    .action,
                    name: "automatic-b-marker",
                    sourceScene: "scene-B",
                    sourceScreen: "home",
                    rumViewOrigin: .automatic,
                    ownerViewStartedAfterSceneOpen: "scene-B"
                )
            ]
        )

        let result = ProbeSemanticOracle.evaluate(
            scenario: scenario,
            signals: recorder.snapshot()
        )

        XCTAssertEqual(
            result.state,
            .pass,
            result.issues.map(\.reason).joined(separator: "\n")
        )
    }

    func testAutomaticViewOriginRejectsSemanticOwner() {
        let recorder = ProbeEventRecorder(
            runID: "wrong-automatic-owner",
            scenarioID: "wrong-automatic-owner",
            sink: { _ in },
            clock: { 42 }
        )
        recorder.record(viewSignal(id: "semantic-a", screen: "home", active: true))
        recorder.record(
            ProbeSignal(
                kind: .rumAction,
                evidenceSource: .rumMapper,
                sourceContext: ProbeSourceContext(
                    logicalSceneID: "scene-B",
                    nativeSceneID: "native-B",
                    screen: "home",
                    phase: "automatic-b-marker"
                ),
                rumContext: ProbeRUMContext(
                    sessionID: "session",
                    viewID: "semantic-a"
                ),
                name: "automatic-b-marker"
            )
        )

        let scenario = ProbeScenario(
            identifier: "wrong-automatic-owner",
            trackingMode: .navigationOccurrence,
            layout: .stack,
            steps: [],
            completionConditions: [],
            expectedSemanticTimeline: [
                ProbeExpectation(
                    .action,
                    name: "automatic-b-marker",
                    sourceScene: "scene-B",
                    sourceScreen: "home",
                    rumViewOrigin: .automatic
                )
            ]
        )

        let result = ProbeSemanticOracle.evaluate(
            scenario: scenario,
            signals: recorder.snapshot()
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertTrue(result.issues[0].reason.contains("observed semantic"))
    }

    func testAutomaticViewOriginRejectsOwnerPredatingSceneOpen() {
        let recorder = ProbeEventRecorder(
            runID: "stale-automatic-owner",
            scenarioID: "stale-automatic-owner",
            sink: { _ in },
            clock: { 42 }
        )
        recorder.record(
            ProbeSignal(
                kind: .rumViewSnapshot,
                evidenceSource: .rumMapper,
                rumContext: ProbeRUMContext(
                    sessionID: "session",
                    viewID: "automatic-a",
                    viewName: "NavigationStackHostingController",
                    viewActive: true,
                    viewDocumentVersion: 1
                )
            )
        )
        recorder.record(
            ProbeSignal(
                kind: .stepStarted,
                stepKind: .openWindow,
                name: "scene-B"
            )
        )
        recorder.record(
            ProbeSignal(
                kind: .rumAction,
                evidenceSource: .rumMapper,
                sourceContext: ProbeSourceContext(
                    logicalSceneID: "scene-B",
                    nativeSceneID: "native-B",
                    screen: "home",
                    phase: "automatic-b-marker"
                ),
                rumContext: ProbeRUMContext(
                    sessionID: "session",
                    viewID: "automatic-a"
                ),
                name: "automatic-b-marker"
            )
        )

        let scenario = ProbeScenario(
            identifier: "stale-automatic-owner",
            trackingMode: .navigationOccurrence,
            layout: .stack,
            steps: [],
            completionConditions: [],
            expectedSemanticTimeline: [
                ProbeExpectation(
                    .action,
                    name: "automatic-b-marker",
                    sourceScene: "scene-B",
                    sourceScreen: "home",
                    rumViewOrigin: .automatic,
                    ownerViewStartedAfterSceneOpen: "scene-B"
                )
            ]
        )

        let result = ProbeSemanticOracle.evaluate(
            scenario: scenario,
            signals: recorder.snapshot()
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertTrue(result.issues[0].reason.contains("started after opening scene-B"))
    }

    private func scenario(named identifier: String) throws -> ProbeScenario {
        try XCTUnwrap(
            ProbeScenarioCatalog.scenario(identifier: identifier),
            "missing catalog scenario \(identifier)"
        )
    }

    private func fixtureSignals(named name: String) throws -> [ProbeSignal] {
        let bundle = Bundle(for: ProbeSemanticOracleTests.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: name, withExtension: "jsonl"),
            "fixture \(name).jsonl is missing from the test bundle"
        )
        let data = try Data(contentsOf: url)
        let contents = try XCTUnwrap(String(data: data, encoding: .utf8))
        let decoder = JSONDecoder()

        return try contents
            .split(whereSeparator: \.isNewline)
            .map { line in
                try decoder.decode(
                    ProbeSignalRecord.self,
                    from: Data(line.utf8)
                ).signal
            }
    }

    private func viewSignal(
        id: String,
        screen: String,
        active: Bool
    ) -> ProbeSignal {
        ProbeSignal(
            kind: .rumViewSnapshot,
            evidenceSource: .rumMapper,
            semanticContext: ProbeSemanticContext(
                logicalSceneID: "scene-A",
                nativeSceneID: "native-A",
                screen: screen
            ),
            rumContext: ProbeRUMContext(
                sessionID: "session",
                viewID: id,
                viewName: screen,
                viewActive: active,
                viewDocumentVersion: active ? 1 : 2
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
            semanticContext: ProbeSemanticContext(
                logicalSceneID: "scene-A",
                nativeSceneID: "native-A",
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
}

private final class LockedLines: @unchecked Sendable {
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
