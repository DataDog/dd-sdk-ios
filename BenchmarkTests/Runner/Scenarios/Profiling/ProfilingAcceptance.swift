/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if MULTISCENE_PROFILING_ACCEPTANCE
import CryptoKit
import Foundation
import UIKit
import DatadogCore
import DatadogInternal
import DatadogRUM
import DatadogProfiling

/// Opt-in acceptance instrumentation. It is absent from ordinary benchmark builds.
@MainActor
final class ProfilingAcceptanceCoordinator {
    static let shared = ProfilingAcceptanceCoordinator()
    private(set) var recorder: ProfilingAcceptanceRecorder?
    private(set) var preparationError: String?

    func configure() {
        do {
            let environment = ProcessInfo.processInfo.environment
            let runID = environment["MULTISCENE_PROFILE_RUN_ID"] ?? ""
            let revision = environment["MULTISCENE_PROFILE_SOURCE_REVISION"] ?? ""
            guard runID.hasPrefix("exp187-"),
                  UUID(uuidString: String(runID.dropFirst(7))) != nil,
                  revision.range(of: "^[a-f0-9]{40}$", options: .regularExpression) != nil else {
                throw ProfilingAcceptanceError.invalidIdentity
            }
            let documents = try FileManager.default.url(
                for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )
            let receiptURL = documents.appendingPathComponent(runID + ".json")
            guard !FileManager.default.fileExists(atPath: receiptURL.path) else {
                throw ProfilingAcceptanceError.reusedReceipt
            }
            let recorder = ProfilingAcceptanceRecorder(runID: runID, revision: revision, receiptURL: receiptURL)
            self.recorder = recorder
            try recorder.assertCheckpoint(1, passed: true)
            let info = try AppInfo()
            guard !info.clientToken.isEmpty, UUID(uuidString: info.applicationID) != nil else {
                throw ProfilingAcceptanceError.missingConfiguration
            }

            try InstalledCodeReceipt.writeIfRequested(runID: runID)
            Datadog.initialize(with: .benchmark(info: info), trackingConsent: .granted)
            try CoreRegistry.default.register(feature: recorder)
            Profiling.enable(with: .init(
                applicationLaunchSampleRate: recorder.configuration.applicationLaunchSampleRate,
                continuousSampleRate: recorder.configuration.continuousSampleRate
            ))
            RUM.enable(
                with: RUM.Configuration(
                    applicationID: info.applicationID,
                    sessionSampleRate: 100,
                    longTaskThreshold: nil,
                    appHangThreshold: nil,
                    vitalsUpdateFrequency: nil,
                    viewEventMapper: { event in
                        recorder.observe(view: event)
                        return event
                    },
                    trackAnonymousUser: false,
                    trackMemoryWarnings: false,
                    trackSlowFrames: false
                )
            )
            RUMMonitor.shared().addAttribute(forKey: "multiscene.run_id", value: runID)
            RUMMonitor.shared().addAttribute(forKey: "multiscene.experiment", value: "EXP-187")
        } catch {
            preparationError = "INVALID: profiling acceptance preparation failed"
            _ = recorder?.finish(status: "INVALID")
            print("EXP187 INVALID preparation")
        }
    }
}

final class ProfilingAcceptanceSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else {
            return
        }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = ProfilingAcceptanceViewController()
        self.window = window
        window.makeKeyAndVisible()
    }
}

