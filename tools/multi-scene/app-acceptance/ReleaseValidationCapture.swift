// Copyright © Datadog, Inc. All rights reserved.

#if os(iOS)
import CryptoKit
import DatadogCore
import DatadogInternal
import DatadogRUM
import Foundation
import UIKit
import WebKit

// Compiled only into separately identified validation app copies.
public enum ReleaseValidationCapture {
    private static let identity: [String: String]? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--rum-release-validation") else { return nil }
        func value(_ key: String) -> String? {
            guard arguments.filter({ $0 == key }).count == 1,
                  let index = arguments.firstIndex(of: key), arguments.indices.contains(index + 1) else { return nil }
            let value = arguments[index + 1]
            return UUID(uuidString: value)?.uuidString.lowercased() == value ? value : nil
        }
        guard let run = value("--capture-run-id"), let nonce = value("--capture-nonce") else { return nil }
        return ["run_id": run, "nonce": nonce]
    }()
    private static let store = identity.map(CaptureStore.init)

    static func configure(_ configuration: inout RUM.Configuration) {
        guard let store else { return }
        let view = configuration.viewEventMapper
        let action = configuration.actionEventMapper
        let resource = configuration.resourceEventMapper
        let error = configuration.errorEventMapper
        let longTask = configuration.longTaskEventMapper
        configuration.viewEventMapper = { event in
            let result = view.map { $0(event) } ?? event
            store.mapper(result, family: "view", accepted: true)
            return result
        }
        configuration.actionEventMapper = { event in
            let result = action.map { $0(event) } ?? Optional(event)
            store.mapper(result ?? event, family: "action", accepted: result != nil)
            return result
        }
        configuration.resourceEventMapper = { event in
            let result = resource.map { $0(event) } ?? Optional(event)
            store.mapper(result ?? event, family: "resource", accepted: result != nil)
            return result
        }
        configuration.errorEventMapper = { event in
            let result = error.map { $0(event) } ?? Optional(event)
            store.mapper(result ?? event, family: "error", accepted: result != nil)
            return result
        }
        configuration.longTaskEventMapper = { event in
            let result = longTask.map { $0(event) } ?? Optional(event)
            store.mapper(result ?? event, family: "long_task", accepted: result != nil)
            return result
        }
        do {
            try CoreRegistry.default.register(feature: CaptureFeature(messageReceiver: CaptureReceiver(store: store)))
            store.record("configured", fields: ["pid": ProcessInfo.processInfo.processIdentifier,
                "bundle_id": Bundle.main.bundleIdentifier ?? "nil",
                "sdk_version": __dogfoodedSDKVersion,
                "build_sdk": Bundle.main.object(forInfoDictionaryKey: "DTSDKName") as Any? ?? NSNull()])
        } catch { store.record("capture_failure", fields: ["reason": "passive receiver registration failed"]) }
        DispatchQueue.main.async { CaptureNative.shared.start(store: store) }
    }

    @MainActor public static func window(_ window: UIWindow) {
        guard let store else { return }
        CaptureNative.shared.bind(window: window)
        store.record("owned_window", fields: ["window": CaptureNative.key(window),
            "scene": window.windowScene?.session.persistentIdentifier ?? "nil"])
    }

    @MainActor public static func scene(_ callback: String, scene: UIScene) {
        guard let store else { return }
        let sequence = store.record("scene_callback", fields: ["callback": callback,
            "scene": scene.session.persistentIdentifier, "activation": scene.activationState.rawValue,
            "app_state": UIApplication.shared.applicationState.rawValue])
        if callback == "didEnterBackground-exit" {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.2) {
                store.checkpoint("background-" + String(sequence))
            }
        }
    }

    @MainActor public static func navigation(_ callback: String, navigation: UINavigationController,
                                            controller: UIViewController, animated: Bool) {
        guard let store else { return }
        let started = DispatchTime.now().uptimeNanoseconds
        store.record("navigation_callback", fields: ["callback": callback,
            "navigation": CaptureNative.key(navigation), "controller": CaptureNative.controller(controller),
            "stack": navigation.viewControllers.map(CaptureNative.key), "animated": animated,
            "transition": CaptureNative.transition(navigation.transitionCoordinator)], started: started)
    }

    @MainActor public static func controller(_ callback: String, controller: UIViewController) {
        guard let store else { return }
        let started = DispatchTime.now().uptimeNanoseconds
        store.record("controller_callback", fields: ["callback": callback,
            "controller": CaptureNative.controller(controller)], started: started)
    }

    public static func swiftUI(_ callback: String, name: String) {
        store?.record("swiftui_callback", fields: ["callback": callback, "name": name, "is_main_thread": Thread.isMainThread])
    }

    @MainActor static func predicate(_ controller: UIViewController, name: String?) {
        guard let store else { return }
        let started = DispatchTime.now().uptimeNanoseconds
        store.record("predicate_result", fields: ["controller": CaptureNative.controller(controller),
            "name": name as Any? ?? NSNull(), "accepted": name != nil], started: started)
    }

    @MainActor public static func webView(_ webView: WKWebView, controller: UIViewController) {
        guard let store else { return }
        CaptureNative.shared.bind(webView: webView, controller: controller)
        store.record("owned_webview", fields: ["webview": CaptureNative.key(webView),
            "controller": CaptureNative.key(controller)])
    }

    public static func manual(_ operation: String, name: String) {
        store?.record("manual_call", fields: ["operation": operation, "name": name])
    }
}

