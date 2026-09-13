/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal struct ProbeSemanticIssue: Codable, Equatable {
    let expectationIndex: Int?
    let expectation: ProbeExpectation?
    let signalSequence: UInt64?
    let reason: String
}

internal struct ProbeSemanticResult: Codable, Equatable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let scenarioID: String
    let state: ProbeSemanticResultState
    let matchedExpectationCount: Int
    let issues: [ProbeSemanticIssue]

    init(
        scenarioID: String,
        state: ProbeSemanticResultState,
        matchedExpectationCount: Int,
        issues: [ProbeSemanticIssue]
    ) {
        self.schemaVersion = Self.schemaVersion
        self.scenarioID = scenarioID
        self.state = state
        self.matchedExpectationCount = matchedExpectationCount
        self.issues = issues
    }
}

internal struct ProbeSemanticResultRecord: Codable, Equatable {
    let type: String
    let runID: String
    let result: ProbeSemanticResult

    init(runID: String, result: ProbeSemanticResult) {
        self.type = "semantic-result"
        self.runID = runID
        self.result = result
    }
}

internal enum ProbeSemanticOracle {
    private enum CandidateResult {
        case noMatch
        case match
        case violation(String)
    }

    static func evaluate(
        scenario: ProbeScenario,
        signals: [ProbeSignal]
    ) -> ProbeSemanticResult {
        let timeline = ProbeSemanticTimeline(signals: signals)

        if let metadataIssue = validateMetadata(scenario: scenario, signals: timeline.signals) {
            return failure(
                scenario: scenario,
                matched: 0,
                issue: metadataIssue
            )
        }

        if let assertedResult = assertedTerminalResult(
            scenario: scenario,
            signals: timeline.signals
        ) {
            return assertedResult
        }

        if let unavailable = unavailableCapability(
            requiredBy: scenario,
            signals: timeline.signals
        ) {
            return ProbeSemanticResult(
                scenarioID: scenario.identifier,
                state: .skipped,
                matchedExpectationCount: 0,
                issues: [
                    ProbeSemanticIssue(
                        expectationIndex: nil,
                        expectation: nil,
                        signalSequence: unavailable.sequence,
                        reason: "required capability \(unavailable.capability?.rawValue ?? "unknown") is unavailable"
                    )
                ]
            )
        }

        if let gestureIssue = inconclusiveGesture(
            requiredBy: scenario,
            signals: timeline.signals
        ) {
            return ProbeSemanticResult(
                scenarioID: scenario.identifier,
                state: .inconclusive,
                matchedExpectationCount: 0,
                issues: [gestureIssue]
            )
        }

        if let diagnostic = timeline.diagnostics.first {
            return failure(
                scenario: scenario,
                matched: 0,
                issue: ProbeSemanticIssue(
                    expectationIndex: nil,
                    expectation: nil,
                    signalSequence: nil,
                    reason: diagnostic
                )
            )
        }

        let orderedResult = evaluateOrdered(
            scenario.expectedSemanticTimeline,
            in: timeline
        )
        if let issue = orderedResult.issue {
            return failure(
                scenario: scenario,
                matched: orderedResult.matched,
                issue: issue
            )
        }

        let completionResult = evaluateCompletion(
            scenario.completionConditions,
            in: timeline
        )
        if let issue = completionResult.issue {
            return failure(
                scenario: scenario,
                matched: orderedResult.matched + completionResult.matched,
                issue: issue
            )
        }

        return ProbeSemanticResult(
            scenarioID: scenario.identifier,
            state: .pass,
            matchedExpectationCount: orderedResult.matched + completionResult.matched,
            issues: []
        )
    }

