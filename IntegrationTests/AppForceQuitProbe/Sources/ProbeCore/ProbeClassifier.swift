/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2026-Present Datadog, Inc.
 */

import Foundation

internal struct ProbeStamp: Codable, Equatable {
    var wall: Double
    var uptime: Double

    var isValid: Bool { wall.isFinite && uptime.isFinite && wall > 0 && uptime >= 0 }
    var offset: Double { wall - uptime }
}

internal struct ProbeRun: Codable, Equatable {
    var schemaVersion = 1
    var id: String
    var started: ProbeStamp
    // Exact app/build/install/OS/boot/process-model facts; never sent to intake.
    var compatibility: [String: String]
    var mainProcess = true
    var physicalDevice = false
    var debugging = false
    var automation = false
    var foregroundScenes = Set<String>()
    var activeScenes = Set<String>()
    var discardedScenes = Set<String>()
    var foregroundEnter: ProbeStamp?
    var foregroundExit: ProbeStamp?
    var normalTermination = false
    var terminationCallbackObserved: Bool?
    var terminationObservedAt: ProbeStamp?
    var crashReporterInstalled: Bool?
    // Host scenario context only; no classifier reads this field.
    var journey: ProbeJourneyState?
    var vetoes: [String] = []
}

internal enum ProbeJourneyKind: String, CaseIterable, Codable {
    case infiniteLoader = "infinite_loader"
    case ineffectiveBack = "ineffective_back"
    case emptyPage = "empty_page"

    var title: String {
        switch self {
        case .infiniteLoader: return "Infinite loader"
        case .ineffectiveBack: return "Back does not navigate"
        case .emptyPage: return "Empty page"
        }
    }
}

internal struct ProbeJourneyState: Codable, Equatable {
    var kind: ProbeJourneyKind
    var enteredAt: ProbeStamp
    var backAttempts = 0
    var responseChecks = 0
}

internal struct ProbeSceneEvidence: Codable {
    var earliestOpen: Set<String>?
    var postConnectionOpen: Set<String>?
    var forwarded = Set<String>()
    var invalidForwarding = false
    var storeReliable = true
}

internal struct ProbeVerdict: Codable, Equatable {
    var outcome: String
    var reasons: [String]

    static func unknown(_ reasons: [String]) -> Self {
        Self(outcome: "cannot_confirm", reasons: reasons)
    }
}

internal enum ProbeReporterRead: String, Codable, CaseIterable {
    case empty, capturedCrash, unmatchedReport, readFailed, installFailed, unavailable
}

internal struct ProbeReporterEvidence: Codable {
    var read: ProbeReporterRead = .unavailable
    var crashedLastLaunch: Bool?
    var reportRunIDs: [String] = []
    var archivedReports: [String] = []
    var failure: String?
}

internal enum ProbeClassifier {
    // Separate feasibility hypothesis. This must never feed the action preparation path.
    static func reporterLifecycle(
        previous: ProbeRun?,
        current: ProbeRun,
        evidence: ProbeSceneEvidence,
        reporter: ProbeReporterEvidence
    ) -> ProbeVerdict {
        guard let previous = previous else {
            return .unknown(["no_prior_run"])
        }
        var failures = commonFailures(previous: previous, current: current)
        failures += timingFailures(previous: previous, current: current)
        if !evidence.storeReliable { failures.append("unreliable_store") }
        if previous.foregroundScenes.isEmpty { failures.append("no_foreground_scenes") }
        if previous.crashReporterInstalled != true || current.crashReporterInstalled != true {
            failures.append("reporter_not_installed_both_runs")
        }
        if reporter.read != .empty { failures.append("reporter_\(reporter.read.rawValue)") }
        if reporter.crashedLastLaunch != false { failures.append("reporter_prior_crash_or_unknown") }
        if previous.compatibility["source"]?.isEmpty != false
            || previous.compatibility["source"] == "unattested"
            || previous.compatibility["source"] != current.compatibility["source"] {
            failures.append("compatibility_source")
        }
        if previous.terminationCallbackObserved != true {
            failures.append("missing_termination_callback")
        }
        if let terminal = previous.terminationObservedAt, let exit = previous.foregroundExit {
            if !terminal.isValid || terminal.uptime < exit.uptime || terminal.wall < exit.wall
                || terminal.uptime > current.started.uptime || terminal.wall > current.started.wall
                || abs(terminal.offset - exit.offset) > 5 {
                failures.append("termination_clock_discontinuity")
            }
            if !(0...15).contains(terminal.wall - exit.wall) {
                failures.append("termination_after_foreground_window")
            }
        } else {
            failures.append("missing_termination_stamp")
        }
        return failures.isEmpty
            ? ProbeVerdict(outcome: "candidate", reasons: ["unvalidated_reporter_lifecycle_hypothesis"])
            : .unknown(Array(Set(failures)).sorted())
    }

