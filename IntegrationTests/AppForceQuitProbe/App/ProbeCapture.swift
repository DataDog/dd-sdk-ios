/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2026-Present Datadog, Inc.
 */

import CryptoKit
import Darwin
import UIKit

internal struct ProbeEvent: Codable {
    var name: String
    var scene: String?
    var role: String?
    var enqueued: ProbeStamp
    var completed: ProbeStamp
    var durableMilliseconds: Double
}

internal struct ProbeObservation: Codable {
    var schemaVersion = 1
    var platform = "ios"
    var previous: ProbeRun?
    var current: ProbeRun
    var evidence: ProbeSceneEvidence
    var naive: Bool
    var automatic: ProbeVerdict
    var explicit: ProbeVerdict
    var reporterLifecycle: ProbeVerdict
    var reporter: ProbeReporterEvidence
    var metricKit: [ProbeDiagnostic]
    var events: [ProbeEvent]
    var captureErrors: [String]
    var trialID: String
    var crashReporting = "kscrash_2.5.1_sdk_monitors_local_only"
    var sdkWriter = "not_exercised"
}

@MainActor
internal final class ProbeCapture: ObservableObject {
    static let shared = ProbeCapture()
    @Published var status = "Starting"
    let store: ProbeStore?
    let previous: ProbeRun?
    var current: ProbeRun
    var evidence: ProbeSceneEvidence
    var events: [ProbeEvent] = []
    var errors: [String] = []
    var trialID = "unassigned"
    var reporter = ProbeReporterEvidence()
    var diagnostics: [ProbeDiagnostic] = []
    private var crashReporter: ProbeCrashReporter?
    private var metricCollector: AnyObject?
    private var observers: [NSObjectProtocol] = []
    private let exportQueue = DispatchQueue(label: "probe.export")
    private var allocations: [Data] = []
    private var memoryTimer: Timer?
    private var priorFileData: Data?

    static func stamp() -> ProbeStamp {
        ProbeStamp(wall: Date().timeIntervalSince1970, uptime: ProcessInfo.processInfo.systemUptime)
    }

    private init() {
        let files = FileManager.default
        let documents = files.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = documents.appendingPathComponent("ForceQuitProbe", isDirectory: true)
        store = try? ProbeStore(directory: directory)
        let old = store?.load()
        previous = old?.run
        priorFileData = try? Data(contentsOf: directory.appendingPathComponent("current.json"))
        let installFile = directory.appendingPathComponent("installation.txt")
        let install: String
        if let existing = try? String(contentsOf: installFile, encoding: .utf8),
           UUID(uuidString: existing) != nil {
            install = existing
        } else {
            install = UUID().uuidString
            do { try store?.atomic(Data(install.utf8), to: installFile) } catch {
                errors.append("installation_write_failed")
            }
        }
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        let bootKnown = sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0
        var process = kinfo_proc()
        var processSize = MemoryLayout<kinfo_proc>.size
        var query = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        let debugKnown = sysctl(&query, u_int(query.count), &process, &processSize, nil, 0) == 0
        let debugging = !debugKnown || process.kp_proc.p_flag & P_TRACED != 0
        #if targetEnvironment(simulator)
        let physical = false
        #else
        let physical = true
        #endif
        #if PROBE_SWIFTUI
        let model = "SwiftUI"
        #else
        let model = "UIKit"
        #endif
        let environment = ProcessInfo.processInfo.environment
        let automated =
            environment["XCTestConfigurationFilePath"] != nil || environment["PROBE_AUTOMATION"] == "1"
            || ProcessInfo.processInfo.arguments.contains("--probe-automation")
        let info = Bundle.main.infoDictionary ?? [:]
        current = ProbeRun(
            id: UUID().uuidString,
            started: Self.stamp(),
            compatibility: [
                "app": info["CFBundleShortVersionString"] as? String ?? "unknown",
                "build": info["CFBundleVersion"] as? String ?? "unknown",
                "source": info["ProbeSourceSHA"] as? String ?? "unattested",
                "pid": String(getpid()),
                "install": install, "os": ProcessInfo.processInfo.operatingSystemVersionString,
                "boot": bootKnown ? "\(boot.tv_sec).\(boot.tv_usec)" : "", "model": model
            ],
            physicalDevice: physical,
            debugging: debugging,
            automation: automated
        )
        evidence = ProbeSceneEvidence(
            earliestOpen: nil,
            postConnectionOpen: nil,
            storeReliable: old?.reliable ?? (store != nil)
        )
        if store == nil { errors.append("store_unavailable") }
        if !bootKnown { errors.append("boot_unavailable") }
        if !debugKnown { errors.append("debug_status_unavailable") }
    }

