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
        XCTAssertEqual(recorded.map(\.schemaVersion), [3, 3])
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
