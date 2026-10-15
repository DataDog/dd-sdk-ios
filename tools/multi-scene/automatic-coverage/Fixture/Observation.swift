import Foundation
import UIKit
import DatadogCore
import DatadogRUM

// Observation never starts, stops, targets or renames a RUM view/action.
final class ObservationStore: @unchecked Sendable {
    static let shared = ObservationStore()
    private let lock = NSLock()
    private var sequence = 0
    private let output: URL
    init() {
        output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("events.jsonl")
        FileManager.default.createFile(atPath: output.path, contents: nil)
    }
    func append(_ kind: String, _ payload: [String: Any]) {
        lock.lock(); defer { lock.unlock() }
        sequence += 1
        let row: [String: Any] = ["sequence": sequence, "run_id": Settings.runID,
            "timestamp": Date().timeIntervalSince1970, "kind": kind, "payload": payload]
        guard let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]),
              let handle = try? FileHandle(forWritingTo: output) else { return }
        defer { try? handle.close() }
        do { try handle.seekToEnd(); try handle.write(contentsOf: data); try handle.write(contentsOf: Data([10])) }
        catch { print("EXP195 observation write failed") }
    }
    func event<T: Encodable>(_ value: T) {
        guard let data = try? JSONEncoder().encode(value),
              let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        append("rum", row)
    }
}
enum Settings {
    static func value(_ key: String, _ fallback: String = "") -> String {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: key), a.indices.contains(i + 1) else { return fallback }
        return a[i + 1]
    }
    static let runID = value("--run-id")
    static let layout = value("--layout", "stack")
    static let framework = Bundle.main.object(forInfoDictionaryKey: "FixtureFramework") as? String ?? "unknown"
}
@MainActor enum FixtureObservation {
    static var timer: Timer?
    static var previousGeometry = ""
    static var lifecycleObservers: [NSObjectProtocol] = []
    static func start() {
        ObservationStore.shared.append("launch", ["framework": Settings.framework, "layout": Settings.layout,
            "bundle": Bundle.main.bundleIdentifier ?? "", "os": UIDevice.current.systemVersion,
            "pid": ProcessInfo.processInfo.processIdentifier,
            "build_sdk": Bundle.main.object(forInfoDictionaryKey: "DTSDKName") ?? "missing",
            "multiple_scenes": UIApplication.shared.supportsMultipleScenes])
        Datadog.initialize(with: Datadog.Configuration(clientToken: "local-fixture-no-credentials",
            env: "exp195-automatic", service: "exp195-automatic"), trackingConsent: .granted)
        var configuration = RUM.Configuration(applicationID: "00000000-0000-0000-0000-000000000195")
        configuration.uiKitActionsPredicate = DefaultUIKitRUMActionsPredicate()
        if Settings.framework == "UIKit" {
            configuration.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
        } else {
            configuration.swiftUIViewsPredicate = DefaultSwiftUIRUMViewsPredicate()
            configuration.swiftUIActionsPredicate = DefaultSwiftUIRUMActionsPredicate(isLegacyDetectionEnabled: true)
        }
        configuration.telemetrySampleRate = 0
        configuration.customEndpoint = URL(string: "http://127.0.0.1:9/rum")!
        configuration.viewEventMapper = { ObservationStore.shared.event($0); return $0 }
        configuration.actionEventMapper = { ObservationStore.shared.event($0); return $0 }
        configuration.errorEventMapper = { ObservationStore.shared.event($0); return $0 }
        configuration.resourceEventMapper = { ObservationStore.shared.event($0); return $0 }
        RUM.enable(with: configuration)
        lifecycleObservers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            ObservationStore.shared.append("native_background", [:])
            Task { @MainActor in captureGeometry() }
        })
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            Task { @MainActor in captureGeometry() }
        }
    }
    static func hit(_ name: String) { ObservationStore.shared.append("native_input", ["name": name]) }
    static func appeared(_ screen: String) { ObservationStore.shared.append("native_appear", ["screen": screen]); captureGeometry() }
    static func captureGeometry() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let entries: [[String: Any]] = scenes.map { scene in
            ["id": scene.session.persistentIdentifier, "activation": scene.activationState.rawValue,
             "orientation": scene.interfaceOrientation.rawValue,
             "windows": scene.windows.filter { !$0.isHidden }.map { window in
                ["width": window.bounds.width, "height": window.bounds.height,
                 "horizontal_size_class": window.traitCollection.horizontalSizeClass.rawValue,
                 "vertical_size_class": window.traitCollection.verticalSizeClass.rawValue]
             }]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: entries, options: [.sortedKeys]),
              let key = String(data: data, encoding: .utf8), key != previousGeometry else { return }
        previousGeometry = key
        ObservationStore.shared.append("geometry", ["scenes": entries])
    }
}
