/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2026-Present Datadog, Inc.
 */

import Foundation
import Testing

@testable import ProbeCore

private func run(_ id: String, at wall: Double) -> ProbeRun {
    ProbeRun(
        id: id,
        started: ProbeStamp(wall: wall, uptime: wall - 50),
        compatibility: [
            "app": "1", "build": "1", "install": "i", "os": "27.2", "boot": "b", "model": "UIKit"
        ],
        physicalDevice: true
    )
}

private func prior() -> ProbeRun {
    var value = run("prior", at: 100)
    value.foregroundScenes = ["a", "b"]
    value.foregroundEnter = ProbeStamp(wall: 101, uptime: 51)
    value.foregroundExit = ProbeStamp(wall: 110, uptime: 60)
    return value
}

private func evidence() -> ProbeSceneEvidence {
    ProbeSceneEvidence(earliestOpen: [], postConnectionOpen: [], forwarded: ["a", "b"])
}

@Test
private func naiveFalsePositivesPrecedeConservativeClassifier() {
    for scenario in ["crash_reporter_disabled", "foreground_oom"] {
        var previous = prior()
        previous.activeScenes = ["a"]
        previous.foregroundExit = nil
        let now = run("new", at: 105)
        let observed = ProbeSceneEvidence(earliestOpen: ["a", "b"], postConnectionOpen: ["a", "b"])
        #expect(ProbeClassifier.naive(previous: previous, current: now), Comment(rawValue: scenario))
        #expect(
            ProbeClassifier.classify(
                previous: previous,
                current: now,
                evidence: observed,
                explicit: false
            ).outcome == "cannot_confirm"
        )
    }
}

@Test(arguments: [false, true])
private func timingAndModes(explicit: Bool) {
    #expect(
        ProbeClassifier.classify(
            previous: prior(),
            current: run("new", at: 170),
            evidence: evidence(),
            explicit: explicit
        ).outcome == "candidate"
    )
    #expect(
        ProbeClassifier.classify(
            previous: prior(),
            current: run("new", at: 170.001),
            evidence: evidence(),
            explicit: explicit
        ).outcome == "cannot_confirm"
    )
    #expect(
        ProbeClassifier.classify(
            previous: prior(),
            current: run("new", at: 109),
            evidence: evidence(),
            explicit: explicit
        ).outcome == "cannot_confirm"
    )
}

@Test
private func everyCommonGateHasANegative() {
    let changes: [(inout ProbeRun) -> Void] =
        [
            { $0.schemaVersion = 2 }, { $0.mainProcess = false }, { $0.physicalDevice = false },
            { $0.debugging = true }, { $0.automation = true }, { $0.normalTermination = true },
            { $0.foregroundScenes = [] }, { $0.activeScenes = ["a"] }, { $0.foregroundExit = nil },
            { $0.foregroundExit?.wall = .nan }, { $0.foregroundExit?.uptime = 200 },
            { $0.foregroundExit?.uptime = 20 }, { $0.id = "new" }
        ]
        + ["app", "build", "install", "os", "boot", "model"].map { key in
            { $0.compatibility[key] = "changed" }
        }
        + ["crash", "oom", "fatal_hang", "watchdog", "update", "reboot", "component_change", "unknown"]
        .map { veto in { $0.vetoes = [veto] } }
    for change in changes {
        var value = prior()
        change(&value)
        #expect(
            ProbeClassifier.classify(
                previous: value,
                current: run("new", at: 115),
                evidence: evidence(),
                explicit: false
            ).outcome == "cannot_confirm"
        )
    }
    #expect(
        ProbeClassifier.classify(
            previous: nil,
            current: run("new", at: 115),
            evidence: evidence(),
            explicit: false
        ).outcome == "cannot_confirm"
    )
}

@Test
private func callbackAndSnapshotNegatives() {
    let negatives = [
        ProbeSceneEvidence(earliestOpen: nil, postConnectionOpen: []),
        ProbeSceneEvidence(earliestOpen: [], postConnectionOpen: nil),
        ProbeSceneEvidence(earliestOpen: ["a"], postConnectionOpen: []),
        ProbeSceneEvidence(earliestOpen: [], postConnectionOpen: ["b"]),
        ProbeSceneEvidence(earliestOpen: [], postConnectionOpen: [], storeReliable: false)
    ]
    for observed in negatives {
        #expect(
            ProbeClassifier.classify(
                previous: prior(),
                current: run("new", at: 115),
                evidence: observed,
                explicit: false
            ).outcome == "cannot_confirm"
        )
    }
    for ids: Set<String> in [[], ["a"], ["a", "b", "unknown"]] {
        let observed = ProbeSceneEvidence(earliestOpen: [], postConnectionOpen: [], forwarded: ids)
        #expect(
            ProbeClassifier.classify(
                previous: prior(),
                current: run("new", at: 115),
                evidence: observed,
                explicit: true
            ).outcome == "cannot_confirm"
        )
    }
    var observed = evidence()
    observed.invalidForwarding = true
    #expect(
        ProbeClassifier.classify(
            previous: prior(),
            current: run("new", at: 115),
            evidence: observed,
            explicit: true
        ).outcome == "cannot_confirm"
    )
    observed = evidence()
    observed.forwarded.formUnion(["a", "b"])
    #expect(
        ProbeClassifier.classify(
            previous: prior(),
            current: run("new", at: 115),
            evidence: observed,
            explicit: true
        ).outcome == "candidate"
    )
}