    private static func validateMetadata(
        scenario: ProbeScenario,
        signals: [ProbeSignal]
    ) -> ProbeSemanticIssue? {
        guard !signals.isEmpty else {
            return ProbeSemanticIssue(
                expectationIndex: nil,
                expectation: nil,
                signalSequence: nil,
                reason: "no probe signals were recorded"
            )
        }

        if let unsupported = signals.first(where: {
            !ProbeSignal.supportedSchemaVersions.contains($0.schemaVersion)
        }) {
            return ProbeSemanticIssue(
                expectationIndex: nil,
                expectation: nil,
                signalSequence: unsupported.sequence,
                reason: "unsupported signal schema version \(unsupported.schemaVersion)"
            )
        }

        if let missingRunID = signals.first(where: { $0.runID.isEmpty }) {
            return ProbeSemanticIssue(
                expectationIndex: nil,
                expectation: nil,
                signalSequence: missingRunID.sequence,
                reason: "signal has no run ID"
            )
        }

        let runIDs = Set(signals.map(\.runID))
        if runIDs.count != 1 {
            return ProbeSemanticIssue(
                expectationIndex: nil,
                expectation: nil,
                signalSequence: nil,
                reason: "signals contain multiple run IDs: \(runIDs.sorted().joined(separator: ","))"
            )
        }

        if let mismatched = signals.first(where: { $0.scenarioID != scenario.identifier }) {
            return ProbeSemanticIssue(
                expectationIndex: nil,
                expectation: nil,
                signalSequence: mismatched.sequence,
                reason: "signal scenario \(mismatched.scenarioID) does not match \(scenario.identifier)"
            )
        }

        for (previous, next) in zip(signals, signals.dropFirst()) where next.sequence <= previous.sequence {
            return ProbeSemanticIssue(
                expectationIndex: nil,
                expectation: nil,
                signalSequence: next.sequence,
                reason: "signal sequence is not strictly increasing after \(previous.sequence)"
            )
        }
        return nil
    }

    private static func assertedTerminalResult(
        scenario: ProbeScenario,
        signals: [ProbeSignal]
    ) -> ProbeSemanticResult? {
        guard
            let assertion = signals.first(where: {
                $0.kind == .assertion
                    && $0.result != nil
                    && $0.result != .pass
            }),
            let result = assertion.result
        else {
            return nil
        }
        return ProbeSemanticResult(
            scenarioID: scenario.identifier,
            state: result,
            matchedExpectationCount: 0,
            issues: [
                ProbeSemanticIssue(
                    expectationIndex: nil,
                    expectation: nil,
                    signalSequence: assertion.sequence,
                    reason: assertion.reason ?? "harness reported \(result.rawValue)"
                )
            ]
        )
    }

    private static func unavailableCapability(
        requiredBy scenario: ProbeScenario,
        signals: [ProbeSignal]
    ) -> ProbeSignal? {
        signals.first {
            $0.kind == .capability
                && $0.available == false
                && $0.capability.map(scenario.requiredCapabilities.contains) == true
        }
    }

    private static func inconclusiveGesture(
        requiredBy scenario: ProbeScenario,
        signals: [ProbeSignal]
    ) -> ProbeSemanticIssue? {
        let requiresNativeGesture =
            scenario.requiredCapabilities.contains(.nativeSwiftUIGesture)
            || scenario.requiredCapabilities.contains(.nativeUIKitGesture)
        guard
            requiresNativeGesture,
            let attempt = signals.first(where: { $0.kind == .gestureAttempted })
        else {
            return nil
        }

        let began = signals.first {
            $0.kind == .transitionBegan
                && $0.sequence > attempt.sequence
                && sameScene($0, attempt)
        }
        guard let began else {
            return ProbeSemanticIssue(
                expectationIndex: nil,
                expectation: nil,
                signalSequence: attempt.sequence,
                reason: "gesture was attempted but no transition or path signal was observed"
            )
        }
        let resolved = signals.first {
            $0.kind == .transitionResolved
                && $0.sequence > began.sequence
                && sameTransition($0, began)
        }
        guard resolved != nil else {
            return ProbeSemanticIssue(
                expectationIndex: nil,
                expectation: nil,
                signalSequence: began.sequence,
                reason: "interactive transition began but no completion or cancellation was observed"
            )
        }
        return nil
    }