@MainActor
private final class ProfilingAcceptanceViewController: UIViewController {
    private let status = UILabel()
    private var started = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        status.numberOfLines = 0
        status.textAlignment = .center
        status.text = "EXP-187 preparing"
        status.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(status)
        NSLayoutConstraint.activate([
            status.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            status.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            status.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !started else {
            return
        }
        started = true
        guard let recorder = ProfilingAcceptanceCoordinator.shared.recorder,
              ProfilingAcceptanceCoordinator.shared.preparationError == nil else {
            status.text = ProfilingAcceptanceCoordinator.shared.preparationError ?? "INVALID: missing recorder"
            return
        }
        Task {
            do {
                try await execute(recorder)
                guard recorder.finish(status: "PASS") else {
                    status.text = "EXP-187 INVALID receipt-write"
                    return
                }
                status.text = "EXP-187 native checks 12/12\nProfile backend verification pending\n\(recorder.runID)"
            } catch {
                _ = recorder.finish(status: "FAIL")
                status.text = "EXP-187 native check failed\n\(recorder.runID)"
            }
        }
    }

    private func execute(_ recorder: ProfilingAcceptanceRecorder) async throws {
        let monitor = RUMMonitor.shared()
        try await checkpoint(2, recorder: recorder) {
            UIApplication.shared.connectedScenes.count == 1
                && self.view.window?.windowScene?.activationState == .foregroundActive
                && self.view.window?.isHidden == false
        }

        recorder.command("view:A")
        monitor.startView(key: "exp187.view.A", name: "EXP187.StartA")
        try await checkpoint(3, recorder: recorder) {
            recorder.hasView("EXP187.StartA", active: true)
                && recorder.snapshot().ttidCount == 1 && recorder.snapshot().profilingRunning
        }

        let work = Task.detached(priority: .utility) {
            let deadline = ProcessInfo.processInfo.systemUptime + 12
            var sum = 0.0
            while ProcessInfo.processInfo.systemUptime < deadline && !Task.isCancelled {
                for value in 1...10_000 { sum += sin(Double(value)) }
            }
            return sum
        }
        defer { work.cancel() }

        recorder.command("start:A")
        monitor.startOperation(name: "exp187.parallel", operationKey: recorder.key("A"), options: ProfilingOptions(sampleRate: 100))
        try await checkpoint(4, recorder: recorder) { recorder.matchesStep(count: 1, key: "A", step: .start, view: "EXP187.StartA") }
        try await Task.sleep(nanoseconds: 1_000_000_000)

        recorder.command("view:B")
        monitor.stopView(key: "exp187.view.A")
        monitor.startView(key: "exp187.view.B", name: "EXP187.StartB")
        try await checkpoint(5, recorder: recorder) {
            recorder.hasView("EXP187.StartA", active: false) && recorder.hasView("EXP187.StartB", active: true)
        }
        recorder.command("start:B")
        monitor.startOperation(name: "exp187.parallel", operationKey: recorder.key("B"), options: ProfilingOptions(sampleRate: 100))
        try await checkpoint(6, recorder: recorder) {
            let steps = recorder.snapshot().operations
            return recorder.matchesStep(count: 2, key: "B", step: .start, view: "EXP187.StartB")
                && steps.count == 2 && steps[0].vital.id != steps[1].vital.id
        }
        try await Task.sleep(nanoseconds: 2_000_000_000)

        recorder.command("view:C")
        monitor.stopView(key: "exp187.view.B")
        monitor.startView(key: "exp187.view.C", name: "EXP187.Finish")
        try await checkpoint(7, recorder: recorder) {
            recorder.hasView("EXP187.StartB", active: false) && recorder.hasView("EXP187.Finish", active: true)
        }
        recorder.command("end:B")
        monitor.succeedOperation(name: "exp187.parallel", operationKey: recorder.key("B"))
        try await checkpoint(8, recorder: recorder) { recorder.matchesStep(count: 3, key: "B", step: .end, view: "EXP187.Finish") }
        try await Task.sleep(nanoseconds: 3_000_000_000)

        recorder.command("end:A")
        monitor.succeedOperation(name: "exp187.parallel", operationKey: recorder.key("A"))
        try await checkpoint(9, recorder: recorder) { recorder.matchesStep(count: 4, key: "A", step: .end, view: "EXP187.Finish") }
        let snapshot = recorder.snapshot()
        try recorder.assertCheckpoint(
            10,
            passed: snapshot.operations.count == 4
                && Set(snapshot.operations.map { $0.vital.id }).count == 4
                && Set(snapshot.operations.map(\.sessionID)).count == 1
                && snapshot.operations.allSatisfy { !$0.sessionID.isEmpty && $0.vital.name == "exp187.parallel" }
                && snapshot.operations.map(\.operationKey) == ["A", "B", "B", "A"].map(recorder.key)
                && snapshot.operations.map(\.step) == ["start", "start", "end", "end"]
        )

        recorder.command("stop:C")
        monitor.stopView(key: "exp187.view.C")
        try await checkpoint(11, recorder: recorder) {
            let views = recorder.snapshot().views
            return views.count == 4 && Set(views.map(\.id)).count == 4
                && Set(views.map(\.name)) == Set(["ApplicationLaunch", "EXP187.StartA", "EXP187.StartB", "EXP187.Finish"])
                && Set(views.map(\.sessionID)).count == 1
                && views.allSatisfy { $0.active == false }
        }
        let expected = recorder.expectedProfileVitals()
        try recorder.assertCheckpoint(
            12,
            passed: expected.count == 2
                && (expected[0].duration ?? 0) > (expected[1].duration ?? 0)
                && (expected[1].duration ?? 0) > 0
        )
        // Allow the normal 60-second continuous timer and upload; Operations do not start a standalone profile.
        try await Task.sleep(nanoseconds: 70_000_000_000)
    }

    private func checkpoint(_ number: Int, recorder: ProfilingAcceptanceRecorder, ready: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 15
        while !ready() && ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try recorder.assertCheckpoint(number, passed: ready())
        status.text = "EXP-187 native check \(number)/12\n\(recorder.runID)"
    }
}

enum ProfilingAcceptanceError: Error {
    case invalidIdentity
    case reusedReceipt
    case missingConfiguration
    case failedCheckpoint
}

/// Records observations without consuming bus messages or doing I/O on an SDK callback.
final class ProfilingAcceptanceRecorder: DatadogFeature, FeatureMessageReceiver, @unchecked Sendable {
    static let name = "profiling-acceptance-recorder"
    var messageReceiver: FeatureMessageReceiver { self }
    let runID: String
    let configuration = Configuration()
    private let revision: String
    private let receiptURL: URL
    private let lock = NSLock()
    private var observed = Snapshot()
    private var checkpoints: [Checkpoint] = []
    private var boundaries: [String] = []