// Sequence reservation and enqueue share the lock. Writer state belongs to its serial queue.
private final class CaptureStore: @unchecked Sendable {
    private let identity: [String: String]
    private let directory: URL
    private let lock = NSLock()
    private let writer = DispatchQueue(label: "validation.capture.writer", qos: .utility)
    private var sequence = 0
    private var lastViewSequence: Int?
    private var lastContextSequence: Int?
    private var requestID: String?
    private var phase: String?
    private var writeFailed = false
    private var byteCount = 0
    private var hasher = SHA256()

    init(identity: [String: String]) {
        self.identity = identity
        directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("rum-release-capture-" + (identity["run_id"] ?? "invalid"))
        writer.async { [self] in
            do {
                guard !FileManager.default.fileExists(atPath: directory.path) else { writeFailed = true; return }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                       attributes: [.posixPermissions: 0o700])
                let stream = directory.appendingPathComponent("events.jsonl")
                try Data().write(to: stream, options: .withoutOverwriting)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stream.path)
            } catch { writeFailed = true }
        }
    }

    @discardableResult
    func record(_ kind: String, fields: [String: Any] = [:], started: UInt64? = nil) -> Int {
        let began = started ?? DispatchTime.now().uptimeNanoseconds
        lock.lock(); defer { lock.unlock() }
        let committed = enqueue(kind, fields: fields, started: began)
        let finished = DispatchTime.now().uptimeNanoseconds
        enqueue("observer_cost", fields: ["event_sequence": committed, "operation": kind,
            "duration_ns": finished - began], started: finished)
        return committed
    }

    // Called only under lock, including the cost receipt after each observation enqueue.
    @discardableResult
    private func enqueue(_ kind: String, fields: [String: Any], started: UInt64) -> Int {
        let began = started
        sequence += 1
        let committed = sequence
        let now = DispatchTime.now().uptimeNanoseconds
        let row: [String: Any] = ["schema_version": 1, "identity": identity, "sequence": committed,
            "kind": kind, "wall_ms": Int64(Date().timeIntervalSince1970 * 1_000), "monotonic_ns": now,
            "capture_started_ns": began, "reservation_latency_ns": now - began,
            "request_id": requestID as Any? ?? NSNull(), "phase": phase as Any? ?? NSNull(),
            "last_view_sequence": lastViewSequence as Any? ?? NSNull(),
            "last_context_sequence": lastContextSequence as Any? ?? NSNull(), "fields": fields]
        if kind == "mapper", fields["family"] as? String == "view" { lastViewSequence = committed }
        if kind == "context" { lastContextSequence = committed }
        writer.async { [self] in
            guard !writeFailed, committed <= 100_000 else { writeFailed = true; return }
            do {
                var bytes = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
                bytes.append(10)
                guard byteCount + bytes.count <= 67_108_864 else { writeFailed = true; return }
                let handle = try FileHandle(forWritingTo: directory.appendingPathComponent("events.jsonl"))
                defer { try? handle.close() }
                try handle.seekToEnd(); try handle.write(contentsOf: bytes)
                hasher.update(data: bytes); byteCount += bytes.count
            } catch { writeFailed = true }
        }
        return committed
    }

    func mapper<Event: Encodable>(_ event: Event, family: String, accepted: Bool) {
        let started = DispatchTime.now().uptimeNanoseconds
        do {
            let bytes = try JSONEncoder().encode(event)
            guard let json = String(data: bytes, encoding: .utf8) else { throw CaptureFailure.encoding }
            record("mapper", fields: ["family": family, "accepted": accepted, "event_json": json], started: started)
        } catch { record("capture_failure", fields: ["reason": "mapper encoding failed", "family": family], started: started) }
    }

    func browser(_ event: [String: Any]) {
        let started = DispatchTime.now().uptimeNanoseconds
        do {
            let bytes = try JSONSerialization.data(withJSONObject: event, options: [.sortedKeys])
            guard let json = String(data: bytes, encoding: .utf8) else { throw CaptureFailure.encoding }
            record("browser_message", fields: ["event_json": json, "scope": "raw_browser_source_payload"], started: started)
        } catch { record("capture_failure", fields: ["reason": "browser encoding failed"], started: started) }
    }

    func begin(request: String, phase: String) {
        lock.lock(); defer { lock.unlock() }
        requestID = request; self.phase = phase
    }

    func checkpoint(_ request: String) {
        lock.lock(); defer { lock.unlock() }
        let committed = sequence
        writer.async { [self] in
            do {
                let receipt: [String: Any] = ["schema_version": 1, "identity": identity, "request_id": request,
                    "sequence": committed, "success": !writeFailed, "byte_count": byteCount,
                    "sha256": hasher.finalize().map { String(format: "%02x", $0) }.joined()]
                let destination = directory.appendingPathComponent("checkpoint-" + request + ".json")
                let temporary = directory.appendingPathComponent(".checkpoint-" + UUID().uuidString.lowercased())
                try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys])
                    .write(to: temporary, options: .withoutOverwriting)
                defer { try? FileManager.default.removeItem(at: temporary) }
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
                try FileManager.default.linkItem(at: temporary, to: destination)
            } catch { writeFailed = true }
        }
    }

    enum CaptureFailure: Error { case encoding }
}