    private static func evaluateOrdered(
        _ expectations: [ProbeExpectation],
        in timeline: ProbeSemanticTimeline
    ) -> (matched: Int, issue: ProbeSemanticIssue?) {
        var cursor = 0
        var matched = 0
        var matchedDeferredEventIndexes: Set<Int> = []

        for (index, expectation) in expectations.enumerated() {
            if isNegative(expectation) {
                if let issue = evaluateNegative(
                    expectation,
                    index: index,
                    in: timeline
                ) {
                    return (matched, issue)
                }
                matched += 1
                continue
            }

            var didMatch = false
            var eventIndex = cursor
            while eventIndex < timeline.events.count {
                defer { eventIndex += 1 }
                guard !matchedDeferredEventIndexes.contains(eventIndex) else {
                    continue
                }
                let event = timeline.events[eventIndex]
                switch candidate(
                    event,
                    for: expectation,
                    timeline: timeline
                ) {
                case .noMatch:
                    continue
                case .match:
                    didMatch = true
                    matched += 1
                    if isDeferredObservation(expectation.kind) {
                        // View-stop mapper callbacks can arrive after the next
                        // view starts while a navigation animation overlaps.
                        // Resource mapper callbacks are emitted on completion,
                        // which can likewise follow a later navigation event.
                        // Require exact ownership without using either callback
                        // as the navigation-order clock.
                        matchedDeferredEventIndexes.insert(eventIndex)
                    } else {
                        cursor = eventIndex + 1
                    }
                case .violation(let reason):
                    return (
                        matched,
                        ProbeSemanticIssue(
                            expectationIndex: index,
                            expectation: expectation,
                            signalSequence: event.signal.sequence,
                            reason: reason
                        )
                    )
                }
                break
            }
            if !didMatch {
                return (
                    matched,
                    missingIssue(expectation, index: index, after: cursor)
                )
            }
        }
        return (matched, nil)
    }

    private static func evaluateCompletion(
        _ expectations: [ProbeExpectation],
        in timeline: ProbeSemanticTimeline
    ) -> (matched: Int, issue: ProbeSemanticIssue?) {
        var matched = 0
        for (index, expectation) in expectations.enumerated() {
            if isNegative(expectation) {
                if let issue = evaluateNegative(
                    expectation,
                    index: index,
                    in: timeline
                ) {
                    return (matched, issue)
                }
                matched += 1
                continue
            }

            var found = false
            var firstViolation: ProbeSemanticIssue?
            for event in timeline.events {
                switch candidate(
                    event,
                    for: expectation,
                    timeline: timeline
                ) {
                case .noMatch:
                    continue
                case .match:
                    found = true
                    matched += 1
                case .violation(let reason):
                    if firstViolation == nil {
                        firstViolation = ProbeSemanticIssue(
                            expectationIndex: index,
                            expectation: expectation,
                            signalSequence: event.signal.sequence,
                            reason: reason
                        )
                    }
                    continue
                }
                break
            }
            if !found {
                if let firstViolation {
                    return (matched, firstViolation)
                }
                return (
                    matched,
                    missingIssue(expectation, index: index, after: 0)
                )
            }
        }
        return (matched, nil)
    }

    private static func evaluateNegative(
        _ expectation: ProbeExpectation,
        index: Int,
        in timeline: ProbeSemanticTimeline
    ) -> ProbeSemanticIssue? {
        guard let scopedEvents = timeline.events(in: expectation.interval) else {
            return ProbeSemanticIssue(
                expectationIndex: index,
                expectation: expectation,
                signalSequence: nil,
                reason: "negative expectation interval \(expectation.interval ?? "unknown") was not closed"
            )
        }

        if let event = scopedEvents.first(where: {
            if expectation.kind == .noViewStarted, $0.kind != .viewStarted {
                return false
            }
            if expectation.kind == .noEvent, !isRUMEvent($0.kind) {
                return false
            }
            return negativeFieldsMatch(
                $0.signal,
                expectation: expectation,
                timeline: timeline
            )
        }) {
            return ProbeSemanticIssue(
                expectationIndex: index,
                expectation: expectation,
                signalSequence: event.signal.sequence,
                reason: "forbidden \(describe(expectation)) occurred at signal \(event.signal.sequence)"
            )
        }
        return nil
    }