@Test
private func realStoreRelaunchCorruptionAndInterruptedWrite() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let writer = try ProbeStore(directory: directory)
    try writer.checkpoint(prior())
    let reader = try ProbeStore(directory: directory)
    #expect(reader.load().run == prior())
    #expect(reader.load().reliable)
    writer.beforeCommit = { throw ProbeStoreError.ioFailure }
    #expect(throws: ProbeStoreError.self) { try writer.checkpoint(run("new", at: 115)) }
    #expect(!reader.load().reliable)
    #expect(reader.load().run == prior())
    writer.beforeCommit = nil
    try writer.checkpoint(run("new", at: 115))
    #expect(reader.load().run?.id == "new")
    try Data("partial".utf8).write(to: directory.appendingPathComponent("current.json"))
    #expect(!reader.load().reliable)
    #expect(reader.load().run == nil)
}

@Test
private func previousViewOwnershipConsentAndConsumeBeforeWrite() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try ProbeStore(directory: directory)
    let view = ProbeView(
        sessionID: UUID().uuidString,
        viewID: UUID().uuidString,
        consent: true,
        sampled: true,
        frustrations: true
    )
    let verdict = ProbeVerdict(outcome: "candidate", reasons: [])
    let id = UUID()
    let prepared = try ProbeReturnPath.prepare(
        previous: view,
        current: ProbeReportingGates(consent: true, frustrations: true),
        verdict: verdict,
        runID: id,
        store: store
    )
    let data = try #require(prepared)
    let decoded = try JSONSerialization.jsonObject(with: data)
    let object = try #require(decoded as? [String: Any])
    #expect((object["view"] as? [String: String])?["id"] == view.viewID)
    #expect((object["session"] as? [String: String])?["id"] == view.sessionID)
    let relaunched = try ProbeStore(directory: directory)
    #expect(throws: ProbeStoreError.self) {
        try ProbeReturnPath.prepare(
            previous: view,
            current: ProbeReportingGates(consent: true, frustrations: true),
            verdict: verdict,
            runID: id,
            store: relaunched
        )
    }
    let lost = UUID()
    try store.consume(lost)  // Simulate death after consuming but before writing.
    #expect(throws: ProbeStoreError.self) {
        try ProbeReturnPath.prepare(
            previous: view,
            current: ProbeReportingGates(consent: true, frustrations: true),
            verdict: verdict,
            runID: lost,
            store: relaunched
        )
    }
    for keyPath in [\ProbeView.consent, \ProbeView.sampled, \ProbeView.frustrations] {
        var blocked = view
        blocked[keyPath: keyPath] = false
        #expect(
            try ProbeReturnPath.prepare(
                previous: blocked,
                current: ProbeReportingGates(consent: true, frustrations: true),
                verdict: verdict,
                runID: UUID(),
                store: store
            ) == nil
        )
    }
    #expect(
        try ProbeReturnPath.prepare(
            previous: view,
            current: ProbeReportingGates(consent: false, frustrations: true),
            verdict: verdict,
            runID: UUID(),
            store: store
        ) == nil
    )
    #expect(
        try ProbeReturnPath.prepare(
            previous: view,
            current: ProbeReportingGates(consent: true, frustrations: false),
            verdict: verdict,
            runID: UUID(),
            store: store
        ) == nil
    )
    #expect(
        try ProbeReturnPath.prepare(
            previous: view,
            current: ProbeReportingGates(consent: true, frustrations: true),
            verdict: .unknown(["missing"]),
            runID: UUID(),
            store: store
        ) == nil
    )
}