private struct CaptureFeature: DatadogFeature {
    static let name = "release-validation-passive-capture"
    let messageReceiver: FeatureMessageReceiver
}

private struct CaptureReceiver: FeatureMessageReceiver {
    let store: CaptureStore
    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        switch message {
        case let .webview(.rum(event)):
            store.browser(event)
        case let .context(context):
            let started = DispatchTime.now().uptimeNanoseconds
            let rum = context.additionalContext(ofType: RUMCoreContext.self)
            store.record("context", fields: ["application_id": rum?.applicationID as Any? ?? NSNull(),
                "session_id": rum?.sessionID as Any? ?? NSNull(), "view_id": rum?.viewID as Any? ?? NSNull(),
                "view_name": rum?.viewName as Any? ?? NSNull(), "view_path": rum?.viewPath as Any? ?? NSNull(),
                "view_server_offset": rum?.viewServerTimeOffset as Any? ?? NSNull(),
                "server_offset": context.serverTimeOffset, "has_replay": context.additionalContext(ofType: SessionReplayCoreContext.HasReplay.self)?.value as Any? ?? NSNull()], started: started)
        default: break
        }
        // MessageBus visits every feature; false preserves its original fallback result.
        return false
    }
}

@MainActor private final class CaptureNative {
    static let shared = CaptureNative()
    private let windows = NSHashTable<UIWindow>.weakObjects()
    private var webViews: [WebViewBinding] = []
    private var requests: CaptureRequests?
    static func key(_ object: AnyObject?) -> String { object.map { String(describing: ObjectIdentifier($0)) } ?? "nil" }
    static func rectangle(_ value: CGRect) -> [CGFloat] { [value.origin.x, value.origin.y, value.width, value.height] }
    func bind(window: UIWindow) { windows.add(window) }
    func bind(webView: WKWebView, controller: UIViewController) {
        webViews.removeAll { $0.webView == nil || $0.controller == nil }
        guard !webViews.contains(where: { $0.webView === webView }) else { return }
        webViews.append(WebViewBinding(webView: webView, controller: controller))
    }
    static func transition(_ coordinator: UIViewControllerTransitionCoordinator?) -> [String: Any] {
        guard let coordinator else { return [:] }
        return ["id": key(coordinator as AnyObject), "initially_interactive": coordinator.initiallyInteractive,
            "interactive": coordinator.isInteractive, "cancelled": coordinator.isCancelled,
            "from": key(coordinator.viewController(forKey: .from)), "to": key(coordinator.viewController(forKey: .to))]
    }
    static func controller(_ controller: UIViewController) -> [String: Any] {
        ["id": key(controller), "class": String(reflecting: type(of: controller)),
         "bundle": Bundle(for: type(of: controller)).bundleURL.path,
         "label": controller.accessibilityLabel as Any? ?? NSNull(), "parent": key(controller.parent),
         "window": key(controller.viewIfLoaded?.window), "scene": controller.viewIfLoaded?.window?.windowScene?.session.persistentIdentifier as Any? ?? NSNull(),
         "children": controller.children.map(key), "presented": key(controller.presentedViewController),
         "presenting": key(controller.presentingViewController), "transition": transition(controller.transitionCoordinator)]
    }
    func snapshot() -> [String: Any] {
        var controllers: [[String: Any]] = []
        var seen = Set<ObjectIdentifier>()
        var pending = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }.compactMap { $0.rootViewController }
        while let controller = pending.popLast() {
            guard seen.insert(ObjectIdentifier(controller)).inserted else { continue }
            guard seen.count <= 512 else { return ["capture_error": "controller inventory exceeds bound"] }
            controllers.append(Self.controller(controller)); pending.append(contentsOf: controller.children)
            if let presented = controller.presentedViewController { pending.append(presented) }
        }
        let inventory: [[String: Any]] = UIApplication.shared.connectedScenes.compactMap { value in
            guard let scene = value as? UIWindowScene else { return nil }
            return ["id": scene.session.persistentIdentifier, "activation": scene.activationState.rawValue,
                "screen": Self.key(scene.screen), "screen_bounds": Self.rectangle(scene.screen.bounds),
                "screen_scale": scene.screen.scale, "coordinate_bounds": Self.rectangle(scene.coordinateSpace.bounds),
                "windows": scene.windows.map { window -> [String: Any] in
                    ["id": Self.key(window), "owned": windows.contains(window), "key": window.isKeyWindow,
                     "hidden": window.isHidden, "alpha": window.alpha, "level": window.windowLevel.rawValue,
                     "bounds": Self.rectangle(window.bounds), "root": Self.key(window.rootViewController),
                     "root_attached": window.rootViewController?.viewIfLoaded?.window === window,
                     "window_bundle": Bundle(for: type(of: window)).bundleURL.path,
                     "root_bundle": window.rootViewController.map { Bundle(for: type(of: $0)).bundleURL.path } ?? "nil"]
                }]
        }
        let web: [[String: Any]] = webViews.map { binding in
            ["id": Self.key(binding.webView), "controller": Self.key(binding.controller),
             "window": Self.key(binding.webView?.window), "loading": binding.webView?.isLoading as Any? ?? NSNull(),
             "host": binding.webView?.url?.host as Any? ?? NSNull(), "path": binding.webView?.url?.path as Any? ?? NSNull(),
             "bounds": binding.webView.map { Self.rectangle($0.bounds) } ?? []]
        }
        return ["pid": ProcessInfo.processInfo.processIdentifier, "app_state": UIApplication.shared.applicationState.rawValue,
            "scene_inventory": inventory, "controllers": controllers, "webviews": web,
            "owned_windows": windows.allObjects.map(Self.key),
            "uikit_window_bundle": Bundle(for: UIWindow.self).bundleURL.path,
            "uikit_controller_bundle": Bundle(for: UIViewController.self).bundleURL.path]
    }
    func start(store: CaptureStore) {
        guard requests == nil else { store.record("capture_failure", fields: ["reason": "capture started twice"]); return }
        requests = CaptureRequests { request, phase, fingerprint in
            Task { @MainActor in
                guard let request, let phase else {
                    store.record("capture_failure", fields: ["reason": "invalid or consumed capture request", "request_sha256": fingerprint]); return
                }
                store.begin(request: request, phase: phase)
                let started = DispatchTime.now().uptimeNanoseconds
                store.record("snapshot", fields: ["request_sha256": fingerprint, "topology": self.snapshot()], started: started)
                store.checkpoint(request)
            }
        }
    }
    private final class WebViewBinding {
        weak var webView: WKWebView?
        weak var controller: UIViewController?
        init(webView: WKWebView, controller: UIViewController) { self.webView = webView; self.controller = controller }
    }
}