    struct Configuration: Encodable {
        let applicationLaunchSampleRate: SampleRate = 0
        let continuousSampleRate: SampleRate = 100
    }

    struct Operation: Encodable {
        let vital: Vital
        let operationKey: String
        let step: String
        let viewID: String
        let viewName: String
        let sessionID: String
        let referenceTime: TimeInterval
        let serverTimeOffset: TimeInterval
        let profilingRunning: Bool
    }

    struct View: Encodable {
        let id: String
        let name: String
        let sessionID: String
        let active: Bool?
    }

    struct Snapshot: Encodable {
        var ttidCount = 0
        var profilingRunning = false
        var operations: [Operation] = []
        var views: [View] = []
    }

    struct Checkpoint: Encodable {
        let number: Int
        let passed: Bool
        let boundary: Int
        let operationCount: Int
        let profilingRunning: Bool
    }

    init(runID: String, revision: String, receiptURL: URL) {
        self.runID = runID
        self.revision = revision
        self.receiptURL = receiptURL
    }

    func key(_ suffix: String) -> String { "\(runID)/\(suffix)" }

    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        locked {
            if case .context(let context) = message {
                observed.profilingRunning = context.additionalContext(ofType: ProfilingContext.self)?.status == .running
            } else if case .payload(let payload) = message {
                if payload is TTIDMessage {
                    observed.ttidCount += 1
                } else if let payload = payload as? OperationMessage {
                    observed.operations.append(Operation(
                        vital: payload.operation,
                        operationKey: payload.operation.operationKey ?? "",
                        step: payload.operation.stepType?.rawValue ?? "",
                        viewID: (payload.attributes[RUMCoreContext.IDs.viewID] as? [String])?.first ?? "",
                        viewName: (payload.attributes[RUMCoreContext.IDs.viewName] as? [String])?.first ?? "",
                        sessionID: payload.attributes[RUMCoreContext.IDs.sessionID] as? String ?? "",
                        referenceTime: payload.operation.date.timeIntervalSinceReferenceDate,
                        serverTimeOffset: payload.operation.serverTimeOffset,
                        profilingRunning: observed.profilingRunning
                    ))
                }
            }
        }
        return false
    }

    func observe(view: RUMViewEvent) {
        locked {
            let value = View(id: view.view.id, name: view.view.name ?? "", sessionID: view.session.id, active: view.view.isActive)
            observed.views.removeAll { $0.id == value.id }
            observed.views.append(value)
        }
    }

    func snapshot() -> Snapshot { locked { observed } }

    func hasView(_ name: String, active: Bool) -> Bool {
        let views = snapshot().views.filter { $0.name == name }
        return views.count == 1 && views[0].active == active
    }

    func matchesStep(count: Int, key suffix: String, step: RUMVitalOperationStepEvent.Vital.StepType, view: String) -> Bool {
        let state = snapshot()
        let views = state.views.filter { $0.name == view }
        guard state.operations.count == count, let operation = state.operations.last, views.count == 1 else {
            return false
        }
        return operation.operationKey == key(suffix) && operation.step == step.rawValue
            && operation.vital.name == "exp187.parallel" && operation.viewID == views[0].id
            && operation.viewName == view && operation.sessionID == views[0].sessionID
            && operation.profilingRunning
    }

    func command(_ name: String) { locked { boundaries.append("command:" + name) } }

