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
        XCTAssertEqual(recorded.map(\.schemaVersion), [5, 5])
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

    func testOwnerViewRelationDistinguishesAResumedAutomaticOccurrence() {
        let recorder = ProbeEventRecorder(
            runID: "automatic-resume",
            scenarioID: "automatic-resume",
            sink: { _ in },
            clock: { 42 }
        )
        recordAutomaticView(id: "home-before", recorder: recorder)
        recordAutomaticAction(
            name: "before-sheet",
            viewID: "home-before",
            recorder: recorder
        )
        recorder.record(
            ProbeSignal(
                kind: .stepStarted,
                stepKind: .setSwiftUIPresentation,
                name: "home"
            )
        )
        recordAutomaticView(id: "home-after", recorder: recorder)
        recordAutomaticAction(
            name: "dismissed-immediate",
            viewID: "home-after",
            recorder: recorder
        )
        recorder.record(
            ProbeSignal(
                kind: .rumResource,
                evidenceSource: .rumMapper,
                rumContext: ProbeRUMContext(
                    sessionID: "session",
                    viewID: "home-after"
                ),
                name: "dismissed-settled"
            )
        )

        let scenario = ProbeScenario(
            identifier: "automatic-resume",
            trackingMode: .automatic,
            layout: .stack,
            steps: [],
            completionConditions: [],
            expectedSemanticTimeline: [
                ProbeExpectation(
                    .action,
                    name: "dismissed-immediate",
                    ownerViewStartedAfterStep: .setSwiftUIPresentation,
                    ownerViewStartedAfterStepValue: "home",
                    ownerViewReferenceAction: "before-sheet",
                    ownerViewRelation: .different
                ),
                ProbeExpectation(
                    .resource,
                    name: "dismissed-settled",
                    ownerViewReferenceAction: "dismissed-immediate",
                    ownerViewRelation: .same
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

    func testOwnerViewRelationRejectsAReusedAutomaticOccurrence() {
        let recorder = ProbeEventRecorder(
            runID: "automatic-not-resumed",
            scenarioID: "automatic-not-resumed",
            sink: { _ in },
            clock: { 42 }
        )
        recordAutomaticView(id: "home", recorder: recorder)
        recordAutomaticAction(
            name: "before-sheet",
            viewID: "home",
            recorder: recorder
        )
        recorder.record(
            ProbeSignal(
                kind: .stepStarted,
                stepKind: .setSwiftUIPresentation,
                name: "home"
            )
        )
        recordAutomaticAction(
            name: "after-sheet",
            viewID: "home",
            recorder: recorder
        )

        let scenario = ProbeScenario(
            identifier: "automatic-not-resumed",
            trackingMode: .automatic,
            layout: .stack,
            steps: [],
            completionConditions: [],
            expectedSemanticTimeline: [
                ProbeExpectation(
                    .action,
                    name: "after-sheet",
                    ownerViewReferenceAction: "before-sheet",
                    ownerViewRelation: .different
                )
            ]
        )

        let result = ProbeSemanticOracle.evaluate(
            scenario: scenario,
            signals: recorder.snapshot()
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertTrue(result.issues[0].reason.contains("observed same"))
    }

    func testOwnerViewStartRejectsAnOwnerPredatingTheDismissalStep() {
        let recorder = ProbeEventRecorder(
            runID: "automatic-predates-dismissal",
            scenarioID: "automatic-predates-dismissal",
            sink: { _ in },
            clock: { 42 }
        )
        recordAutomaticView(id: "home", recorder: recorder)
        recorder.record(
            ProbeSignal(
                kind: .stepStarted,
                stepKind: .setSwiftUIPresentation,
                name: "home"
            )
        )
        recordAutomaticAction(
            name: "after-sheet",
            viewID: "home",
            recorder: recorder
        )

        let scenario = ProbeScenario(
            identifier: "automatic-predates-dismissal",
            trackingMode: .automatic,
            layout: .stack,
            steps: [],
            completionConditions: [],
            expectedSemanticTimeline: [
                ProbeExpectation(
                    .action,
                    name: "after-sheet",
                    ownerViewStartedAfterStep: .setSwiftUIPresentation,
                    ownerViewStartedAfterStepValue: "home"
                )
            ]
        )

        let result = ProbeSemanticOracle.evaluate(
            scenario: scenario,
            signals: recorder.snapshot()
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertTrue(result.issues[0].reason.contains("set-swiftui-presentation value home"))
    }

    func testNoAutomaticViewAllowsAnExplicitViewInsideTheInterval() {
        let recorder = ProbeEventRecorder(
            runID: "manual-interval",
            scenarioID: "manual-interval",
            sink: { _ in },
            clock: { 42 }
        )
        recorder.record(viewSignal(id: "sheet", screen: "sheet", active: true))
        recorder.record(viewSignal(id: "sheet", screen: "sheet", active: false))

        let scenario = ProbeScenario(
            identifier: "manual-interval",
            trackingMode: .automatic,
            layout: .stack,
            steps: [],
            completionConditions: [
                ProbeExpectation(
                    .noViewStarted,
                    rumViewOrigin: .automatic,
                    interval: "rum-view:scene-A/sheet#1"
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

    func testNoAutomaticViewRejectsADuplicateDuringExplicitViewLifetime() {
        let recorder = ProbeEventRecorder(
            runID: "manual-duplicate",
            scenarioID: "manual-duplicate",
            sink: { _ in },
            clock: { 42 }
        )
        recorder.record(viewSignal(id: "sheet", screen: "sheet", active: true))
        recordAutomaticView(id: "automatic-sheet", recorder: recorder)
        recorder.record(viewSignal(id: "sheet", screen: "sheet", active: false))

        let scenario = ProbeScenario(
            identifier: "manual-duplicate",
            trackingMode: .automatic,
            layout: .stack,
            steps: [],
            completionConditions: [
                ProbeExpectation(
                    .noViewStarted,
                    rumViewOrigin: .automatic,
                    interval: "rum-view:scene-A/sheet#1"
                )
            ],
            expectedSemanticTimeline: []
        )

        let result = ProbeSemanticOracle.evaluate(
            scenario: scenario,
            signals: recorder.snapshot()
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertTrue(result.issues[0].reason.contains("forbidden no-view-started"))
    }

    func testPresentationAuthorityAllowsFreshUnderlyingViewBeforeOutgoingFinalSnapshot() {
        let recorder = ProbeEventRecorder(
            runID: "presentation-overlap",
            scenarioID: "presentation-authority",
            sink: { _ in },
            clock: { 42 }
        )
        recorder.record(ProbeSignal(kind: .intervalBegan, interval: "manual-sheet-active"))
        recorder.record(
            ProbeSignal(kind: .intervalBegan, interval: "swiftui-presentation-subtree")
        )
        recorder.record(viewSignal(id: "sheet", screen: "sheet", active: true))
        recorder.record(ProbeSignal(kind: .intervalEnded, interval: "manual-sheet-active"))
        recordAutomaticView(id: "home-2", recorder: recorder)
        recorder.record(viewSignal(id: "sheet", screen: "sheet", active: false))
        recorder.record(
            ProbeSignal(kind: .intervalEnded, interval: "swiftui-presentation-subtree")
        )

        let result = ProbeSemanticOracle.evaluate(
            scenario: presentationAuthorityScenario(),
            signals: recorder.snapshot()
        )

        XCTAssertEqual(
            result.state,
            .pass,
            result.issues.map(\.reason).joined(separator: "\n")
        )
    }

    func testPresentationAuthorityRejectsDelayedAutomaticPresentationAfterSemanticStop() {
        let recorder = ProbeEventRecorder(
            runID: "presentation-duplicate",
            scenarioID: "presentation-authority",
            sink: { _ in },
            clock: { 42 }
        )
        recorder.record(ProbeSignal(kind: .intervalBegan, interval: "manual-sheet-active"))
        recorder.record(
            ProbeSignal(kind: .intervalBegan, interval: "swiftui-presentation-subtree")
        )
        recorder.record(viewSignal(id: "sheet", screen: "sheet", active: true))
        recorder.record(ProbeSignal(kind: .intervalEnded, interval: "manual-sheet-active"))
        recorder.record(viewSignal(id: "sheet", screen: "sheet", active: false))
        recordAutomaticView(
            id: "automatic-sheet",
            viewName: "ProbeSheetView",
            recorder: recorder
        )
        recorder.record(
            ProbeSignal(kind: .intervalEnded, interval: "swiftui-presentation-subtree")
        )

        let result = ProbeSemanticOracle.evaluate(
            scenario: presentationAuthorityScenario(),
            signals: recorder.snapshot()
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertTrue(result.issues[0].reason.contains("rum-view-name=ProbeSheetView"))
    }

    func testKeyedManualAuthorityContractPasses() throws {
        let scenario = try scenario(
            named: "swiftui.coexistence.automatic-keyed-manual-view"
        )

        let result = ProbeSemanticOracle.evaluate(
            scenario: scenario,
            signals: keyedManualSignals()
        )

        XCTAssertEqual(
            result.state,
            .pass,
            result.issues.map(\.reason).joined(separator: "\n")
        )
    }

    func testKeyedManualAuthorityRejectsRetainedAutomaticHome() throws {
        let scenario = try scenario(
            named: "swiftui.coexistence.automatic-keyed-manual-view"
        )

        let result = ProbeSemanticOracle.evaluate(
            scenario: scenario,
            signals: keyedManualSignals(mutation: .retainInitialHome)
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertTrue(result.issues[0].reason.contains("missing expected view-stopped"))
    }

    func testKeyedManualAuthorityFindsDeferredHomeStopAfterManualStop() throws {
        let scenario = try scenario(
            named: "swiftui.coexistence.automatic-keyed-manual-view"
        )

        let result = ProbeSemanticOracle.evaluate(
            scenario: scenario,
            signals: keyedManualSignals(mutation: .deferInitialHomeStop)
        )

        XCTAssertEqual(
            result.state,
            .pass,
            result.issues.map(\.reason).joined(separator: "\n")
        )
    }

    func testKeyedManualAuthorityRejectsAutomaticViewBeforeManualSnapshot() throws {
        let scenario = try scenario(
            named: "swiftui.coexistence.automatic-keyed-manual-view"
        )

        let result = ProbeSemanticOracle.evaluate(
            scenario: scenario,
            signals: keyedManualSignals(mutation: .automaticBeforeManualSnapshot)
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertTrue(result.issues[0].reason.contains("forbidden no-view-started"))
    }

    func testKeyedManualAuthorityRejectsWrongManualWorkOwner() throws {
        let scenario = try scenario(
            named: "swiftui.coexistence.automatic-keyed-manual-view"
        )

        let result = ProbeSemanticOracle.evaluate(
            scenario: scenario,
            signals: keyedManualSignals(mutation: .manualWorkUsesAutomaticHome)
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertTrue(result.issues[0].reason.contains("semantic RUM view"))
    }

    func testKeyedManualAuthorityRejectsReusedHomeAfterStop() throws {
        let scenario = try scenario(
            named: "swiftui.coexistence.automatic-keyed-manual-view"
        )

        let result = ProbeSemanticOracle.evaluate(
            scenario: scenario,
            signals: keyedManualSignals(mutation: .reuseInitialHomeOnReturn)
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertTrue(result.issues[0].reason.contains("started after stop-keyed-manual-view"))
    }

    func testKeyedManualAuthorityRejectsDifferentSettledOwner() throws {
        let scenario = try scenario(
            named: "swiftui.coexistence.automatic-keyed-manual-view"
        )

        let result = ProbeSemanticOracle.evaluate(
            scenario: scenario,
            signals: keyedManualSignals(mutation: .changeOwnerBeforeSettledWork)
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertTrue(result.issues[0].reason.contains("observed different"))
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

    private func recordAutomaticView(
        id: String,
        active: Bool = true,
        viewName: String = "NavigationStackHostingController",
        recorder: ProbeEventRecorder
    ) {
        recorder.record(
            ProbeSignal(
                kind: .rumViewSnapshot,
                evidenceSource: .rumMapper,
                rumContext: ProbeRUMContext(
                    sessionID: "session",
                    viewID: id,
                    viewName: viewName,
                    viewActive: active,
                    viewDocumentVersion: active ? 1 : 2
                )
            )
        )
    }

    private func presentationAuthorityScenario() -> ProbeScenario {
        ProbeScenario(
            identifier: "presentation-authority",
            trackingMode: .automatic,
            layout: .stack,
            steps: [],
            completionConditions: [
                ProbeExpectation(
                    .noViewStarted,
                    rumViewOrigin: .automatic,
                    interval: "manual-sheet-active"
                ),
                ProbeExpectation(
                    .noViewStarted,
                    rumViewOrigin: .automatic,
                    rumViewName: "ProbeSheetView",
                    interval: "swiftui-presentation-subtree"
                )
            ],
            expectedSemanticTimeline: []
        )
    }

    private func recordAutomaticAction(
        name: String,
        viewID: String,
        recorder: ProbeEventRecorder
    ) {
        recorder.record(
            ProbeSignal(
                kind: .rumAction,
                evidenceSource: .rumMapper,
                rumContext: ProbeRUMContext(
                    sessionID: "session",
                    viewID: viewID
                ),
                name: name
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

    private enum KeyedManualMutation {
        case retainInitialHome
        case deferInitialHomeStop
        case automaticBeforeManualSnapshot
        case manualWorkUsesAutomaticHome
        case reuseInitialHomeOnReturn
        case changeOwnerBeforeSettledWork
    }

    private func keyedManualSignals(
        mutation: KeyedManualMutation? = nil
    ) -> [ProbeSignal] {
        let recorder = ProbeEventRecorder(
            runID: "keyed-manual-contract",
            scenarioID: "swiftui.coexistence.automatic-keyed-manual-view",
            sink: { _ in },
            clock: { 42 }
        )

        recordAutomaticView(id: "home-1", recorder: recorder)
        recorder.record(
            keyedManualWorkSignal(
                kind: .rumAction,
                name: "automatic-home-before-keyed-manual",
                viewID: "home-1",
                sourceScreen: "home"
            )
        )
        recorder.record(
            keyedManualWorkSignal(
                kind: .rumResource,
                name: "automatic-home-before-keyed-manual",
                viewID: "home-1",
                sourceScreen: "home"
            )
        )
        recorder.record(
            ProbeSignal(
                kind: .stepStarted,
                stepKind: .startKeyedManualView,
                name: "compose"
            )
        )
        recorder.record(
            ProbeSignal(
                kind: .intervalBegan,
                interval: "keyed-manual-authority"
            )
        )
        if mutation == .automaticBeforeManualSnapshot {
            recordAutomaticView(id: "early-automatic", recorder: recorder)
        }
        recorder.record(viewSignal(id: "compose", screen: "compose", active: true))
        if mutation != .retainInitialHome && mutation != .deferInitialHomeStop {
            recordAutomaticView(id: "home-1", active: false, recorder: recorder)
        }

        let manualWorkOwner = mutation == .manualWorkUsesAutomaticHome
            ? "home-1"
            : "compose"
        recorder.record(
            keyedManualWorkSignal(
                kind: .rumAction,
                name: "keyed-manual-active",
                viewID: manualWorkOwner,
                sourceScreen: "compose"
            )
        )
        recorder.record(
            keyedManualWorkSignal(
                kind: .rumResource,
                name: "keyed-manual-active",
                viewID: manualWorkOwner,
                sourceScreen: "compose"
            )
        )
        recorder.record(
            ProbeSignal(
                kind: .stepStarted,
                stepKind: .stopKeyedManualView,
                name: "compose"
            )
        )
        recorder.record(
            ProbeSignal(
                kind: .intervalEnded,
                interval: "keyed-manual-authority"
            )
        )
        recorder.record(viewSignal(id: "compose", screen: "compose", active: false))
        if mutation == .deferInitialHomeStop {
            recordAutomaticView(id: "home-1", active: false, recorder: recorder)
        }

        let returnedOwner: String
        if mutation == .reuseInitialHomeOnReturn {
            returnedOwner = "home-1"
        } else {
            returnedOwner = "home-2"
            recordAutomaticView(id: returnedOwner, recorder: recorder)
        }
        recorder.record(
            keyedManualWorkSignal(
                kind: .rumAction,
                name: "keyed-manual-stopped-immediate",
                viewID: returnedOwner,
                sourceScreen: "home"
            )
        )
        recorder.record(
            keyedManualWorkSignal(
                kind: .rumResource,
                name: "keyed-manual-stopped-immediate",
                viewID: returnedOwner,
                sourceScreen: "home"
            )
        )

        let settledOwner: String
        if mutation == .changeOwnerBeforeSettledWork {
            settledOwner = "home-3"
            recordAutomaticView(id: settledOwner, recorder: recorder)
        } else {
            settledOwner = returnedOwner
        }
        recorder.record(
            keyedManualWorkSignal(
                kind: .rumAction,
                name: "keyed-manual-stopped-settled",
                viewID: settledOwner,
                sourceScreen: "home"
            )
        )
        recorder.record(
            keyedManualWorkSignal(
                kind: .rumResource,
                name: "keyed-manual-stopped-settled",
                viewID: settledOwner,
                sourceScreen: "home"
            )
        )
        return recorder.snapshot()
    }

    private func keyedManualWorkSignal(
        kind: ProbeSignalKind,
        name: String,
        viewID: String,
        sourceScreen: String
    ) -> ProbeSignal {
        ProbeSignal(
            kind: kind,
            evidenceSource: .rumMapper,
            sourceContext: ProbeSourceContext(
                logicalSceneID: "scene-A",
                nativeSceneID: "native-A",
                screen: sourceScreen
            ),
            rumContext: ProbeRUMContext(
                sessionID: "session",
                viewID: viewID
            ),
            eventID: "\(kind.rawValue)-\(name)",
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