private final class CaptureRequests: @unchecked Sendable {
    private let queue = DispatchQueue(label: "validation.capture.requests", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var previousBytes: String?
    private var consumed = Set<String>()
    init(receive: @escaping @Sendable (String?, String?, String) -> Void) {
        let arguments = ProcessInfo.processInfo.arguments
        func argument(_ key: String) -> String {
            guard let index = arguments.firstIndex(of: key), arguments.indices.contains(index + 1) else { return "" }
            return arguments[index + 1]
        }
        let run = argument("--capture-run-id"), nonce = argument("--capture-nonce")
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("release-capture-request.json")
        queue.async { [self] in
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(250))
            timer.setEventHandler { [weak self] in
                guard let self, let bytes = try? Data(contentsOf: path) else { return }
                let fingerprint = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
                guard previousBytes != fingerprint else { return }; previousBytes = fingerprint
                guard bytes.count <= 16_384,
                      let value = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                      Set(value.keys) == Set(["schema_version", "run_id", "nonce", "request_id", "phase"]),
                      let version = value["schema_version"] as? NSNumber,
                      CFGetTypeID(version) != CFBooleanGetTypeID(), version.intValue == 1, version.doubleValue == 1,
                      value["run_id"] as? String == run, value["nonce"] as? String == nonce,
                      let request = value["request_id"] as? String, UUID(uuidString: request)?.uuidString.lowercased() == request,
                      let phase = value["phase"] as? String, !phase.isEmpty, phase.count <= 128,
                      consumed.insert(request).inserted else { receive(nil, nil, fingerprint); return }
                receive(request, phase, fingerprint)
            }
            self.timer = timer; timer.resume()
        }
    }
}
#endif