    // Deliberately unsafe comparator, retained only to demonstrate false positives in fixtures.
    static func naive(previous: ProbeRun?, current: ProbeRun) -> Bool {
        guard let previous = previous, previous.id != current.id, !previous.normalTermination else {
            return false
        }
        let last = previous.foregroundExit ?? previous.foregroundEnter ?? previous.started
        return (0...60).contains(current.started.wall - last.wall)
    }

    static func classify(
        previous: ProbeRun?,
        current: ProbeRun,
        evidence: ProbeSceneEvidence,
        explicit: Bool
    ) -> ProbeVerdict {
        guard let previous = previous else {
            return .unknown(["no_prior_run"])
        }
        var failures = commonFailures(previous: previous, current: current)
        failures += timingFailures(previous: previous, current: current)
        failures += sceneFailures(previous: previous, evidence: evidence, explicit: explicit)
        return failures.isEmpty
            ? ProbeVerdict(
                outcome: "candidate",
                reasons: [explicit ? "inferred_scene_discard_explicit" : "inferred_scene_discard_automatic"]
            )
            : .unknown(Array(Set(failures)).sorted())
    }

    private static func commonFailures(previous: ProbeRun, current: ProbeRun) -> [String] {
        var failures: [String] = []
        if previous.schemaVersion != 1 || current.schemaVersion != 1 {
            failures.append("unsupported_state")
        }
        if previous.id == current.id { failures.append("same_process") }
        let required = ["app", "build", "install", "os", "boot", "model"]
        for key in required
        where previous.compatibility[key]?.isEmpty != false
            || previous.compatibility[key] != current.compatibility[key] {
            failures.append("compatibility_\(key)")
        }
        if !previous.mainProcess || !current.mainProcess { failures.append("not_main_process") }
        if !previous.physicalDevice || !current.physicalDevice { failures.append("simulator") }
        if previous.debugging || current.debugging { failures.append("debugger") }
        if previous.automation || current.automation { failures.append("automation") }
        if previous.normalTermination { failures.append("normal_termination") }
        failures.append(contentsOf: previous.vetoes.map { "veto_\($0)" })
        return failures
    }

    private static func timingFailures(previous: ProbeRun, current: ProbeRun) -> [String] {
        var failures: [String] = []
        if !previous.activeScenes.isEmpty { failures.append("missing_foreground_exit") }
        if let exit = previous.foregroundExit {
            if !exit.isValid || !current.started.isValid || !previous.started.isValid
                || exit.uptime < previous.started.uptime || exit.wall < previous.started.wall
                || current.started.uptime < exit.uptime || abs(current.started.offset - exit.offset) > 5
                || abs(exit.offset - previous.started.offset) > 5 {
                failures.append("clock_discontinuity")
            }
            if !(0...60).contains(current.started.wall - exit.wall) { failures.append("relaunch_window") }
        } else {
            failures.append("missing_foreground_exit")
        }
        return failures
    }

    private static func sceneFailures(
        previous: ProbeRun,
        evidence: ProbeSceneEvidence,
        explicit: Bool
    ) -> [String] {
        var failures: [String] = []
        if !evidence.storeReliable { failures.append("unreliable_store") }
        if previous.foregroundScenes.isEmpty { failures.append("no_foreground_scenes") }
        if let earliest = evidence.earliestOpen, let connected = evidence.postConnectionOpen {
            if !previous.foregroundScenes.isDisjoint(with: earliest.union(connected)) {
                failures.append("preserved_scene")
            }
        } else {
            failures.append("missing_open_sessions")
        }
        if explicit {
            let forwarded = evidence.forwarded.union(previous.discardedScenes)
            if evidence.invalidForwarding || !forwarded.isSubset(of: previous.foregroundScenes) {
                failures.append("invalid_forwarding")
            }
            if previous.foregroundScenes.isEmpty || !previous.foregroundScenes.isSubset(of: forwarded) {
                failures.append("missing_discard_callback")
            }
        }
        return failures
    }
}