    private func hash(_ value: String) -> String {
        let salt = current.compatibility["install"] ?? current.id
        return SHA256.hash(data: Data((salt + value).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func openIDs(_ application: UIApplication) -> Set<String> {
        Set(
            application.openSessions.filter { $0.role == .windowApplication }.map {
                hash($0.persistentIdentifier)
            }
        )
    }

    func start(_ application: UIApplication) {
        guard observers.isEmpty else {
            return
        }
        // Preserve the previous record and earliest open set before any new scene writes.
        evidence.earliestOpen = openIDs(application)
        if let data = priorFileData, let store = store {
            let path = store.directory.appendingPathComponent("previous-at-\(current.id).json")
            do { try store.atomic(data, to: path) } catch {
                errors.append("previous_snapshot_failed")
                evidence.storeReliable = false
            }
            priorFileData = nil
        }
        if let store = store {
            let crash = ProbeCrashReporter(directory: store.directory, runID: current.id, previousID: previous?.id)
            crashReporter = crash
            current.crashReporterInstalled = crash.installed
            reporter = crash.evidence
            if #available(iOS 27.0, *) {
                metricCollector = ProbeMetricCollector(directory: store.directory) { [weak self] diagnostic in
                    self?.diagnostics.append(diagnostic)
                    self?.record("metrickit_diagnostic_received")
                }
            }
        }
        let names: [Notification.Name] = [
            UIScene.willConnectNotification, UIScene.didActivateNotification,
            UIScene.willDeactivateNotification,
            UIScene.willEnterForegroundNotification, UIScene.didEnterBackgroundNotification,
            UIScene.didDisconnectNotification
        ]
        for name in names {
            observers.append(
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                    MainActor.assumeIsolated {
                        guard let scene = note.object as? UIScene else {
                            return
                        }
                        self?.scene(scene, event: note.name.rawValue)
                    }
                }
            )
        }
        for scene in application.connectedScenes { self.scene(scene, event: "initial_connected") }
        record("launch_earliest_open_sessions")
        if ProcessInfo.processInfo.arguments.contains("--probe-verify-reporter-failure") {
            verifyReporterRefusal()
        }
    }

    func postConnection(_ application: UIApplication) {
        evidence.postConnectionOpen = (evidence.postConnectionOpen ?? []).union(openIDs(application))
        record("post_connection_open_sessions")
    }

    func scene(_ scene: UIScene, event: String) {
        let id = hash(scene.session.persistentIdentifier)
        let role = scene.session.role.rawValue
        guard scene.session.role == .windowApplication else {
            record(event, scene: id, role: role)
            return
        }
        let wasActive = !current.activeScenes.isEmpty
        if event == UIScene.didActivateNotification.rawValue
            || (event == "initial_connected" && scene.activationState == .foregroundActive) {
            current.foregroundScenes.insert(id)
            current.activeScenes.insert(id)
            if !wasActive {
                current.foregroundEnter = Self.stamp()
                current.foregroundExit = nil
            }
        }
        if [
            UIScene.willDeactivateNotification.rawValue, UIScene.didEnterBackgroundNotification.rawValue,
            UIScene.didDisconnectNotification.rawValue
        ].contains(event) {
            current.activeScenes.remove(id)
            if wasActive && current.activeScenes.isEmpty { current.foregroundExit = Self.stamp() }
        }
        record(event, scene: id, role: role)
    }

    func discard(_ sessions: Set<UISceneSession>) {
        let ids = Set(
            sessions.filter { $0.role == .windowApplication }.map { hash($0.persistentIdentifier) }
        )
        let tracked = (previous?.foregroundScenes ?? []).union(current.foregroundScenes)
        if ids.isEmpty || !ids.isSubset(of: tracked) { evidence.invalidForwarding = true }
        evidence.forwarded.formUnion(ids.intersection(previous?.foregroundScenes ?? []))
        current.discardedScenes.formUnion(ids.intersection(current.foregroundScenes))
        record("forwarded_did_discard_\(ids.count)")
    }

    func terminate() {
        // The physical removal trial delivered this callback. It is not a normal-exit oracle.
        current.terminationCallbackObserved = true
        current.terminationObservedAt = Self.stamp()
        record("application_will_terminate")
    }

    func record(_ name: String, scene: String? = nil, role: String? = nil) {
        let enqueued = Self.stamp()
        var latency = -1.0
        do {
            guard let store = store else { throw ProbeStoreError.ioFailure }
            latency = try store.checkpoint(current)
        } catch {
            evidence.storeReliable = false
            errors.append("checkpoint_failed")
        }
        events.append(
            ProbeEvent(
                name: name,
                scene: scene,
                role: role,
                enqueued: enqueued,
                completed: Self.stamp(),
                durableMilliseconds: latency
            )
        )
        if events.count > 2_048 {
            events.removeFirst()
            errors.append("event_limit_reached")
        }
        refresh()
    }

    func observation() -> ProbeObservation {
        ProbeObservation(
            previous: previous,
            current: current,
            evidence: evidence,
            naive: ProbeClassifier.naive(previous: previous, current: current),
            automatic: ProbeClassifier.classify(
                previous: previous,
                current: current,
                evidence: evidence,
                explicit: false
            ),
            explicit: ProbeClassifier.classify(
                previous: previous,
                current: current,
                evidence: evidence,
                explicit: true
            ),
            reporterLifecycle: ProbeClassifier.reporterLifecycle(
                previous: previous, current: current, evidence: evidence, reporter: reporter
            ),
            reporter: reporter,
            metricKit: diagnostics,
            events: events,
            captureErrors: Array(Set(errors)).sorted(),
            trialID: trialID
        )
    }

    func refresh() {
        let value = observation()
        status =
            "Run \(current.id.prefix(8))\nTrial \(trialID)\nReporter: \(reporter.read.rawValue), installed \(current.crashReporterInstalled == true)\nReporter lifecycle: \(value.reporterLifecycle.outcome)\n\(value.reporterLifecycle.reasons.joined(separator: ", "))\nAutomatic: \(value.automatic.outcome)\n\(value.automatic.reasons.joined(separator: ", "))\nExplicit: \(value.explicit.outcome)\n\(value.explicit.reasons.joined(separator: ", "))\nMetricKit diagnostics: \(diagnostics.count)\nNaive: \(value.naive)\nEvents: \(events.count)\nErrors: \(errors.joined(separator: ", "))"
        guard let store = store, let data = try? JSONEncoder().encode(value) else {
            return
        }
        let destination = store.directory.appendingPathComponent("observation-\(current.id).json")
        let directory = store.directory
        exportQueue.async {
            do { try ProbeStore(directory: directory).atomic(data, to: destination) } catch {
                DispatchQueue.main.async { self.errors.append("observation_export_failed") }
            }
        }
    }

    func export() -> URL? {
        guard let store = store else {
            return nil
        }
        exportQueue.sync {}
        let target = store.directory.appendingPathComponent("observation-\(current.id).json")
        do {
            try store.atomic(try JSONEncoder().encode(observation()), to: target)
            return target
        } catch {
            errors.append("observation_export_failed")
            refresh()
            return nil
        }
    }

    func fault(_ name: String) {
        // Scenario labels are observations only and never become a crash/OOM classifier veto.
        record("control_requested_\(name)")
        switch name {
        case "managed_crash": fatalError("Dedicated force-quit probe controlled crash")
        case "native_crash": raise(SIGSEGV)
        case "hang_5s": Thread.sleep(forTimeInterval: 5)
        case "fatal_hang": while true { Thread.sleep(forTimeInterval: 1) }
        case "memory":
            guard memoryTimer == nil else {
                return
            }
            memoryTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self = self else {
                        return
                    }
                    var block = Data(count: 16 * 1_024 * 1_024)
                    block.withUnsafeMutableBytes { bytes in
                        guard let address = bytes.baseAddress else {
                            return
                        }
                        arc4random_buf(address, bytes.count)
                    }
                    self.allocations.append(block)
                }
            }
        case "stop_memory":
            memoryTimer?.invalidate()
            memoryTimer = nil
            allocations = []
        default: break
        }
    }

    func verifyReporterRefusal() {
        reporter = crashReporter?.verifyReadRefusal() ?? ProbeReporterEvidence()
        record("reporter_read_refusal_fixture")
    }

    func restoreReporterEvidence() {
        reporter = crashReporter?.evidence ?? ProbeReporterEvidence()
        record("reporter_startup_evidence_restored")
    }
}
