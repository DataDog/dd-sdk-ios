/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import UIKit
import os.signpost
import DatadogCore
import DatadogRUM

final class ImpactEvidence: @unchecked Sendable {
    static let shared = ImpactEvidence()
    private let lock = NSLock()
    private var rows: [[String: Any]] = []
    private var timer: DispatchSourceTimer?
    private let samplingQueue = DispatchQueue(label: "impact.metrics", qos: .utility)
    private var sealed = false
    private let log = OSLog(subsystem: "com.datadoghq.application-impact", category: .pointsOfInterest)
    private var interval: OSSignpostID?
    private var phase = "launch"
    private var previousIdleTimerSetting: Bool?
    let runID = ProcessInfo.processInfo.environment["IMPACT_RUN_ID"] ?? ""
    let nonce = ProcessInfo.processInfo.environment["IMPACT_NONCE"] ?? ""
    let source = Bundle.main.object(forInfoDictionaryKey: "ImpactSource") as? String ?? ""
    let fixture = Bundle.main.object(forInfoDictionaryKey: "ImpactFixture") as? String ?? ""
    let framework = Bundle.main.object(forInfoDictionaryKey: "ImpactFramework") as? String ?? ""

    func record(_ kind: String, _ fields: [String: Any] = [:]) {
        lock.lock()
        defer { lock.unlock() }
        guard !sealed else { return }
        var row = fields
        row["kind"] = kind
        row["sequence"] = rows.count + 1
        row["uptime_ns"] = DispatchTime.now().uptimeNanoseconds
        row["phase"] = phase
        rows.append(row)
    }

    @MainActor
    func configure() -> Bool {
        guard UUID(uuidString: runID) != nil, UUID(uuidString: nonce) != nil, runID != nonce,
              source.count == 40, fixture.count == 64,
              let token = Bundle.main.object(forInfoDictionaryKey: "ImpactToken") as? String,
              !token.isEmpty, !token.contains("$(") else { return false }
        let environment = ProcessInfo.processInfo.environment
        guard environment["MULTISCENE_CODE_IDENTITY_RUN_ID"] == runID,
              environment["MULTISCENE_CODE_IDENTITY_REVISION"] == source else { return false }
        do { try InstalledCodeReceipt.writeIfRequested(runID: runID) }
        catch { return false }
        previousIdleTimerSetting = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        Datadog.initialize(
            with: .init(clientToken: token, env: "integration", service: "ios-s3-application-impact"),
            trackingConsent: .granted
        )
        var config = RUM.Configuration(applicationID: "43cbc59b-0626-438b-a3d9-c6417a4545a3")
        config.uiKitViewsPredicate = framework == "UIKit" ? DefaultUIKitRUMViewsPredicate() : nil
        config.uiKitActionsPredicate = DefaultUIKitRUMActionsPredicate()
        config.swiftUIViewsPredicate = nil
        config.viewEventMapper = { event in
            ImpactEvidence.shared.record("view", ["id": event.view.id, "name": event.view.name ?? "", "active": event.view.isActive ?? false])
            return event
        }
        RUM.enable(with: config)
        record("launch", ["pid": ProcessInfo.processInfo.processIdentifier, "source": source,
            "fixture": fixture, "framework": framework, "run_id": runID, "nonce": nonce])
        return true
    }

