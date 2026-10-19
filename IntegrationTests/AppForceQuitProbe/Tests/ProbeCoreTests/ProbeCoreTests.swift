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
