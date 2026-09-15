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

    func testNestedKeyedManualAuthorityContractPasses() throws {
        let scenario = try scenario(
            named: "swiftui.coexistence.nested-keyed-manual-view"
        )

        let result = ProbeSemanticOracle.evaluate(
            scenario: scenario,
            signals: nestedKeyedManualSignals()
        )

        XCTAssertEqual(
            result.state,
            .pass,
            result.issues.map(\.reason).joined(separator: "\n")
        )
    }

    func testNestedKeyedManualAuthorityRejectsReusedComposeOccurrence() throws {
        let scenario = try scenario(
            named: "swiftui.coexistence.nested-keyed-manual-view"
        )

        let result = ProbeSemanticOracle.evaluate(
            scenario: scenario,
            signals: nestedKeyedManualSignals(mutation: .reuseFirstComposeOnReveal)
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertEqual(result.issues[0].expectation?.kind, .viewStarted)
        XCTAssertEqual(result.issues[0].expectation?.screen, "compose")
        XCTAssertEqual(result.issues[0].expectation?.occurrence, 2)
    }

    func testNestedKeyedManualAuthorityRejectsViewRestartDuringDuplicateStart() throws {
        let scenario = try scenario(
            named: "swiftui.coexistence.nested-keyed-manual-view"
        )

        let result = ProbeSemanticOracle.evaluate(
            scenario: scenario,
            signals: nestedKeyedManualSignals(mutation: .startViewDuringDuplicate)
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertTrue(result.issues[0].reason.contains("forbidden no-view-started"))
    }

    func testNestedKeyedManualAuthorityRejectsWrongResumedComposeOwner() throws {
        let scenario = try scenario(
            named: "swiftui.coexistence.nested-keyed-manual-view"
        )

        let result = ProbeSemanticOracle.evaluate(
            scenario: scenario,
            signals: nestedKeyedManualSignals(mutation: .resumedWorkUsesFirstCompose)
        )

        XCTAssertEqual(result.state, .fail)
    }

    func testNestedKeyedManualAuthorityRejectsReusedHomeOccurrence() throws {
        let scenario = try scenario(
            named: "swiftui.coexistence.nested-keyed-manual-view"
        )

        let result = ProbeSemanticOracle.evaluate(
            scenario: scenario,
            signals: nestedKeyedManualSignals(mutation: .reuseInitialHomeOnReturn)
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertTrue(result.issues[0].reason.contains("started after stop-keyed-manual-view"))
    }

    func testOperationCrossSceneContractPasses() throws {
        let scenario = try scenario(named: "operations.cross-scene.lifecycle")
        let result = ProbeSemanticOracle.evaluate(
            scenario: scenario,
            signals: operationCrossSceneSignals()
        )

        XCTAssertEqual(
            result.state,
            .pass,
            result.issues.map(\.reason).joined(separator: "\n")
        )
    }

    func testOperationCrossSceneRejectsOneViewIDAcrossScenes() throws {
        let scenario = try scenario(named: "operations.cross-scene.lifecycle")
        let result = ProbeSemanticOracle.evaluate(
            scenario: scenario,
            signals: operationCrossSceneSignals(mutation: .reuseViewIDAcrossScenes)
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertTrue(try XCTUnwrap(result.issues.first).reason.contains("maps to both"))
    }

    func testOperationCrossSceneRejectsBHomeWorkOnA() throws {
        let scenario = try scenario(named: "operations.cross-scene.lifecycle")
        let result = ProbeSemanticOracle.evaluate(
            scenario: scenario,
            signals: operationCrossSceneSignals(mutation: .attributeBHomeToA)
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertEqual(
            try XCTUnwrap(result.issues.first).expectation?.name,
            "operation-cross-home-b"
        )
    }

    func testOperationCrossSceneRejectsBCompletionOnA() throws {
        let scenario = try scenario(named: "operations.cross-scene.lifecycle")
        let result = ProbeSemanticOracle.evaluate(
            scenario: scenario,
            signals: operationCrossSceneSignals(mutation: .attributeBCompletionToA)
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertEqual(
            try XCTUnwrap(result.issues.first).expectation?.name,
            "operation-cross-success-end-b"
        )
    }

    func testOperationCrossSceneRejectsChangedAOwnerAfterBCompletes() throws {
        let scenario = try scenario(named: "operations.cross-scene.lifecycle")
        let result = ProbeSemanticOracle.evaluate(
            scenario: scenario,
            signals: operationCrossSceneSignals(mutation: .changeAOwnerAfterBCompletion)
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertEqual(
            try XCTUnwrap(result.issues.first).expectation?.name,
            "operation-parallel-alpha-end-a"
        )
    }

    func testSameKeyManualTwoSceneContractPasses() throws {
        let scenario = try scenario(
            named: "swiftui.coexistence.same-key-manual-two-scenes"
        )

        let result = ProbeSemanticOracle.evaluate(
            scenario: scenario,
            signals: sameKeyManualTwoSceneSignals()
        )

        XCTAssertEqual(
            result.state,
            .pass,
            result.issues.map(\.reason).joined(separator: "\n")
        )
    }

    func testSameKeyManualTwoSceneRejectsOneComposeViewIDAcrossScenes() throws {
        let scenario = try scenario(
            named: "swiftui.coexistence.same-key-manual-two-scenes"
        )

        let result = ProbeSemanticOracle.evaluate(
            scenario: scenario,
            signals: sameKeyManualTwoSceneSignals(
                mutation: .reuseComposeViewIDAcrossScenes
            )
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertTrue(result.issues[0].reason.contains("maps to both"))
    }

    func testSameKeyManualTwoSceneRejectsBWorkOnACompose() throws {
        let scenario = try scenario(
            named: "swiftui.coexistence.same-key-manual-two-scenes"
        )

        let result = ProbeSemanticOracle.evaluate(
            scenario: scenario,
            signals: sameKeyManualTwoSceneSignals(
                mutation: .attributeBWorkToACompose
            )
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertEqual(result.issues[0].expectation?.scene, "scene-B")
        XCTAssertEqual(result.issues[0].expectation?.screen, "compose")
    }

    func testSameKeyManualTwoSceneRejectsBStopPreemptingA() throws {
        let scenario = try scenario(
            named: "swiftui.coexistence.same-key-manual-two-scenes"
        )

        let result = ProbeSemanticOracle.evaluate(
            scenario: scenario,
            signals: sameKeyManualTwoSceneSignals(
                mutation: .stopAWhenBStops
            )
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertEqual(
            result.issues[0].expectation?.name,
            "same-key-compose-a-after-b-stop"
        )
    }

    func testSameKeyManualTwoSceneRejectsReusedBHome() throws {
        let scenario = try scenario(
            named: "swiftui.coexistence.same-key-manual-two-scenes"
        )

        let result = ProbeSemanticOracle.evaluate(
            scenario: scenario,
            signals: sameKeyManualTwoSceneSignals(
                mutation: .reuseReturnedBHome
            )
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertTrue(result.issues[0].reason.contains("started after stop-keyed-manual-view"))
    }

    func testSameKeyManualTwoSceneRejectsReusedAHome() throws {
        let scenario = try scenario(
            named: "swiftui.coexistence.same-key-manual-two-scenes"
        )

        let result = ProbeSemanticOracle.evaluate(
            scenario: scenario,
            signals: sameKeyManualTwoSceneSignals(
                mutation: .reuseReturnedAHome
            )
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertTrue(result.issues[0].reason.contains("started after stop-keyed-manual-view"))
    }

    func testSiblingContainerAuthorityContractPasses() throws {
        let scenario = try scenario(
            named: "swiftui.coexistence.sibling-container-authority"
        )

        let result = ProbeSemanticOracle.evaluate(
            scenario: scenario,
            signals: siblingContainerAuthoritySignals()
        )

        XCTAssertEqual(
            result.state,
            .pass,
            result.issues.map(\.reason).joined(separator: "\n")
        )
    }

    func testSemanticSiblingContainerIsolationContractPasses() throws {
        let scenario = try scenario(
            named: "swiftui.semantic-api.sibling-container-isolation"
        )

        let result = ProbeSemanticOracle.evaluate(
            scenario: scenario,
            signals: siblingContainerAuthoritySignals(semanticUnderlying: true)
        )

        XCTAssertEqual(
            result.state,
            .pass,
            result.issues.map(\.reason).joined(separator: "\n")
        )
    }

    func testSemanticSiblingContainerIsolationRejectsAutomaticDuplicate() throws {
        let scenario = try scenario(
            named: "swiftui.semantic-api.sibling-container-isolation"
        )

        let result = ProbeSemanticOracle.evaluate(
            scenario: scenario,
            signals: siblingContainerAuthoritySignals(
                semanticUnderlying: true,
                includesAutomaticDuplicate: true
            )
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertTrue(result.issues[0].reason.contains("forbidden no-view-started"))
    }

    func testSiblingContainerAuthorityRejectsReusedUnderlyingHome() throws {
        let scenario = try scenario(
            named: "swiftui.coexistence.sibling-container-authority"
        )

        let result = ProbeSemanticOracle.evaluate(
            scenario: scenario,
            signals: siblingContainerAuthoritySignals(mutation: .reuseInitialHome)
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertTrue(result.issues[0].reason.contains("started after stop-keyed-manual-view"))
    }

    func testSiblingContainerAuthorityRejectsWrongManualOwner() throws {
        let scenario = try scenario(
            named: "swiftui.coexistence.sibling-container-authority"
        )

        let result = ProbeSemanticOracle.evaluate(
            scenario: scenario,
            signals: siblingContainerAuthoritySignals(mutation: .manualWorkUsesHome)
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertTrue(result.issues[0].reason.contains("semantic RUM view"))
    }

    func testSiblingContainerAuthorityRejectsGenericFallback() throws {
        let scenario = try scenario(
            named: "swiftui.coexistence.sibling-container-authority"
        )

        let result = ProbeSemanticOracle.evaluate(
            scenario: scenario,
            signals: siblingContainerAuthoritySignals(mutation: .revealGenericFallback)
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertTrue(
            result.issues[0].reason.contains(
                "rum-view-name=AutoTracked_HostingController_Fallback"
            )
        )
    }

    func testSiblingContainerAuthorityRejectsDifferentSettledOwner() throws {
        let scenario = try scenario(
            named: "swiftui.coexistence.sibling-container-authority"
        )

        let result = ProbeSemanticOracle.evaluate(
            scenario: scenario,
            signals: siblingContainerAuthoritySignals(mutation: .changeSettledOwner)
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertTrue(result.issues[0].reason.contains("observed different"))
    }

    func testUIKitScrollNavigationAttributionContractPasses() throws {
        let result = ProbeSemanticOracle.evaluate(
            scenario: try scenario(
                named: "actions.uikit-scroll-navigation-deceleration"
            ),
            signals: uikitScrollNavigationSignals()
        )

        XCTAssertEqual(
            result.state,
            .pass,
            result.issues.map(\.reason).joined(separator: "\n")
        )
    }

    func testUIKitScrollNavigationRejectsActionMigratingToDestination() throws {
        let result = ProbeSemanticOracle.evaluate(
            scenario: try scenario(
                named: "actions.uikit-scroll-navigation-deceleration"
            ),
            signals: uikitScrollNavigationSignals(mutation: .moveActionToDestination)
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertTrue(result.issues[0].reason.contains("observed secondary-3"))
    }

    func testUIKitScrollNavigationRejectsDuplicateOriginAction() throws {
        let result = ProbeSemanticOracle.evaluate(
            scenario: try scenario(
                named: "actions.uikit-scroll-navigation-deceleration"
            ),
            signals: uikitScrollNavigationSignals(mutation: .duplicateOriginAction)
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertTrue(result.issues[0].reason.contains("observed 2"))
    }

    func testUIKitScrollNavigationRejectsDuplicateDestinationAction() throws {
        let result = ProbeSemanticOracle.evaluate(
            scenario: try scenario(
                named: "actions.uikit-scroll-navigation-deceleration"
            ),
            signals: uikitScrollNavigationSignals(mutation: .duplicateDestinationAction)
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertTrue(result.issues[0].reason.contains("observed secondary-3"))
    }

    func testUIKitScrollNavigationRejectsWrongFinalActionType() throws {
        let result = ProbeSemanticOracle.evaluate(
            scenario: try scenario(
                named: "actions.uikit-scroll-navigation-deceleration"
            ),
            signals: uikitScrollNavigationSignals(mutation: .changeActionType)
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertTrue(result.issues[0].reason.contains("action type scroll"))
        XCTAssertTrue(result.issues[0].reason.contains("observed swipe"))
    }

    func testUIKitScrollNavigationRejectsIncorrectSourceProvenance() throws {
        let result = ProbeSemanticOracle.evaluate(
            scenario: try scenario(
                named: "actions.uikit-scroll-navigation-deceleration"
            ),
            signals: uikitScrollNavigationSignals(mutation: .changeSourceScreen)
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertTrue(result.issues[0].reason.contains("from screen secondary-2"))
    }

    func testUIKitScrollNavigationRejectsReusedDestinationViewID() throws {
        let result = ProbeSemanticOracle.evaluate(
            scenario: try scenario(
                named: "actions.uikit-scroll-navigation-deceleration"
            ),
            signals: uikitScrollNavigationSignals(mutation: .reuseDestinationViewID)
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertTrue(result.issues[0].reason.contains("maps to both"))
    }

    func testTraceOnlyURLSessionCrossSceneAttributionContractPasses() throws {
        let result = ProbeSemanticOracle.evaluate(
            scenario: try scenario(named: "traces.urlsession-cross-scene"),
            signals: traceOnlyURLSessionSignals()
        )

        XCTAssertEqual(
            result.state,
            .pass,
            result.issues.map(\.reason).joined(separator: "\n")
        )
    }

    func testTraceOnlyURLSessionRejectsCompletionRepresentativeAsOwner() throws {
        let result = ProbeSemanticOracle.evaluate(
            scenario: try scenario(named: "traces.urlsession-cross-scene"),
            signals: traceOnlyURLSessionSignals(mutation: .moveTraceToSceneB)
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertTrue(result.issues[0].reason.contains("observed scene-B"))
    }

    func testTraceOnlyURLSessionRejectsMissingSpan() throws {
        let result = ProbeSemanticOracle.evaluate(
            scenario: try scenario(named: "traces.urlsession-cross-scene"),
            signals: traceOnlyURLSessionSignals(mutation: .omitTrace)
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertTrue(result.issues[0].reason.contains("missing expected trace"))
    }

    func testTraceOnlyURLSessionRejectsDuplicateSpan() throws {
        let result = ProbeSemanticOracle.evaluate(
            scenario: try scenario(named: "traces.urlsession-cross-scene"),
            signals: traceOnlyURLSessionSignals(mutation: .duplicateTrace)
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertTrue(result.issues[0].reason.contains("observed 2"))
    }

    func testTraceOnlyURLSessionReverseCompletionContractPasses() throws {
        let result = ProbeSemanticOracle.evaluate(
            scenario: try scenario(named: "traces.urlsession-reverse-completion"),
            signals: traceOnlyURLSessionReverseCompletionSignals()
        )

        XCTAssertEqual(
            result.state,
            .pass,
            result.issues.map(\.reason).joined(separator: "\n")
        )
    }

    func testTraceOnlyURLSessionReverseCompletionRejectsSwappedOwners() throws {
        let result = ProbeSemanticOracle.evaluate(
            scenario: try scenario(named: "traces.urlsession-reverse-completion"),
            signals: traceOnlyURLSessionReverseCompletionSignals(
                mutation: .swapTraceOwners
            )
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertTrue(result.issues[0].reason.contains("observed scene-A"))
    }

    func testTraceOnlyURLSessionReverseCompletionRejectsMissingSceneBSpan() throws {
        let result = ProbeSemanticOracle.evaluate(
            scenario: try scenario(named: "traces.urlsession-reverse-completion"),
            signals: traceOnlyURLSessionReverseCompletionSignals(
                mutation: .omitSceneBTrace
            )
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertTrue(result.issues[0].reason.contains("missing expected trace"))
    }

    func testTraceOnlyURLSessionReverseCompletionRejectsDuplicateSceneASpan() throws {
        let result = ProbeSemanticOracle.evaluate(
            scenario: try scenario(named: "traces.urlsession-reverse-completion"),
            signals: traceOnlyURLSessionReverseCompletionSignals(
                mutation: .duplicateSceneATrace
            )
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertTrue(result.issues[0].reason.contains("observed 2"))
    }

    func testTraceOnlySharedRequestContractPasses() throws {
        let result = ProbeSemanticOracle.evaluate(
            scenario: try scenario(named: "traces.urlsession-shared-request"),
            signals: traceOnlySharedRequestSignals()
        )

        XCTAssertEqual(
            result.state,
            .pass,
            result.issues.map(\.reason).joined(separator: "\n")
        )
    }

    func testTraceOnlySharedRequestRejectsJoiningSceneAsOwner() throws {
        let result = ProbeSemanticOracle.evaluate(
            scenario: try scenario(named: "traces.urlsession-shared-request"),
            signals: traceOnlySharedRequestSignals(mutation: .moveTraceToSceneB)
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertTrue(result.issues[0].reason.contains("observed scene-B"))
    }

    func testTraceOnlySharedRequestRejectsMissingSpan() throws {
        let result = ProbeSemanticOracle.evaluate(
            scenario: try scenario(named: "traces.urlsession-shared-request"),
            signals: traceOnlySharedRequestSignals(mutation: .omitTrace)
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertTrue(result.issues[0].reason.contains("missing expected trace"))
    }

    func testTraceOnlySharedRequestRejectsDuplicateSpan() throws {
        let result = ProbeSemanticOracle.evaluate(
            scenario: try scenario(named: "traces.urlsession-shared-request"),
            signals: traceOnlySharedRequestSignals(mutation: .duplicateTrace)
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertTrue(result.issues[0].reason.contains("observed 2"))
    }

    func testSwiftUIButtonStructuredTaskContractPasses() throws {
        let result = ProbeSemanticOracle.evaluate(
            scenario: try scenario(named: "actions.swiftui-button-structured-task"),
            signals: swiftUIButtonStructuredTaskSignals()
        )

        XCTAssertEqual(
            result.state,
            .pass,
            result.issues.map(\.reason).joined(separator: "\n")
        )
    }

    func testSwiftUIButtonStructuredTaskRejectsResumedWorkOnSceneB() throws {
        let result = ProbeSemanticOracle.evaluate(
            scenario: try scenario(named: "actions.swiftui-button-structured-task"),
            signals: swiftUIButtonStructuredTaskSignals(
                mutation: .resumeOnSceneB
            )
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertTrue(result.issues[0].reason.contains("observed scene-B"))
    }

    func testSwiftUIButtonStructuredTaskRejectsMissingAutomaticTap() throws {
        let result = ProbeSemanticOracle.evaluate(
            scenario: try scenario(named: "actions.swiftui-button-structured-task"),
            signals: swiftUIButtonStructuredTaskSignals(
                mutation: .omitAutomaticTap
            )
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertTrue(result.issues[0].reason.contains("observed 0"))
    }

    func testSwiftUIButtonStructuredTaskRejectsDuplicateResumedWork() throws {
        let result = ProbeSemanticOracle.evaluate(
            scenario: try scenario(named: "actions.swiftui-button-structured-task"),
            signals: swiftUIButtonStructuredTaskSignals(
                mutation: .duplicateResumedWork
            )
        )

        XCTAssertEqual(result.state, .fail)
        XCTAssertTrue(result.issues[0].reason.contains("observed 2"))
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
        active: Bool,
        scene: String = "scene-A",
        nativeSceneID: String = "native-A"
    ) -> ProbeSignal {
        ProbeSignal(
            kind: .rumViewSnapshot,
            evidenceSource: .rumMapper,
            semanticContext: ProbeSemanticContext(
                logicalSceneID: scene,
                nativeSceneID: nativeSceneID,
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
                eventID: name,
                name: name,
                action: ProbeActionSignal(
                    id: name,
                    type: "tap",
                    target: name,
                    loadingTimeNanoseconds: 1
                )
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

    private enum NestedKeyedManualMutation {
        case reuseFirstComposeOnReveal
        case startViewDuringDuplicate
        case resumedWorkUsesFirstCompose
        case reuseInitialHomeOnReturn
    }

    private enum SameKeyManualTwoSceneMutation {
        case reuseComposeViewIDAcrossScenes
        case attributeBWorkToACompose
        case stopAWhenBStops
        case reuseReturnedBHome
        case reuseReturnedAHome
    }

    private enum OperationCrossSceneMutation {
        case reuseViewIDAcrossScenes
        case attributeBHomeToA
        case attributeBCompletionToA
        case changeAOwnerAfterBCompletion
    }

    private enum SiblingContainerAuthorityMutation {
        case reuseInitialHome
        case manualWorkUsesHome
        case revealGenericFallback
        case changeSettledOwner
    }

    private enum UIKitScrollNavigationMutation {
        case moveActionToDestination
        case duplicateOriginAction
        case duplicateDestinationAction
        case changeActionType
        case changeSourceScreen
        case reuseDestinationViewID
    }

    private enum TraceOnlyURLSessionMutation: Equatable {
        case moveTraceToSceneB
        case omitTrace
        case duplicateTrace
    }

    private enum TraceOnlyURLSessionReverseCompletionMutation {
        case swapTraceOwners
        case omitSceneBTrace
        case duplicateSceneATrace
    }

    private enum SwiftUIButtonStructuredTaskMutation {
        case resumeOnSceneB
        case omitAutomaticTap
        case duplicateResumedWork
    }

    private func traceOnlyURLSessionSignals(
        mutation: TraceOnlyURLSessionMutation? = nil
    ) -> [ProbeSignal] {
        let recorder = ProbeEventRecorder(
            runID: "trace-only-cross-scene-contract",
            scenarioID: "traces.urlsession-cross-scene",
            sink: { _ in },
            clock: { 42 }
        )
        let sceneAViewID = "scene-A-home-1"
        let sceneBViewID = "scene-B-home-1"

        recorder.record(
            viewSignal(
                id: sceneAViewID,
                screen: "home",
                active: true,
                scene: "scene-A",
                nativeSceneID: "native-A"
            )
        )
        recordTraceRepresentativeMarker(
            name: "trace-request-representative",
            scene: "scene-A",
            nativeSceneID: "native-A",
            viewID: sceneAViewID,
            recorder: recorder
        )
        recorder.record(
            viewSignal(
                id: sceneBViewID,
                screen: "home",
                active: true,
                scene: "scene-B",
                nativeSceneID: "native-B"
            )
        )
        recordTraceRepresentativeMarker(
            name: "trace-completion-representative",
            scene: "scene-B",
            nativeSceneID: "native-B",
            viewID: sceneBViewID,
            recorder: recorder
        )

        guard mutation != .omitTrace else {
            return recorder.snapshot()
        }
        let traceOwner = mutation == .moveTraceToSceneB
            ? sceneBViewID
            : sceneAViewID
        recordTraceOnlyURLSessionSignal(
            viewID: traceOwner,
            recorder: recorder
        )
        if mutation == .duplicateTrace {
            recordTraceOnlyURLSessionSignal(
                viewID: sceneAViewID,
                recorder: recorder
            )
        }
        return recorder.snapshot()
    }

    private func traceOnlyURLSessionReverseCompletionSignals(
        mutation: TraceOnlyURLSessionReverseCompletionMutation? = nil
    ) -> [ProbeSignal] {
        let recorder = ProbeEventRecorder(
            runID: "trace-only-reverse-completion-contract",
            scenarioID: "traces.urlsession-reverse-completion",
            sink: { _ in },
            clock: { 42 }
        )
        let sceneAViewID = "scene-A-home-1"
        let sceneBViewID = "scene-B-home-1"

        recorder.record(
            viewSignal(
                id: sceneAViewID,
                screen: "home",
                active: true,
                scene: "scene-A",
                nativeSceneID: "native-A"
            )
        )
        recordTraceRepresentativeMarker(
            name: "trace-reverse-a-start-representative",
            scene: "scene-A",
            nativeSceneID: "native-A",
            viewID: sceneAViewID,
            recorder: recorder
        )
        recorder.record(
            viewSignal(
                id: sceneBViewID,
                screen: "home",
                active: true,
                scene: "scene-B",
                nativeSceneID: "native-B"
            )
        )
        recordTraceRepresentativeMarker(
            name: "trace-reverse-b-start-representative",
            scene: "scene-B",
            nativeSceneID: "native-B",
            viewID: sceneBViewID,
            recorder: recorder
        )
        recordTraceRepresentativeMarker(
            name: "trace-reverse-b-completion-representative",
            scene: "scene-A",
            nativeSceneID: "native-A",
            viewID: sceneAViewID,
            recorder: recorder
        )
        if mutation != .omitSceneBTrace {
            recordTraceOnlyURLSessionSignal(
                requestName: ProbeTraceOnlyURLSessionContract.reverseSceneBRequestName,
                sourceScene: "scene-B",
                sourceNativeSceneID: "native-B",
                viewID: mutation == .swapTraceOwners
                    ? sceneAViewID
                    : sceneBViewID,
                recorder: recorder
            )
        }
        recordTraceRepresentativeMarker(
            name: "trace-reverse-a-completion-representative",
            scene: "scene-B",
            nativeSceneID: "native-B",
            viewID: sceneBViewID,
            recorder: recorder
        )
        recordTraceOnlyURLSessionSignal(
            requestName: ProbeTraceOnlyURLSessionContract.reverseSceneARequestName,
            sourceScene: "scene-A",
            sourceNativeSceneID: "native-A",
            viewID: mutation == .swapTraceOwners
                ? sceneBViewID
                : sceneAViewID,
            recorder: recorder
        )
        if mutation == .duplicateSceneATrace {
            recordTraceOnlyURLSessionSignal(
                requestName: ProbeTraceOnlyURLSessionContract.reverseSceneARequestName,
                sourceScene: "scene-A",
                sourceNativeSceneID: "native-A",
                viewID: sceneAViewID,
                recorder: recorder
            )
        }
        return recorder.snapshot()
    }

    private func traceOnlySharedRequestSignals(
        mutation: TraceOnlyURLSessionMutation? = nil
    ) -> [ProbeSignal] {
        let recorder = ProbeEventRecorder(
            runID: "trace-only-shared-request-contract",
            scenarioID: "traces.urlsession-shared-request",
            sink: { _ in },
            clock: { 42 }
        )
        let sceneAViewID = "scene-A-home-1"
        let sceneBViewID = "scene-B-home-1"

        recorder.record(
            viewSignal(
                id: sceneAViewID,
                screen: "home",
                active: true,
                scene: "scene-A",
                nativeSceneID: "native-A"
            )
        )
        recordTraceRepresentativeMarker(
            name: "trace-shared-creator-representative",
            scene: "scene-A",
            nativeSceneID: "native-A",
            viewID: sceneAViewID,
            recorder: recorder
        )
        recorder.record(
            viewSignal(
                id: sceneBViewID,
                screen: "home",
                active: true,
                scene: "scene-B",
                nativeSceneID: "native-B"
            )
        )
        recordTraceRepresentativeMarker(
            name: "trace-shared-consumer-representative",
            scene: "scene-B",
            nativeSceneID: "native-B",
            viewID: sceneBViewID,
            recorder: recorder
        )

        guard mutation != .omitTrace else {
            return recorder.snapshot()
        }
        recordTraceOnlyURLSessionSignal(
            requestName: ProbeTraceOnlyURLSessionContract.sharedRequestName,
            sourceScene: "scene-A",
            sourceNativeSceneID: "native-A",
            viewID: mutation == .moveTraceToSceneB
                ? sceneBViewID
                : sceneAViewID,
            recorder: recorder
        )
        if mutation == .duplicateTrace {
            recordTraceOnlyURLSessionSignal(
                requestName: ProbeTraceOnlyURLSessionContract.sharedRequestName,
                sourceScene: "scene-A",
                sourceNativeSceneID: "native-A",
                viewID: sceneAViewID,
                recorder: recorder
            )
        }
        return recorder.snapshot()
    }

    private func swiftUIButtonStructuredTaskSignals(
        mutation: SwiftUIButtonStructuredTaskMutation? = nil
    ) -> [ProbeSignal] {
        let recorder = ProbeEventRecorder(
            runID: "swiftui-button-structured-task-contract",
            scenarioID: "actions.swiftui-button-structured-task",
            sink: { _ in },
            clock: { 42 }
        )
        let sceneAViewID = "scene-A-home-1"
        let sceneBViewID = "scene-B-home-1"

        recorder.record(
            viewSignal(
                id: sceneAViewID,
                screen: "home",
                active: true,
                scene: "scene-A",
                nativeSceneID: "native-A"
            )
        )
        if mutation != .omitAutomaticTap {
            recordAutomaticAction(
                name: ProbeSwiftUIButtonStructuredTaskContract.automaticActionName,
                viewID: sceneAViewID,
                recorder: recorder
            )
        }
        recorder.record(
            viewSignal(
                id: sceneBViewID,
                screen: "home",
                active: true,
                scene: "scene-B",
                nativeSceneID: "native-B"
            )
        )
        recordTraceRepresentativeMarker(
            name: ProbeSwiftUIButtonStructuredTaskContract.representativeMarker,
            scene: "scene-B",
            nativeSceneID: "native-B",
            viewID: sceneBViewID,
            recorder: recorder
        )
        recordTraceRepresentativeMarker(
            name: ProbeSwiftUIButtonStructuredTaskContract.resumedMarker,
            scene: "scene-A",
            nativeSceneID: "native-A",
            viewID: mutation == .resumeOnSceneB ? sceneBViewID : sceneAViewID,
            recorder: recorder
        )
        if mutation == .duplicateResumedWork {
            recordTraceRepresentativeMarker(
                name: ProbeSwiftUIButtonStructuredTaskContract.resumedMarker,
                scene: "scene-A",
                nativeSceneID: "native-A",
                viewID: sceneAViewID,
                recorder: recorder
            )
        }
        return recorder.snapshot()
    }

    private func recordTraceRepresentativeMarker(
        name: String,
        scene: String,
        nativeSceneID: String,
        viewID: String,
        recorder: ProbeEventRecorder
    ) {
        for kind in [ProbeSignalKind.rumAction, .rumResource] {
            recorder.record(
                ProbeSignal(
                    kind: kind,
                    evidenceSource: .rumMapper,
                    sourceContext: ProbeSourceContext(
                        logicalSceneID: scene,
                        nativeSceneID: nativeSceneID,
                        screen: "home",
                        phase: name
                    ),
                    rumContext: ProbeRUMContext(
                        sessionID: "session",
                        viewID: viewID
                    ),
                    eventID: "\(scene)-\(kind.rawValue)-\(name)",
                    name: name
                )
            )
        }
    }

    private func recordTraceOnlyURLSessionSignal(
        viewID: String,
        recorder: ProbeEventRecorder
    ) {
        recordTraceOnlyURLSessionSignal(
            requestName: ProbeTraceOnlyURLSessionContract.requestName,
            sourceScene: "scene-A",
            sourceNativeSceneID: "native-A",
            viewID: viewID,
            recorder: recorder
        )
    }

    private func recordTraceOnlyURLSessionSignal(
        requestName: String,
        sourceScene: String,
        sourceNativeSceneID: String,
        viewID: String,
        recorder: ProbeEventRecorder
    ) {
        recorder.record(
            ProbeSignal(
                kind: .rumTrace,
                evidenceSource: .traceMapper,
                sourceContext: ProbeSourceContext(
                    logicalSceneID: sourceScene,
                    nativeSceneID: sourceNativeSceneID,
                    screen: "home",
                    phase: requestName
                ),
                rumContext: ProbeRUMContext(
                    sessionID: "session",
                    viewID: viewID
                ),
                name: requestName,
                trace: ProbeTraceSignal(
                    operationName: "urlsession.request",
                    serviceName: "ios-sdk-native-multi-scene-probe",
                    resourceName: "https://multi-scene-probe.invalid/trace-only/\(requestName)",
                    startTimeMilliseconds: 42,
                    durationNanoseconds: 1,
                    isError: false,
                    rumSessionID: "session",
                    rumViewID: viewID,
                    rumActionIDs: nil
                )
            )
        )
    }

    private func uikitScrollNavigationSignals(
        mutation: UIKitScrollNavigationMutation? = nil
    ) -> [ProbeSignal] {
        let recorder = ProbeEventRecorder(
            runID: "uikit-scroll-navigation-contract",
            scenarioID: "actions.uikit-scroll-navigation-deceleration",
            sink: { _ in },
            clock: { 42 }
        )
        let originViewID = "secondary-2-view"
        let destinationViewID = mutation == .reuseDestinationViewID
            ? originViewID
            : "secondary-3-view"

        recorder.record(
            viewSignal(
                id: originViewID,
                screen: "secondary-2",
                active: true
            )
        )
        recorder.record(
            ProbeSignal(
                kind: .intervalBegan,
                semanticContext: ProbeSemanticContext(
                    logicalSceneID: "scene-A",
                    nativeSceneID: "native-A",
                    screen: "secondary-2",
                    occurrence: 1
                ),
                interval: "uikit-scroll-after-navigation"
            )
        )

        recordUIKitScrollAction(
            id: "scroll-origin",
            viewID: mutation == .moveActionToDestination
                ? destinationViewID
                : originViewID,
            sourceScreen: mutation == .changeSourceScreen
                ? "secondary-3"
                : "secondary-2",
            actionType: mutation == .changeActionType ? "swipe" : "scroll",
            recorder: recorder
        )
        if mutation == .duplicateOriginAction {
            recordUIKitScrollAction(
                id: "scroll-origin-duplicate",
                viewID: originViewID,
                sourceScreen: "secondary-2",
                actionType: "scroll",
                recorder: recorder
            )
        }

        recorder.record(
            viewSignal(
                id: originViewID,
                screen: "secondary-2",
                active: false
            )
        )
        recorder.record(
            viewSignal(
                id: destinationViewID,
                screen: "secondary-3",
                active: true
            )
        )
        if mutation == .duplicateDestinationAction {
            recordUIKitScrollAction(
                id: "scroll-destination-duplicate",
                viewID: destinationViewID,
                sourceScreen: "secondary-2",
                actionType: "scroll",
                recorder: recorder
            )
        }
        recorder.record(
            workSignal(
                kind: .rumAction,
                id: "destination-marker-action",
                name: "post-scroll-navigation",
                viewID: destinationViewID,
                screen: "secondary-3",
                occurrence: 1
            )
        )
        recorder.record(
            workSignal(
                kind: .rumResource,
                id: "destination-marker-resource",
                name: "post-scroll-navigation",
                viewID: destinationViewID,
                screen: "secondary-3",
                occurrence: 1
            )
        )
        recorder.record(
            ProbeSignal(
                kind: .intervalEnded,
                semanticContext: ProbeSemanticContext(
                    logicalSceneID: "scene-A",
                    nativeSceneID: "native-A",
                    screen: "secondary-3",
                    occurrence: 1
                ),
                interval: "uikit-scroll-after-navigation"
            )
        )
        return recorder.snapshot()
    }

    private func recordUIKitScrollAction(
        id: String,
        viewID: String,
        sourceScreen: String,
        actionType: String,
        recorder: ProbeEventRecorder
    ) {
        recorder.record(
            ProbeSignal(
                kind: .rumAction,
                evidenceSource: .rumMapper,
                sourceContext: ProbeSourceContext(
                    logicalSceneID: "scene-A",
                    nativeSceneID: "native-A",
                    screen: sourceScreen,
                    phase: "uikit-scroll-origin"
                ),
                rumContext: ProbeRUMContext(
                    sessionID: "session",
                    viewID: viewID
                ),
                eventID: id,
                name: "uikit-scroll-origin",
                action: ProbeActionSignal(
                    id: id,
                    type: actionType,
                    target: "uikit-scroll-origin",
                    loadingTimeNanoseconds: 100
                )
            )
        )
    }

    private func siblingContainerAuthoritySignals(
        mutation: SiblingContainerAuthorityMutation? = nil,
        semanticUnderlying: Bool = false,
        includesAutomaticDuplicate: Bool = false
    ) -> [ProbeSignal] {
        let recorder = ProbeEventRecorder(
            runID: "sibling-container-authority-contract",
            scenarioID: semanticUnderlying
                ? "swiftui.semantic-api.sibling-container-isolation"
                : "swiftui.coexistence.sibling-container-authority",
            sink: { _ in },
            clock: { 42 }
        )

        recorder.record(
            ProbeSignal(
                kind: .intervalBegan,
                interval: "sibling-container-observation"
            )
        )
        recordSiblingUnderlyingView(
            id: "home-1",
            screen: "home",
            semantic: semanticUnderlying,
            recorder: recorder
        )
        if includesAutomaticDuplicate {
            recordAutomaticView(id: "automatic-duplicate", recorder: recorder)
        }
        for kind in [ProbeSignalKind.rumAction, .rumResource] {
            recorder.record(
                keyedManualWorkSignal(
                    kind: kind,
                    name: "sibling-home-before-authority",
                    viewID: "home-1",
                    sourceScreen: "home"
                )
            )
        }
        recorder.record(
            ProbeSignal(
                kind: .stepStarted,
                stepKind: .startKeyedManualView,
                name: "sibling-authority"
            )
        )
        recorder.record(
            ProbeSignal(
                kind: .intervalBegan,
                interval: "manual-sibling-authority"
            )
        )
        recorder.record(
            viewSignal(
                id: "sibling-authority",
                screen: "sibling-authority",
                active: true
            )
        )
        recordSiblingUnderlyingView(
            id: "home-1",
            screen: "home",
            active: false,
            semantic: semanticUnderlying,
            recorder: recorder
        )

        let manualOwner = mutation == .manualWorkUsesHome
            ? "home-1"
            : "sibling-authority"
        for (name, sourceScreen) in [
            ("sibling-authority-active", "sibling-authority"),
            ("task-delayed", "detail-1"),
            ("sibling-underlying-detail-active", "detail-1")
        ] {
            for kind in [ProbeSignalKind.rumAction, .rumResource] {
                recorder.record(
                    keyedManualWorkSignal(
                        kind: kind,
                        name: name,
                        viewID: manualOwner,
                        sourceScreen: sourceScreen
                    )
                )
            }
        }
        recorder.record(
            ProbeSignal(
                kind: .assertion,
                name: "sibling-controller-topology",
                result: .pass,
                reason: "fixture exposes independent controller branches"
            )
        )
        recorder.record(
            ProbeSignal(
                kind: .stepStarted,
                stepKind: .stopKeyedManualView,
                name: "sibling-authority"
            )
        )
        recorder.record(
            ProbeSignal(
                kind: .intervalEnded,
                interval: "manual-sibling-authority"
            )
        )
        recorder.record(
            viewSignal(
                id: "sibling-authority",
                screen: "sibling-authority",
                active: false
            )
        )

        let revealedOwner: String
        if mutation == .reuseInitialHome {
            revealedOwner = "home-1"
        } else {
            revealedOwner = "detail-1"
            recordSiblingUnderlyingView(
                id: revealedOwner,
                screen: "detail-1",
                viewName: mutation == .revealGenericFallback
                    ? "AutoTracked_HostingController_Fallback"
                    : "NavigationStackHostingController",
                semantic: semanticUnderlying
                    && mutation != .revealGenericFallback,
                recorder: recorder
            )
        }
        for kind in [ProbeSignalKind.rumAction, .rumResource] {
            recorder.record(
                keyedManualWorkSignal(
                    kind: kind,
                    name: "sibling-authority-stopped-immediate",
                    viewID: revealedOwner,
                    sourceScreen: "detail-1"
                )
            )
        }

        let settledOwner: String
        if mutation == .changeSettledOwner {
            settledOwner = "detail-2"
            recordSiblingUnderlyingView(
                id: settledOwner,
                screen: "detail-2",
                semantic: semanticUnderlying,
                recorder: recorder
            )
        } else {
            settledOwner = revealedOwner
        }
        for kind in [ProbeSignalKind.rumAction, .rumResource] {
            recorder.record(
                keyedManualWorkSignal(
                    kind: kind,
                    name: "sibling-authority-stopped-settled",
                    viewID: settledOwner,
                    sourceScreen: "detail-1"
                )
            )
        }
        recorder.record(
            ProbeSignal(
                kind: .intervalEnded,
                interval: "sibling-container-observation"
            )
        )
        return recorder.snapshot()
    }

    private func recordSiblingUnderlyingView(
        id: String,
        screen: String,
        active: Bool = true,
        viewName: String = "NavigationStackHostingController",
        semantic: Bool,
        recorder: ProbeEventRecorder
    ) {
        if semantic {
            recorder.record(
                viewSignal(
                    id: id,
                    screen: screen,
                    active: active
                )
            )
        } else {
            recordAutomaticView(
                id: id,
                active: active,
                viewName: viewName,
                recorder: recorder
            )
        }
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
                interval: "keyed-manual-authority-scene-A"
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
                interval: "keyed-manual-authority-scene-A"
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

    private func nestedKeyedManualSignals(
        mutation: NestedKeyedManualMutation? = nil
    ) -> [ProbeSignal] {
        let recorder = ProbeEventRecorder(
            runID: "nested-keyed-manual-contract",
            scenarioID: "swiftui.coexistence.nested-keyed-manual-view",
            sink: { _ in },
            clock: { 42 }
        )

        recordAutomaticView(id: "home-1", recorder: recorder)
        for kind in [ProbeSignalKind.rumAction, .rumResource] {
            recorder.record(
                keyedManualWorkSignal(
                    kind: kind,
                    name: "automatic-home-before-nested-keyed-manual",
                    viewID: "home-1",
                    sourceScreen: "home"
                )
            )
        }
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
                interval: "keyed-manual-authority-scene-A"
            )
        )
        recorder.record(viewSignal(id: "compose-1", screen: "compose", active: true))
        recordAutomaticView(id: "home-1", active: false, recorder: recorder)
        for kind in [ProbeSignalKind.rumAction, .rumResource] {
            recorder.record(
                keyedManualWorkSignal(
                    kind: kind,
                    name: "nested-keyed-manual-compose-first-active",
                    viewID: "compose-1",
                    sourceScreen: "compose"
                )
            )
        }

        recorder.record(
            ProbeSignal(
                kind: .stepStarted,
                stepKind: .startKeyedManualView,
                name: "preview"
            )
        )
        recorder.record(viewSignal(id: "compose-1", screen: "compose", active: false))
        recorder.record(viewSignal(id: "preview-1", screen: "preview", active: true))
        for kind in [ProbeSignalKind.rumAction, .rumResource] {
            recorder.record(
                keyedManualWorkSignal(
                    kind: kind,
                    name: "nested-keyed-manual-preview-active",
                    viewID: "preview-1",
                    sourceScreen: "preview"
                )
            )
        }

        recorder.record(
            ProbeSignal(
                kind: .stepStarted,
                stepKind: .stopKeyedManualView,
                name: "preview"
            )
        )
        recorder.record(viewSignal(id: "preview-1", screen: "preview", active: false))
        let resumedComposeID = mutation == .reuseFirstComposeOnReveal
            ? "compose-1"
            : "compose-2"
        if mutation != .reuseFirstComposeOnReveal {
            recorder.record(
                viewSignal(id: resumedComposeID, screen: "compose", active: true)
            )
        }
        for name in [
            "keyed-manual-preview-stopped-immediate",
            "keyed-manual-preview-stopped-settled"
        ] {
            for kind in [ProbeSignalKind.rumAction, .rumResource] {
                recorder.record(
                    keyedManualWorkSignal(
                        kind: kind,
                        name: name,
                        viewID: resumedComposeID,
                        sourceScreen: "compose"
                    )
                )
            }
        }
        let resumedWorkOwner = mutation == .resumedWorkUsesFirstCompose
            ? "compose-1"
            : resumedComposeID
        for kind in [ProbeSignalKind.rumAction, .rumResource] {
            recorder.record(
                keyedManualWorkSignal(
                    kind: kind,
                    name: "nested-keyed-manual-compose-resumed",
                    viewID: resumedWorkOwner,
                    sourceScreen: "compose"
                )
            )
        }

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
                interval: "duplicate-keyed-manual-start-compose-scene-A"
            )
        )
        if mutation == .startViewDuringDuplicate {
            recorder.record(viewSignal(id: "compose-3", screen: "compose", active: true))
        }
        for kind in [ProbeSignalKind.rumAction, .rumResource] {
            recorder.record(
                keyedManualWorkSignal(
                    kind: kind,
                    name: "duplicate-keyed-manual-start-compose-scene-A",
                    viewID: resumedComposeID,
                    sourceScreen: "compose"
                )
            )
        }
        recorder.record(
            ProbeSignal(
                kind: .intervalEnded,
                interval: "duplicate-keyed-manual-start-compose-scene-A"
            )
        )
        recorder.record(
            ProbeSignal(
                kind: .assertion,
                name: "duplicate-keyed-manual-start-compose-scene-A",
                result: .pass,
                reason: "fixture duplicate start completed"
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
                interval: "keyed-manual-authority-scene-A"
            )
        )
        if mutation != .reuseFirstComposeOnReveal {
            recorder.record(
                viewSignal(id: resumedComposeID, screen: "compose", active: false)
            )
        }
        let returnedHomeID = mutation == .reuseInitialHomeOnReturn
            ? "home-1"
            : "home-2"
        if mutation != .reuseInitialHomeOnReturn {
            recordAutomaticView(id: returnedHomeID, recorder: recorder)
        }
        for name in [
            "keyed-manual-stopped-immediate",
            "keyed-manual-stopped-settled"
        ] {
            for kind in [ProbeSignalKind.rumAction, .rumResource] {
                recorder.record(
                    keyedManualWorkSignal(
                        kind: kind,
                        name: name,
                        viewID: returnedHomeID,
                        sourceScreen: "home"
                    )
                )
            }
        }
        return recorder.snapshot()
    }

    private func operationCrossSceneSignals(
        mutation: OperationCrossSceneMutation? = nil
    ) -> [ProbeSignal] {
        let recorder = ProbeEventRecorder(
            runID: "operation-cross-scene-contract",
            scenarioID: "operations.cross-scene.lifecycle",
            sink: { _ in },
            clock: { 42 }
        )

        func nativeSceneID(for scene: String) -> String {
            scene == "scene-A" ? "native-A" : "native-B"
        }

        func recordStep(
            _ kind: ProbeStepKind,
            scene: String,
            name: String
        ) {
            recorder.record(
                ProbeSignal(
                    kind: .stepStarted,
                    semanticContext: ProbeSemanticContext(
                        logicalSceneID: scene,
                        nativeSceneID: nativeSceneID(for: scene)
                    ),
                    stepKind: kind,
                    name: name
                )
            )
        }

        func recordWork(
            name: String,
            scene: String,
            viewID: String
        ) {
            for kind in [ProbeSignalKind.rumAction, .rumResource] {
                recorder.record(
                    keyedManualWorkSignal(
                        kind: kind,
                        name: name,
                        viewID: viewID,
                        sourceScreen: "home",
                        scene: scene,
                        nativeSceneID: nativeSceneID(for: scene)
                    )
                )
            }
        }

        func recordOperation(
            _ kind: ProbeStepKind,
            scene: String,
            instance: String,
            marker: String,
            viewID: String
        ) {
            recordStep(kind, scene: scene, name: instance)
            recordWork(name: marker, scene: scene, viewID: viewID)
        }

        let homeA = "operation-home-A"
        let homeB = mutation == .reuseViewIDAcrossScenes
            ? homeA
            : "operation-home-B"
        recorder.record(
            viewSignal(
                id: homeA,
                screen: "home",
                active: true,
                scene: "scene-A",
                nativeSceneID: "native-A"
            )
        )
        recordWork(
            name: "operation-cross-home-a",
            scene: "scene-A",
            viewID: homeA
        )
        recordStep(.openWindow, scene: "scene-A", name: "scene-B")
        recorder.record(
            viewSignal(
                id: homeB,
                screen: "home",
                active: true,
                scene: "scene-B",
                nativeSceneID: "native-B"
            )
        )
        recordWork(
            name: "operation-cross-home-b",
            scene: "scene-B",
            viewID: mutation == .attributeBHomeToA ? homeA : homeB
        )

        recordOperation(
            .startOperation,
            scene: "scene-A",
            instance: "cross-success",
            marker: "operation-cross-success-start-a",
            viewID: homeA
        )
        recordOperation(
            .succeedOperation,
            scene: "scene-B",
            instance: "cross-success",
            marker: "operation-cross-success-end-b",
            viewID: mutation == .attributeBCompletionToA ? homeA : homeB
        )
        recordOperation(
            .startOperation,
            scene: "scene-A",
            instance: "cross-failure",
            marker: "operation-cross-failure-start-a",
            viewID: homeA
        )
        recordOperation(
            .failOperation,
            scene: "scene-B",
            instance: "cross-failure",
            marker: "operation-cross-failure-end-b",
            viewID: homeB
        )
        recordOperation(
            .startOperation,
            scene: "scene-A",
            instance: "parallel-alpha",
            marker: "operation-parallel-alpha-start-a",
            viewID: homeA
        )
        recordOperation(
            .startOperation,
            scene: "scene-B",
            instance: "parallel-beta",
            marker: "operation-parallel-beta-start-b",
            viewID: homeB
        )
        recordOperation(
            .succeedOperation,
            scene: "scene-B",
            instance: "parallel-beta",
            marker: "operation-parallel-beta-end-b",
            viewID: homeB
        )

        let finalAOwner: String
        if mutation == .changeAOwnerAfterBCompletion {
            recorder.record(
                viewSignal(
                    id: homeA,
                    screen: "home",
                    active: false,
                    scene: "scene-A",
                    nativeSceneID: "native-A"
                )
            )
            finalAOwner = "operation-home-A-2"
            recorder.record(
                viewSignal(
                    id: finalAOwner,
                    screen: "home",
                    active: true,
                    scene: "scene-A",
                    nativeSceneID: "native-A"
                )
            )
        } else {
            finalAOwner = homeA
        }
        recordOperation(
            .succeedOperation,
            scene: "scene-A",
            instance: "parallel-alpha",
            marker: "operation-parallel-alpha-end-a",
            viewID: finalAOwner
        )
        return recorder.snapshot()
    }

    private func sameKeyManualTwoSceneSignals(
        mutation: SameKeyManualTwoSceneMutation? = nil
    ) -> [ProbeSignal] {
        let recorder = ProbeEventRecorder(
            runID: "same-key-manual-two-scenes-contract",
            scenarioID: "swiftui.coexistence.same-key-manual-two-scenes",
            sink: { _ in },
            clock: { 42 }
        )

        func recordStep(
            _ kind: ProbeStepKind,
            scene: String,
            name: String
        ) {
            recorder.record(
                ProbeSignal(
                    kind: .stepStarted,
                    semanticContext: ProbeSemanticContext(
                        logicalSceneID: scene,
                        nativeSceneID: scene == "scene-A" ? "native-A" : "native-B"
                    ),
                    stepKind: kind,
                    name: name
                )
            )
        }

        func recordWork(
            name: String,
            scene: String,
            screen: String,
            viewID: String
        ) {
            for kind in [ProbeSignalKind.rumAction, .rumResource] {
                recorder.record(
                    keyedManualWorkSignal(
                        kind: kind,
                        name: name,
                        viewID: viewID,
                        sourceScreen: screen,
                        scene: scene,
                        nativeSceneID: scene == "scene-A" ? "native-A" : "native-B"
                    )
                )
            }
        }

        recordAutomaticView(id: "home-A-1", recorder: recorder)
        recordWork(
            name: "same-key-home-a-before-manual",
            scene: "scene-A",
            screen: "home",
            viewID: "home-A-1"
        )
        recordStep(.openWindow, scene: "scene-A", name: "scene-B")
        recordAutomaticView(id: "home-B-1", recorder: recorder)
        recordWork(
            name: "same-key-home-b-before-manual",
            scene: "scene-B",
            screen: "home",
            viewID: "home-B-1"
        )

        recordStep(.startKeyedManualView, scene: "scene-A", name: "compose")
        recorder.record(
            ProbeSignal(
                kind: .intervalBegan,
                interval: "keyed-manual-authority-scene-A"
            )
        )
        recorder.record(
            viewSignal(
                id: "compose-A",
                screen: "compose",
                active: true,
                scene: "scene-A",
                nativeSceneID: "native-A"
            )
        )
        recordAutomaticView(id: "home-A-1", active: false, recorder: recorder)
        recordWork(
            name: "same-key-compose-a-active",
            scene: "scene-A",
            screen: "compose",
            viewID: "compose-A"
        )

        recordStep(.startKeyedManualView, scene: "scene-B", name: "compose")
        recorder.record(
            ProbeSignal(
                kind: .intervalBegan,
                interval: "keyed-manual-authority-scene-B"
            )
        )
        let composeBID = mutation == .reuseComposeViewIDAcrossScenes
            ? "compose-A"
            : "compose-B"
        recorder.record(
            viewSignal(
                id: composeBID,
                screen: "compose",
                active: true,
                scene: "scene-B",
                nativeSceneID: "native-B"
            )
        )
        recordAutomaticView(id: "home-B-1", active: false, recorder: recorder)
        recordWork(
            name: "same-key-compose-b-active",
            scene: "scene-B",
            screen: "compose",
            viewID: mutation == .attributeBWorkToACompose
                ? "compose-A"
                : composeBID
        )

        recordStep(.stopKeyedManualView, scene: "scene-B", name: "compose")
        recorder.record(
            ProbeSignal(
                kind: .intervalEnded,
                interval: "keyed-manual-authority-scene-B"
            )
        )
        recorder.record(
            viewSignal(
                id: composeBID,
                screen: "compose",
                active: false,
                scene: "scene-B",
                nativeSceneID: "native-B"
            )
        )
        let returnedBID: String
        if mutation == .reuseReturnedBHome {
            returnedBID = "home-B-1"
        } else {
            returnedBID = "home-B-2"
            recordAutomaticView(id: returnedBID, recorder: recorder)
        }
        recordWork(
            name: "same-key-home-b-returned",
            scene: "scene-B",
            screen: "home",
            viewID: returnedBID
        )

        let aAfterBStopOwner: String
        if mutation == .stopAWhenBStops {
            recorder.record(
                viewSignal(
                    id: "compose-A",
                    screen: "compose",
                    active: false,
                    scene: "scene-A",
                    nativeSceneID: "native-A"
                )
            )
            aAfterBStopOwner = "home-A-2"
            recordAutomaticView(id: aAfterBStopOwner, recorder: recorder)
        } else {
            aAfterBStopOwner = "compose-A"
        }
        recordWork(
            name: "same-key-compose-a-after-b-stop",
            scene: "scene-A",
            screen: "compose",
            viewID: aAfterBStopOwner
        )

        recordStep(.stopKeyedManualView, scene: "scene-A", name: "compose")
        recorder.record(
            ProbeSignal(
                kind: .intervalEnded,
                interval: "keyed-manual-authority-scene-A"
            )
        )
        if mutation != .stopAWhenBStops {
            recorder.record(
                viewSignal(
                    id: "compose-A",
                    screen: "compose",
                    active: false,
                    scene: "scene-A",
                    nativeSceneID: "native-A"
                )
            )
        }
        let returnedAID: String
        switch mutation {
        case .reuseReturnedAHome:
            returnedAID = "home-A-1"
        case .stopAWhenBStops:
            returnedAID = "home-A-2"
        default:
            returnedAID = "home-A-2"
            recordAutomaticView(id: returnedAID, recorder: recorder)
        }
        recordWork(
            name: "same-key-home-a-returned",
            scene: "scene-A",
            screen: "home",
            viewID: returnedAID
        )
        return recorder.snapshot()
    }

    private func keyedManualWorkSignal(
        kind: ProbeSignalKind,
        name: String,
        viewID: String,
        sourceScreen: String,
        scene: String = "scene-A",
        nativeSceneID: String = "native-A"
    ) -> ProbeSignal {
        ProbeSignal(
            kind: kind,
            evidenceSource: .rumMapper,
            sourceContext: ProbeSourceContext(
                logicalSceneID: scene,
                nativeSceneID: nativeSceneID,
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