    private static func candidate(
        _ event: ProbeSemanticEvent,
        for expectation: ProbeExpectation,
        timeline: ProbeSemanticTimeline
    ) -> CandidateResult {
        guard event.kind == expectation.kind else {
            return .noMatch
        }

        let signal = event.signal
        let hasNamedIdentity = expectation.name != nil
        if let expectedName = expectation.name, signal.name != expectedName {
            return .noMatch
        }

        if let expectedSourceScene = expectation.sourceScene {
            guard signal.sourceContext?.logicalSceneID == expectedSourceScene else {
                return .violation(
                    "expected \(describe(expectation)) from \(expectedSourceScene), "
                        + "observed \(signal.sourceContext?.logicalSceneID ?? "unresolved")"
                )
            }
        }
        if let expectedSourceScreen = expectation.sourceScreen {
            guard signal.sourceContext?.screen == expectedSourceScreen else {
                return .violation(
                    "expected \(describe(expectation)) from screen \(expectedSourceScreen), "
                        + "observed \(signal.sourceContext?.screen ?? "unresolved")"
                )
            }
        }
        if let expectedOrigin = expectation.rumViewOrigin {
            guard let observedOrigin = timeline.rumViewOrigin(for: signal) else {
                return .violation(
                    "expected \(describe(expectation)) on a \(expectedOrigin.rawValue) RUM view, "
                        + "but the owner view origin was unresolved"
                )
            }
            guard observedOrigin == expectedOrigin else {
                return .violation(
                    "expected \(describe(expectation)) on a \(expectedOrigin.rawValue) RUM view, "
                        + "observed \(observedOrigin.rawValue)"
                )
            }
        }
        if let openedScene = expectation.ownerViewStartedAfterSceneOpen {
            guard timeline.ownerView(for: signal, startedAfterOpening: openedScene) else {
                return .violation(
                    "expected \(describe(expectation)) on a RUM view started after opening "
                        + openedScene
                )
            }
        }

        if
            requiresViewOwnership(expectation),
            let scene = expectation.scene,
            let screen = expectation.screen,
            let occurrence = expectation.occurrence {
            guard let expectedViewID = timeline.viewID(
                scene: scene,
                screen: screen,
                occurrence: occurrence
            ) else {
                return .violation(
                    "expected view identity for \(scene)/\(screen)#\(occurrence) was never established"
                )
            }
            guard let observedViewID = signal.rumContext?.viewID else {
                return .violation(
                    "expected \(describe(expectation)) on view \(expectedViewID), but event has no view ID"
                )
            }
            if observedViewID != expectedViewID {
                return .violation(
                    "expected \(describe(expectation)) on view \(expectedViewID), observed \(observedViewID)"
                )
            }
        }

        if let expectedScreen = expectation.screen {
            guard let observedScreen = timeline.observedScreen(for: signal) else {
                return hasNamedIdentity
                    ? .violation(
                        "expected \(describe(expectation)) on screen \(expectedScreen), "
                            + "but RUM ownership was unresolved"
                    )
                    : .noMatch
            }
            if observedScreen != expectedScreen {
                return hasNamedIdentity
                    ? .violation(
                        "expected \(describe(expectation)) on screen \(expectedScreen), "
                            + "observed \(observedScreen)"
                    )
                    : .noMatch
            }
        }
        if let expectedScene = expectation.scene {
            guard let observedScene = timeline.observedScene(for: signal) else {
                return hasNamedIdentity
                    ? .violation(
                        "expected \(describe(expectation)) on \(expectedScene), "
                            + "but RUM ownership was unresolved"
                    )
                    : .noMatch
            }
            if observedScene != expectedScene {
                return hasNamedIdentity
                    ? .violation(
                        "expected \(describe(expectation)) on \(expectedScene), "
                            + "observed \(observedScene)"
                    )
                    : .noMatch
            }
        }
        if let expectedOccurrence = expectation.occurrence {
            guard let observedOccurrence = timeline.observedOccurrence(for: signal) else {
                return hasNamedIdentity
                    ? .violation(
                        "expected \(describe(expectation)) occurrence \(expectedOccurrence), "
                            + "but RUM ownership was unresolved"
                    )
                    : .noMatch
            }
            if observedOccurrence != expectedOccurrence {
                return hasNamedIdentity
                    ? .violation(
                        "expected \(describe(expectation)) occurrence \(expectedOccurrence), "
                            + "observed \(observedOccurrence)"
                    )
                    : .noMatch
            }
        }
        if
            let expectedOutcome = expectation.outcome,
            signal.outcome != expectedOutcome {
            return .violation(
                "expected transition \(expectedOutcome.rawValue), observed \(signal.outcome?.rawValue ?? "unresolved")"
            )
        }

        return .match
    }