@Test
private func terminationCallbackIsAnObservationAndMissingViewDoesNotPrepareAction() throws {
    var previous = prior()
    previous.terminationCallbackObserved = true
    let verdict = ProbeClassifier.classify(
        previous: previous,
        current: run("new", at: 115),
        evidence: evidence(),
        explicit: false
    )
    #expect(verdict.outcome == "candidate")
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try ProbeStore(directory: directory)
    #expect(
        try ProbeReturnPath.prepare(
            previous: nil,
            current: ProbeReportingGates(consent: true, frustrations: true),
            verdict: verdict,
            runID: UUID(),
            store: store
        ) == nil
    )
    let invalid = ProbeView(sessionID: "", viewID: "", consent: true, sampled: true, frustrations: true)
    #expect(
        try ProbeReturnPath.prepare(
            previous: invalid,
            current: ProbeReportingGates(consent: true, frustrations: true),
            verdict: verdict,
            runID: UUID(),
            store: store
        ) == nil
    )
}

@Test
private func currentRunGatesAndClockTolerance() {
    let changes: [(inout ProbeRun) -> Void] = [
        { $0.schemaVersion = 999 }, { $0.mainProcess = false }, { $0.physicalDevice = false },
        { $0.debugging = true }, { $0.automation = true }, { $0.started.wall = .infinity }
    ]
    for change in changes {
        var current = run("new", at: 120)
        change(&current)
        #expect(
            ProbeClassifier.classify(previous: prior(), current: current, evidence: evidence(), explicit: false).outcome
                == "cannot_confirm"
        )
    }
    var current = run("new", at: 120)
    current.started.uptime = 65
    #expect(
        ProbeClassifier.classify(previous: prior(), current: current, evidence: evidence(), explicit: false).outcome
            == "candidate"
    )
    current.started.uptime = 64.999
    #expect(
        ProbeClassifier.classify(previous: prior(), current: current, evidence: evidence(), explicit: false).outcome
            == "cannot_confirm"
    )
}

private func reporterPrior() -> ProbeRun {
    var value = prior()
    value.compatibility["source"] = "source-a"
    value.crashReporterInstalled = true
    value.terminationCallbackObserved = true
    value.terminationObservedAt = ProbeStamp(wall: 111, uptime: 61)
    return value
}

private func reporterCurrent() -> ProbeRun {
    var value = run("new", at: 115)
    value.compatibility["source"] = "source-a"
    value.crashReporterInstalled = true
    return value
}

@Test(arguments: ProbeJourneyKind.allCases)
private func journeyEvidenceSurvivesProcessCheckpoint(kind: ProbeJourneyKind) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var value = reporterPrior()
    value.journey = ProbeJourneyState(
        kind: kind, enteredAt: ProbeStamp(wall: 105, uptime: 55), backAttempts: 2, responseChecks: 3
    )
    try ProbeStore(directory: directory).checkpoint(value)
    let loaded = try ProbeStore(directory: directory)
    #expect(loaded.load().run == value)
    #expect(loaded.load().reliable)
}

@Test
private func earlierCheckpointsWithoutJourneyStillDecode() throws {
    var value = reporterPrior()
    value.journey = ProbeJourneyState(kind: .emptyPage, enteredAt: value.started)
    var fields = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    fields.removeValue(forKey: "journey")
    let restored = try JSONDecoder().decode(ProbeRun.self, from: JSONSerialization.data(withJSONObject: fields))
    value.journey = nil
    #expect(restored == value)
}

@Test(arguments: ProbeJourneyKind.allCases)
private func journeyLabelsDoNotSupplyDetectionEvidence(kind: ProbeJourneyKind) {
    let clean = ProbeReporterEvidence(read: .empty, crashedLastLaunch: false)
    let crash = ProbeReporterEvidence(read: .capturedCrash, crashedLastLaunch: true)
    var previous = reporterPrior()
    var current = reporterCurrent()
    let withoutJourney = ProbeClassifier.reporterLifecycle(
        previous: previous, current: current, evidence: evidence(), reporter: clean
    )
    previous.journey = ProbeJourneyState(kind: kind, enteredAt: previous.started, responseChecks: 1)
    current.journey = ProbeJourneyState(kind: kind, enteredAt: current.started)
    #expect(
        ProbeClassifier.reporterLifecycle(
            previous: previous, current: current, evidence: evidence(), reporter: clean
        ) == withoutJourney
    )
    #expect(
        ProbeClassifier.reporterLifecycle(
            previous: previous, current: current, evidence: evidence(), reporter: crash
        ).outcome == "cannot_confirm"
    )
    previous.terminationCallbackObserved = false
    let missingCallback = ProbeClassifier.reporterLifecycle(
        previous: previous, current: current, evidence: evidence(), reporter: clean
    )
    #expect(missingCallback.reasons.contains("missing_termination_callback"))
}