    @MainActor
    func awaitRecorder() async throws {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let marker = directory.appendingPathComponent("impact-ready-" + runID)
        let admission = directory.appendingPathComponent("impact-admission-" + runID + ".json")
        let deadline = ProcessInfo.processInfo.systemUptime + 60
        while ProcessInfo.processInfo.systemUptime < deadline {
            // The host copies the complete admission first, then publishes the nonce marker.
            if let data = try? Data(contentsOf: marker), String(data: data, encoding: .utf8) == nonce {
                let value = try JSONSerialization.jsonObject(with: Data(contentsOf: admission)) as? [String: Any]
                guard let value, Set(value.keys) == ["state", "run_id", "nonce", "source", "fixture", "framework", "pid"],
                      value["state"] as? String == "TRACE_READY", value["run_id"] as? String == runID,
                      value["nonce"] as? String == nonce, value["source"] as? String == source,
                      value["fixture"] as? String == fixture, value["framework"] as? String == framework,
                      value["pid"] as? Int32 == ProcessInfo.processInfo.processIdentifier else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                record("admission", value)
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw CocoaError(.fileReadUnknown)
    }

    @MainActor
    func startSampling() {
        let timer = DispatchSource.makeTimerSource(queue: samplingQueue)
        timer.setEventHandler { [weak self] in self?.sample() }
        timer.schedule(deadline: .now(), repeating: .seconds(1), leeway: .milliseconds(10))
        timer.activate()
        self.timer = timer
    }

    private func sample(role: String = "periodic") {
        dispatchPrecondition(condition: .onQueue(samplingQueue))
        var usage = rusage()
        var memory = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &memory) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard getrusage(RUSAGE_SELF, &usage) == 0, result == KERN_SUCCESS,
              count >= mach_msg_type_number_t(MemoryLayout.offset(of: \task_vm_info_data_t.min_address)! / MemoryLayout<integer_t>.size)
        else { record("metric-failure"); return }
        let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        record("sample", ["sample_role": role, "cpu_seconds": cpu, "footprint_bytes": memory.phys_footprint,
            "thermal": ProcessInfo.processInfo.thermalState.rawValue,
            "low_power": ProcessInfo.processInfo.isLowPowerModeEnabled])
    }

    @MainActor
    func begin(_ name: String) {
        samplingQueue.sync {
            lock.lock(); phase = name; lock.unlock()
            record("phase-begin", ["name": name])
            interval = OSSignpostID(log: log)
            if let interval { os_signpost(.begin, log: log, name: "Workload", signpostID: interval, "%{public}@ %{public}@", runID as NSString, name as NSString) }
            sample(role: "begin")
        }
    }

    @MainActor
    func end(_ name: String) {
        samplingQueue.sync {
            sample(role: "end")
            if let interval { os_signpost(.end, log: log, name: "Workload", signpostID: interval, "%{public}@ %{public}@", runID as NSString, name as NSString) }
            interval = nil
            record("phase-end", ["name": name])
            lock.lock(); phase = "transition"; lock.unlock()
        }
    }

    @MainActor
    func topology(window: UIWindow, step: String, cycle: Int) -> Bool {
        guard let scene = window.windowScene, scene.activationState == .foregroundActive,
              window.isKeyWindow, !window.isHidden, window.alpha > 0, UIScreen.screens.count == 1,
              window.bounds.size == window.screen.bounds.size,
              UIApplication.shared.connectedScenes.filter({ $0.activationState == .foregroundActive }).count == 1
        else { record("topology-failure", ["step": step, "cycle": cycle]); return false }
        record("boundary", ["step": step, "cycle": cycle, "scene": scene.session.persistentIdentifier,
            "window": String(describing: ObjectIdentifier(window)), "width": window.bounds.width,
            "height": window.bounds.height, "screen_id": String(describing: ObjectIdentifier(window.screen)),
            "screen_count": UIScreen.screens.count, "screen_width": window.screen.bounds.width,
            "screen_height": window.screen.bounds.height, "scale": window.screen.scale,
            "maximum_fps": window.screen.maximumFramesPerSecond,
            "windows": scene.windows.map { ["owned": $0 === window, "key": $0.isKeyWindow,
                "hidden": $0.isHidden, "root": $0.rootViewController.map { String(describing: type(of: $0)) } ?? "nil"] }])
        return true
    }

    @MainActor
    func finish(_ state: String, reason: String = "") {
        timer?.cancel(); timer = nil
        if let previousIdleTimerSetting { UIApplication.shared.isIdleTimerDisabled = previousIdleTimerSetting }
        let records: [[String: Any]] = samplingQueue.sync {
            lock.lock()
            defer { lock.unlock() }
            rows.append(["kind": "terminal", "state": state, "reason": reason, "sequence": rows.count + 1,
                         "uptime_ns": DispatchTime.now().uptimeNanoseconds, "phase": phase])
            sealed = true
            return rows
        }
        let document: [String: Any] = ["schema_version": 1, "run_id": runID, "nonce": nonce,
            "source": source, "fixture": fixture, "framework": framework,
            "pid": ProcessInfo.processInfo.processIdentifier, "records": records]
        do {
            let data = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try data.write(to: directory.appendingPathComponent("impact-" + runID + ".json"), options: .atomic)
            print("IMPACT_RESULT \(runID) \(state)")
        } catch { print("IMPACT_PERSISTENCE_FAILED") }
    }
}

@MainActor
protocol ImpactJourney: AnyObject {
    var root: UIViewController { get }
    func perform(step: Int, cycle: Int)
    func verify(step: Int, cycle: Int) -> Bool
}

@MainActor
final class ImpactDriver {
    let journey: ImpactJourney
    let window: UIWindow
    init(journey: ImpactJourney, window: UIWindow) { self.journey = journey; self.window = window }

    func run() async {
        let evidence = ImpactEvidence.shared
        do {
            try await evidence.awaitRecorder()
            guard journey.verify(step: 0, cycle: 0), evidence.topology(window: window, step: "ready", cycle: -1) else {
                evidence.finish("INVALID", reason: "initial owned foreground display not ready"); return
            }
            evidence.startSampling()
            for (phase, cycles) in [("warmup", 2), ("active", 12)] {
                evidence.begin(phase)
                let start = ProcessInfo.processInfo.systemUptime
                for cycle in 0..<cycles {
                    for step in 0..<8 {
                        let slot = start + Double(cycle * 8 + step)
                        guard abs(ProcessInfo.processInfo.systemUptime - slot) < 0.2 else {
                            evidence.finish("INVALID", reason: "late workload boundary"); return
                        }
                        journey.perform(step: step, cycle: cycle)
                        try await sleepUntil(slot + 0.8)
                        guard journey.verify(step: step, cycle: cycle), evidence.topology(window: window, step: String(step), cycle: cycle) else {
                            evidence.finish("INVALID", reason: "native workload boundary not complete"); return
                        }
                        try await sleepUntil(slot + 1)
                    }
                }
                evidence.end(phase)
            }
            evidence.begin("idle")
            try await Task.sleep(nanoseconds: 30_000_000_000)
            evidence.end("idle")
            guard evidence.topology(window: window, step: "terminal", cycle: 12) else {
                evidence.finish("INVALID", reason: "lost final scene"); return
            }
            evidence.finish("SCENARIO_COMPLETE")
        } catch { evidence.finish("INVALID", reason: "workload cancelled") }
    }

    private func sleepUntil(_ uptime: Double) async throws {
        let delay = uptime - ProcessInfo.processInfo.systemUptime
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
    }
}