    private static func negativeFieldsMatch(
        _ signal: ProbeSignal,
        expectation: ProbeExpectation,
        timeline: ProbeSemanticTimeline
    ) -> Bool {
        if
            let scene = expectation.scene,
            timeline.observedScene(for: signal) != scene {
            return false
        }
        if
            let screen = expectation.screen,
            timeline.observedScreen(for: signal) != screen {
            return false
        }
        if
            let occurrence = expectation.occurrence,
            timeline.observedOccurrence(for: signal) != occurrence {
            return false
        }
        if let name = expectation.name, signal.name != name {
            return false
        }
        if
            let sourceScene = expectation.sourceScene,
            signal.sourceContext?.logicalSceneID != sourceScene {
            return false
        }
        if
            let sourceScreen = expectation.sourceScreen,
            signal.sourceContext?.screen != sourceScreen {
            return false
        }
        if
            let rumViewOrigin = expectation.rumViewOrigin,
            timeline.rumViewOrigin(for: signal) != rumViewOrigin {
            return false
        }
        if
            let openedScene = expectation.ownerViewStartedAfterSceneOpen,
            !timeline.ownerView(for: signal, startedAfterOpening: openedScene) {
            return false
        }
        if let outcome = expectation.outcome, signal.outcome != outcome {
            return false
        }
        return true
    }

    private static func isNegative(_ expectation: ProbeExpectation) -> Bool {
        expectation.kind == .noViewStarted || expectation.kind == .noEvent
    }

    private static func isDeferredObservation(
        _ kind: ProbeExpectationKind
    ) -> Bool {
        kind == .viewStopped || kind == .resource
    }

    private static func isRUMEvent(_ kind: ProbeExpectationKind) -> Bool {
        switch kind {
        case .action, .resource, .error, .trace, .operationStep:
            return true
        default:
            return false
        }
    }

    private static func requiresViewOwnership(
        _ expectation: ProbeExpectation
    ) -> Bool {
        switch expectation.kind {
        case .action, .resource, .error, .trace, .operationStep:
            return true
        default:
            return false
        }
    }

    private static func missingIssue(
        _ expectation: ProbeExpectation,
        index: Int,
        after cursor: Int
    ) -> ProbeSemanticIssue {
        ProbeSemanticIssue(
            expectationIndex: index,
            expectation: expectation,
            signalSequence: nil,
            reason: "missing expected \(describe(expectation)) after signal index \(cursor)"
        )
    }

    private static func describe(_ expectation: ProbeExpectation) -> String {
        var parts = [expectation.kind.rawValue]
        if let scene = expectation.scene {
            parts.append("scene=\(scene)")
        }
        if let screen = expectation.screen {
            parts.append("screen=\(screen)")
        }
        if let occurrence = expectation.occurrence {
            parts.append("occurrence=\(occurrence)")
        }
        if let name = expectation.name {
            parts.append("name=\(name)")
        }
        if let sourceScene = expectation.sourceScene {
            parts.append("source-scene=\(sourceScene)")
        }
        if let sourceScreen = expectation.sourceScreen {
            parts.append("source-screen=\(sourceScreen)")
        }
        if let rumViewOrigin = expectation.rumViewOrigin {
            parts.append("rum-view-origin=\(rumViewOrigin.rawValue)")
        }
        if let openedScene = expectation.ownerViewStartedAfterSceneOpen {
            parts.append("owner-view-after-open=\(openedScene)")
        }
        if let interval = expectation.interval {
            parts.append("interval=\(interval)")
        }
        return parts.joined(separator: " ")
    }

    private static func sameScene(
        _ lhs: ProbeSignal,
        _ rhs: ProbeSignal
    ) -> Bool {
        guard
            let lhsScene = lhs.semanticContext?.logicalSceneID,
            let rhsScene = rhs.semanticContext?.logicalSceneID
        else {
            return true
        }
        return lhsScene == rhsScene
    }

    private static func sameTransition(
        _ lhs: ProbeSignal,
        _ rhs: ProbeSignal
    ) -> Bool {
        if
            let lhsTransition = lhs.transitionID,
            let rhsTransition = rhs.transitionID {
            return lhsTransition == rhsTransition
        }
        return sameScene(lhs, rhs)
    }

    private static func failure(
        scenario: ProbeScenario,
        matched: Int,
        issue: ProbeSemanticIssue
    ) -> ProbeSemanticResult {
        ProbeSemanticResult(
            scenarioID: scenario.identifier,
            state: .fail,
            matchedExpectationCount: matched,
            issues: [issue]
        )
    }
}