    func assertCheckpoint(_ number: Int, passed: Bool) throws {
        locked {
            boundaries.append("assert:\(number)")
            checkpoints.append(Checkpoint(
                number: number,
                passed: passed,
                boundary: boundaries.count,
                operationCount: observed.operations.count,
                profilingRunning: observed.profilingRunning
            ))
        }
        try persist(status: passed ? "RUNNING" : "FAIL")
        guard passed else { throw ProfilingAcceptanceError.failedCheckpoint }
    }

    func expectedProfileVitals() -> [Vital] {
        let operations = snapshot().operations
        return operations.filter { $0.step == "start" }.compactMap { start in
            let ends = operations.filter { $0.step == "end" && $0.operationKey == start.operationKey }
            guard ends.count == 1 else {
                return nil
            }
            var vital = start.vital
            vital.duration = ends[0].vital.date.timeIntervalSince(start.vital.date).dd.toInt64Nanoseconds
            return vital
        }
    }

    func finish(status: String) -> Bool {
        do {
            try persist(status: status)
            print("EXP187 native \(status) \(runID)")
            return true
        } catch {
            print("EXP187 INVALID receipt-write")
            return false
        }
    }

    private func persist(status: String) throws {
        struct Receipt: Encodable {
            let schemaVersion = 2
            let configuration: Configuration
            let experiment = "EXP-187"
            let nativeStatus: String
            let backendStatus = "NOT_VERIFIED"
            let runID: String
            let sourceRevision: String
            let platform: String
            let processID = ProcessInfo.processInfo.processIdentifier
            let observations: Snapshot
            let checkpoints: [Checkpoint]
            let boundaries: [String]
            let expectedProfileVitals: [Vital]
        }
#if targetEnvironment(simulator)
        let platform = "SIMULATOR_MECHANICS_ONLY"
#else
        let platform = "PHYSICAL_DEVICE"
#endif
        let state = locked { (observed, checkpoints, boundaries) }
        let receipt = Receipt(
            configuration: configuration,
            nativeStatus: status,
            runID: runID,
            sourceRevision: revision,
            platform: platform,
            observations: state.0,
            checkpoints: state.1,
            boundaries: state.2,
            expectedProfileVitals: expectedProfileVitals()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(receipt).write(to: receiptURL, options: .atomic)
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

/// Local physical-run identity evidence, written before SDK initialization.
private enum InstalledCodeReceipt {
    static func writeIfRequested(runID: String) throws {
        let environment = ProcessInfo.processInfo.environment
        guard let requestedRun = environment["MULTISCENE_CODE_IDENTITY_RUN_ID"] else {
            return
        }
        let revision = environment["MULTISCENE_CODE_IDENTITY_REVISION"] ?? ""
        guard requestedRun == runID,
              runID.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil,
              revision.range(of: "^[a-f0-9]{40}$", options: .regularExpression) != nil,
              let executable = Bundle.main.executableURL,
              let bundleID = Bundle.main.bundleIdentifier else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let manager = FileManager.default
        let documents = try manager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let receipt = documents.appendingPathComponent(runID + ".installed-code.json")
        guard !manager.fileExists(atPath: receipt.path) else { throw CocoaError(.fileWriteFileExists) }
        let root = Bundle.main.bundleURL
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let files = manager.enumerator(at: root, includingPropertiesForKeys: keys) else {
            throw CocoaError(.fileReadUnknown)
        }
        var hashes: [String: String] = [:]
        for case let file as URL in files {
            let properties = try file.resourceValues(forKeys: Set(keys))
            guard properties.isRegularFile == true, properties.isSymbolicLink != true else { continue }
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            let header = try handle.read(upToCount: 4) ?? Data()
            let magic = header.map { String(format: "%02x", $0) }.joined()
            guard ["cffaedfe", "feedfacf", "cafebabe", "bebafeca", "cafebabf", "bfbafeca"].contains(magic) else {
                continue
            }
            var digest = SHA256()
            digest.update(data: header)
            while let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty {
                digest.update(data: chunk)
            }
            let relative = String(file.path.dropFirst(root.path.count + 1))
            hashes[relative] = digest.finalize().map { String(format: "%02x", $0) }.joined()
        }
        let mainPath = String(executable.path.dropFirst(root.path.count + 1))
        guard hashes[mainPath] != nil else { throw CocoaError(.fileReadCorruptFile) }
        let value: [String: Any] = [
            "schemaVersion": 1, "runID": runID, "sourceRevision": revision,
            "processID": ProcessInfo.processInfo.processIdentifier, "bundleIdentifier": bundleID,
            "boundary": "before-sdk-initialization", "executable": mainPath, "binaries": hashes
        ]
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]).write(to: receipt, options: .atomic)
    }
}
#endif