@Test
private func reporterHypothesisDoesNotRequireDiscardAndRejectsEveryReporterFailure() {
    let retained = ProbeSceneEvidence(earliestOpen: ["a"], postConnectionOpen: ["a"])
    let clean = ProbeReporterEvidence(read: .empty, crashedLastLaunch: false)
    #expect(
        ProbeClassifier.reporterLifecycle(
            previous: reporterPrior(),
            current: reporterCurrent(),
            evidence: retained,
            reporter: clean
        ).outcome == "candidate"
    )
    #expect(
        ProbeClassifier.classify(
            previous: reporterPrior(),
            current: reporterCurrent(),
            evidence: retained,
            explicit: false
        ).outcome == "cannot_confirm"
    )
    for state in ProbeReporterRead.allCases where state != .empty {
        #expect(
            ProbeClassifier.reporterLifecycle(
                previous: reporterPrior(),
                current: reporterCurrent(),
                evidence: retained,
                reporter: ProbeReporterEvidence(read: state, crashedLastLaunch: false)
            ).outcome == "cannot_confirm"
        )
    }
    for crashed: Bool? in [true, nil] {
        #expect(
            ProbeClassifier.reporterLifecycle(
                previous: reporterPrior(),
                current: reporterCurrent(),
                evidence: retained,
                reporter: ProbeReporterEvidence(read: .empty, crashedLastLaunch: crashed)
            ).outcome == "cannot_confirm"
        )
    }
}

@Test
private func reporterHypothesisHasLifecycleCompatibilityAndHealthRefusals() {
    let changes: [(inout ProbeRun) -> Void] =
        [
            { $0.terminationCallbackObserved = nil }, { $0.terminationCallbackObserved = false },
            { $0.terminationObservedAt = nil }, { $0.terminationObservedAt?.wall = .nan },
            { $0.terminationObservedAt = ProbeStamp(wall: 109, uptime: 59) },
            { $0.terminationObservedAt = ProbeStamp(wall: 116, uptime: 66) },
            { $0.terminationObservedAt = ProbeStamp(wall: 111, uptime: 40) },
            { $0.crashReporterInstalled = nil }, { $0.crashReporterInstalled = false },
            { $0.foregroundExit = nil }, { $0.activeScenes = ["a"] }, { $0.foregroundScenes = [] },
            { $0.debugging = true }, { $0.physicalDevice = false }, { $0.automation = true },
            { $0.schemaVersion = 2 }, { $0.mainProcess = false }, { $0.normalTermination = true },
            { $0.id = "new" }, { $0.vetoes = ["oom"] }, { $0.compatibility["source"] = "unattested" }
        ]
        + ["app", "build", "source", "install", "os", "boot", "model"].map { key in
            { $0.compatibility[key] = "different" }
        }
    let clean = ProbeReporterEvidence(read: .empty, crashedLastLaunch: false)
    for change in changes {
        var previous = reporterPrior()
        change(&previous)
        #expect(
            ProbeClassifier.reporterLifecycle(
                previous: previous,
                current: reporterCurrent(),
                evidence: evidence(),
                reporter: clean
            ).outcome == "cannot_confirm"
        )
    }
    var current = reporterCurrent()
    current.crashReporterInstalled = false
    #expect(
        ProbeClassifier.reporterLifecycle(
            previous: reporterPrior(),
            current: current,
            evidence: evidence(),
            reporter: clean
        ).outcome == "cannot_confirm"
    )
    var unreliable = evidence()
    unreliable.storeReliable = false
    #expect(
        ProbeClassifier.reporterLifecycle(
            previous: reporterPrior(),
            current: reporterCurrent(),
            evidence: unreliable,
            reporter: clean
        ).outcome == "cannot_confirm"
    )
    #expect(
        ProbeClassifier.reporterLifecycle(
            previous: nil,
            current: reporterCurrent(),
            evidence: evidence(),
            reporter: clean
        ).outcome == "cannot_confirm"
    )
}

@Test
private func reporterHypothesisTerminationAndRelaunchWindows() {
    let clean = ProbeReporterEvidence(read: .empty, crashedLastLaunch: false)
    var previous = reporterPrior()
    previous.terminationObservedAt = ProbeStamp(wall: 125, uptime: 75)
    var current = reporterCurrent()
    current.started = ProbeStamp(wall: 170, uptime: 120)
    #expect(
        ProbeClassifier.reporterLifecycle(
            previous: previous,
            current: current,
            evidence: evidence(),
            reporter: clean
        ).outcome == "candidate"
    )
    previous.terminationObservedAt = ProbeStamp(wall: 125.001, uptime: 75.001)
    #expect(
        ProbeClassifier.reporterLifecycle(
            previous: previous,
            current: current,
            evidence: evidence(),
            reporter: clean
        ).outcome == "cannot_confirm"
    )
    previous = reporterPrior()
    current.started = ProbeStamp(wall: 170.001, uptime: 120.001)
    #expect(
        ProbeClassifier.reporterLifecycle(
            previous: previous,
            current: current,
            evidence: evidence(),
            reporter: clean
        ).outcome == "cannot_confirm"
    )
}
