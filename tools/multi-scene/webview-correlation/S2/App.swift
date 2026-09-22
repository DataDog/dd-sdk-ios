/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */
import CryptoKit
import Foundation
import UIKit
import WebKit
import DatadogCore
import DatadogSessionReplay
import DatadogWebViewTracking
@_spi(Internal) import DatadogInternal
@testable import DatadogRUM

private enum WebSettings {
    static func argument(_ name: String) -> String {
        let values = ProcessInfo.processInfo.arguments
        guard let index = values.firstIndex(of: name), values.indices.contains(index + 1) else { return "" }
        return values[index + 1]
    }
    static let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    static let identity = ["run_id": argument("--run-id"), "nonce": argument("--nonce"), "arm": argument("--arm"),
        "source": Bundle.main.object(forInfoDictionaryKey: "WebSource") as? String ?? "",
        "fixture": Bundle.main.object(forInfoDictionaryKey: "WebFixture") as? String ?? ""]
    static let device = argument("--device")
    static let hostRun = argument("--host-run")
    static let startedTick = DispatchTime.now().uptimeNanoseconds
    static let budgetSeconds = Double(argument("--budget-seconds")) ?? 0
    static let deadline: UInt64 = budgetSeconds.isFinite && budgetSeconds > 0 && budgetSeconds <= 1_800
        ? startedTick + UInt64(budgetSeconds * 1_000_000_000) : 0
    static func phaseBudget(_ kind: String) throws -> UInt64 {
        let maximum: Double = kind == "human-fold" ? 300 : 180
        let argumentName = kind == "human-fold" ? "--fold-budget-seconds" : "--marker-budget-seconds"
        guard let value = Double(argument(argumentName)), value.isFinite, value > 0, value <= maximum
        else { throw WebFailure.invalid("phase-budget") }
        return UInt64(value * 1_000_000_000)
    }
    static let evidence = S2WebViewEvidence(identity: identity, output: directory.appendingPathComponent("evidence.json"))
    static let browserService = "ios-s2-webview-browser-validation"
    static func capture<T: Encodable>(_ event: T, kind: String) {
        do {
            let data = try JSONEncoder().encode(event)
            guard let text = String(data: data, encoding: .utf8) else { throw WebFailure.invalid("mapper-encoding") }
            evidence.record(kind, fields: ["event_json": text])
        } catch { evidence.record("encoding-failure") }
    }
}
private enum WebFailure: Error { case invalid(String) }

// Passive fixture observation of the SDK's value snapshot at TTID dispatch.
private struct WebTTIDFeature: DatadogFeature {
    static let name = "s2-webview-ttid-witness"
    let messageReceiver: FeatureMessageReceiver
}
private struct WebTTIDReceiver: FeatureMessageReceiver {
    let evidence: S2WebViewEvidence
    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard case .payload(let payload) = message, let message = payload as? TTIDMessage else { return false }
        var attributes: [String: Any] = [:]
        for (key, value) in message.attributes {
            if let value = value as? String { attributes[key] = ["type": "String", "value": value] }
            else if let value = value as? [String] { attributes[key] = ["type": "[String]", "value": value] }
            else { attributes[key] = ["type": "unsupported"] }
        }
        evidence.record("ttid-message", fields: ["payload_type": "TTIDMessage", "attributes": attributes,
            "vital_id": message.ttid.id, "vital_name": message.ttid.name,
            "duration_ns": message.ttid.duration as Any? ?? NSNull(),
            "raw_date_reference_seconds": message.ttid.date.timeIntervalSinceReferenceDate,
            "raw_date_unix_seconds": message.ttid.date.timeIntervalSince1970,
            "server_time_offset_seconds": message.ttid.serverTimeOffset])
        // Keep the message bus's original consumer/fallback behavior.
        return false
    }
}

@main @MainActor final class WebApp: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let info = Bundle.main
        WebSettings.evidence.record("runtime-admission", fields: ["started_ns": WebSettings.startedTick,
            "deadline_ns": WebSettings.deadline, "budget_seconds": WebSettings.budgetSeconds])
        Datadog.initialize(with: .init(clientToken: info.object(forInfoDictionaryKey: "WebClientToken") as? String ?? "",
            env: "s2-webview", service: "ios-s2-webview-native-validation", batchSize: .small, uploadFrequency: .frequent), trackingConsent: .granted)
        do {
            try CoreRegistry.default.register(feature: WebTTIDFeature(messageReceiver: WebTTIDReceiver(evidence: WebSettings.evidence)))
            WebSettings.evidence.record("ttid-observer-registered")
        } catch { WebSettings.evidence.record("ttid-observer-failure") }
        var rum = RUM.Configuration(applicationID: info.object(forInfoDictionaryKey: "WebApplicationID") as? String ?? "")
        rum.sessionSampleRate = 100; rum.telemetrySampleRate = 0
        rum.uiKitViewsPredicate = nil; rum.uiKitActionsPredicate = nil
        rum.trackFrustrations = false; rum.trackBackgroundEvents = false
        rum.vitalsUpdateFrequency = nil; rum.longTaskThreshold = nil; rum.appHangThreshold = nil
        rum.trackSlowFrames = false; rum.trackMemoryWarnings = false; rum.trackWatchdogTerminations = false
        rum.viewEventMapper = { WebSettings.capture($0, kind: "native-view"); return $0 }
        rum.actionEventMapper = { WebSettings.capture($0, kind: "native-action"); return $0 }
        rum.errorEventMapper = { WebSettings.capture($0, kind: "native-error"); return $0 }
        rum.resourceEventMapper = { WebSettings.capture($0, kind: "native-resource"); return $0 }
        WebSettings.evidence.record("rum-enable")
        RUM.enable(with: rum)
        SessionReplay.enable(with: .init(replaySampleRate: 100))
        WebSettings.evidence.record("launch", fields: ["pid": ProcessInfo.processInfo.processIdentifier])
        return true
    }
}

@MainActor final class WebScene: UIResponder, UIWindowSceneDelegate, UINavigationControllerDelegate, WKNavigationDelegate {
    var window: UIWindow?
    private var navigation: UINavigationController?
    private var retainedA: WKWebView?
    private weak var releasedA: WKWebView?
    private var webB: WKWebView?
    private var root: UIViewController?
    private var second: UIViewController?
    private var started = false
    private let evidence = WebSettings.evidence
    private var documents: [String: String] = [:]
    private var readyDocuments: Set<String> = []
    private var shownControllers: Set<String> = []
    private func key(_ object: AnyObject) -> String { String(describing: ObjectIdentifier(object)) }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let root = UIViewController(); root.title = "Native A"
        let nav = UINavigationController(rootViewController: root); nav.delegate = self
        self.root = root; navigation = nav
        let window = UIWindow(windowScene: scene); window.rootViewController = nav; self.window = window
        retainedA = makeWebView(label: "A", controller: root)
        evidence.record("scene-connected", fields: ["scene": session.persistentIdentifier, "window": key(window), "navigation": key(nav), "root": key(root)])
        window.makeKeyAndVisible()
    }
    func sceneDidBecomeActive(_ scene: UIScene) {
        evidence.record("scene-active", fields: ["scene": scene.session.persistentIdentifier])
        guard !started else { return }; started = true
        Task { @MainActor in
            do {
                try await run()
                try await wait("weak-release") { releasedA == nil }
                evidence.record("weak-release", fields: ["webview": "A", "is_nil": releasedA == nil])
                guard let second else { throw WebFailure.invalid("terminal-controller") }
                RUMMonitor.shared().stopView(viewController: second)
                try await wait("B-stopped") {
                    guard let row = evidence.matching("native-view").last,
                          let text = row["event_json"] as? String, let data = text.data(using: .utf8),
                          let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let view = event["view"] as? [String: Any] else { return false }
                    return view["name"] as? String == "NativeB" && view["is_active"] as? Bool == false
                }
                try await wait("TTID-witness") { evidence.matching("ttid-message").count == 1 }
                RUMMonitor.shared().stopSession()
                try await finish(state: "PASS")
            }
            catch { evidence.record("failure", fields: ["reason": String(describing: error)]); try? await finish(state: "INVALID") }
        }
    }
    func sceneWillResignActive(_ scene: UIScene) { evidence.record("scene-inactive", fields: ["scene": scene.session.persistentIdentifier]) }
    func sceneDidEnterBackground(_ scene: UIScene) { evidence.record("scene-background", fields: ["scene": scene.session.persistentIdentifier]) }
    func sceneDidDisconnect(_ scene: UIScene) { evidence.record("scene-disconnected", fields: ["scene": scene.session.persistentIdentifier]) }
    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        shownControllers.insert(key(viewController)); evidence.record("did-show", fields: ["controller": key(viewController), "animated": animated])
    }
    private func makeWebView(label: String, controller: UIViewController) -> WKWebView {
        let observer = S2WebViewContentController(evidence: evidence)
        let configuration = WKWebViewConfiguration(); configuration.userContentController = observer
        let webView = WKWebView(frame: controller.view.bounds, configuration: configuration)
        documents[label] = observer.documentID; webView.accessibilityIdentifier = label
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]; webView.navigationDelegate = self
        controller.view.addSubview(webView)
        WebViewTracking.enable(webView: webView, hosts: ["s2-webview.invalid"])
        webView.loadHTMLString("<html><body>Controlled native WebView \(label)</body></html>", baseURL: URL(string: "https://s2-webview.invalid"))
        return webView
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let label = webView.accessibilityIdentifier, let document = documents[label] else { return }
        readyDocuments.insert(label)
        evidence.record("web-document-ready", fields: ["webview": label, "document_id": document, "webview_identity": key(webView)])
    }
    private func wait(_ label: String, until deadline: UInt64? = nil, condition: () -> Bool) async throws {
        let bound = min(deadline ?? WebSettings.deadline, WebSettings.deadline)
        while !condition() {
            guard DispatchTime.now().uptimeNanoseconds < bound else { throw WebFailure.invalid("deadline-" + label) }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        guard DispatchTime.now().uptimeNanoseconds < bound else { throw WebFailure.invalid("deadline-" + label) }
    }
    private func owner(_ name: String, active: Bool = true) -> [String: Any]? {
        let events = evidence.matching("native-view").compactMap { row -> [String: Any]? in
            guard let text = row["event_json"] as? String, let data = text.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let view = event["view"] as? [String: Any], view["name"] as? String == name else { return nil }
            return ["event": event, "sequence": row["sequence"] as Any]
        }
        guard let latest = events.last, let event = latest["event"] as? [String: Any],
              (event["view"] as? [String: Any])?["is_active"] as? Bool == active,
              (event["session"] as? [String: Any])?["has_replay"] as? Bool == true else { return nil }
        return latest
    }
    private func start(_ name: String, controller: UIViewController) async throws -> [String: Any] {
        evidence.record("native-start", fields: ["name": name, "controller": key(controller)])
        RUMMonitor.shared().startView(viewController: controller, name: name, attributes: ["probe.run_id": WebSettings.identity["run_id"] ?? ""])
        try await wait(name + "-mapper") { owner(name) != nil }
        guard let mapped = owner(name), let event = mapped["event"] as? [String: Any],
              let view = event["view"] as? [String: Any], let session = event["session"] as? [String: Any] else { throw WebFailure.invalid("missing-owner") }
        evidence.record("native-ready", fields: ["name": name, "view_id": view["id"] as Any, "session_id": session["id"] as Any, "mapper_sequence": mapped["sequence"] as Any])
        return event
    }
    private func topology(_ phase: String, controller: UIViewController) throws {
        guard let window, let scene = window.windowScene, let navigation, let root,
              window.isKeyWindow, controller.view.window === window, navigation.topViewController === controller,
              scene.activationState == .foregroundActive else { throw WebFailure.invalid("owned-topology-" + phase) }
        let owned = Set([key(navigation), key(root), key(second ?? root)])
        func contains(_ controller: UIViewController?) -> Bool {
            guard let controller else { return false }
            return owned.contains(key(controller)) || controller.children.contains(where: { contains($0) }) || contains(controller.presentedViewController)
        }
        let captureStarted = DispatchTime.now().uptimeNanoseconds
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.map { value in
            ["id": value.session.persistentIdentifier, "activation": value.activationState.rawValue, "windows": value.windows.map { item in
                ["id": key(item), "owned": item === window, "key": item.isKeyWindow, "hidden": item.isHidden,
                 "alpha": item.alpha, "contains_fixture_controller": contains(item.rootViewController),
                 "defining_bundle": Bundle(for: type(of: item)).bundlePath,
                 "root_defining_bundle": item.rootViewController.map { Bundle(for: type(of: $0)).bundlePath } as Any? ?? NSNull(),
                 "root": item.rootViewController.map(key) as Any? ?? NSNull(), "width": item.bounds.width,
                 "height": item.bounds.height, "screen": key(item.screen)] as [String: Any]
            }] as [String: Any]
        }
        evidence.record("topology", fields: ["phase": phase, "scene": scene.session.persistentIdentifier,
            "window": key(window), "controller": key(controller), "controller_attached": true,
            "inventory": scenes, "connected_scene_count": UIApplication.shared.connectedScenes.count,
            "capture_started_ns": captureStarted, "capture_finished_ns": DispatchTime.now().uptimeNanoseconds,
            "window_framework_bundle": Bundle(for: UIWindow.self).bundlePath,
            "controller_framework_bundle": Bundle(for: UIViewController.self).bundlePath,
            "navigation": key(navigation), "root": key(root),
            "screen": ["id": key(scene.screen), "width": scene.screen.bounds.width,
                "height": scene.screen.bounds.height, "scale": scene.screen.scale]])
    }
    private func exchange(_ kind: String, fields: [String: Any], deadline: UInt64? = nil) async throws -> [String: Any] {
        let id = UUID().uuidString.lowercased(), issued = DispatchTime.now().uptimeNanoseconds
        let bound = min(deadline ?? WebSettings.deadline, WebSettings.deadline, issued + (try WebSettings.phaseBudget(kind)))
        guard issued < bound else { throw WebFailure.invalid("expired-request-" + kind) }
        let request: [String: Any] = ["id": id, "kind": kind, "identity": WebSettings.identity,
            "issued_ns": issued, "deadline_ns": bound, "fields": fields]
        let data = try JSONSerialization.data(withJSONObject: request, options: [.sortedKeys])
        let requestHash = SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined()
        evidence.record("host-request-issued", fields: ["request_id": id, "request_kind": kind,
            "request_sha256": requestHash, "issued_ns": issued, "deadline_ns": bound])
        try await evidence.flush()
        try data.write(to: WebSettings.directory.appendingPathComponent("request-\(id).json"), options: .atomic)
        let response = WebSettings.directory.appendingPathComponent("response-\(id).json")
        try await wait(kind, until: bound) { FileManager.default.fileExists(atPath: response.path) }
        let responseData = try Data(contentsOf: response)
        guard let value = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              value["id"] as? String == id, value["kind"] as? String == kind, value["identity"] as? [String: String] == WebSettings.identity,
              value["request_sha256"] as? String == requestHash,
              value["state"] as? String == "PASS" else { throw WebFailure.invalid("invalid-response-" + kind) }
        let consumed = DispatchTime.now().uptimeNanoseconds
        guard consumed < bound else { throw WebFailure.invalid("late-response-" + kind) }
        evidence.record("host-response-consumed", fields: ["request_id": id, "request_kind": kind,
            "request_sha256": requestHash, "response_sha256": SHA256.hash(data: responseData).map({ String(format: "%02x", $0) }).joined(),
            "issued_ns": issued, "deadline_ns": bound, "consumed_ns": consumed])
        return value
    }
    private func emit(_ marker: String, body: String, webView: WKWebView, ownerName: String) async throws {
        guard let mapped = owner(ownerName), let event = mapped["event"] as? [String: Any],
              let native = event["view"] as? [String: Any], let data = body.data(using: .utf8),
              let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let browser = envelope["event"] as? [String: Any], let view = browser["view"] as? [String: Any] else { throw WebFailure.invalid("emit-owner") }
        evidence.record("emit-before", fields: ["marker": marker, "view_id": view["id"] as Any, "live_view_id": native["id"] as Any])
        let quoted = try JSONSerialization.data(withJSONObject: [body], options: [])
        guard let literal = String(data: quoted, encoding: .utf8) else { throw WebFailure.invalid("js-encoding") }
        _ = try await webView.evaluateJavaScript("window.DatadogEventBridge.send(\(literal)[0]); true")
        try await wait(marker + "-callback") { evidence.matching("webkit-callback", field: "marker", value: marker).count == 1 }
    }
    private func acknowledge(_ markers: [String], deadline: UInt64? = nil) async throws {
        let callbacks = markers.compactMap { evidence.matching("webkit-callback", field: "marker", value: $0).first }
        let reply = try await exchange("backend-markers", fields: ["callbacks": callbacks], deadline: deadline)
        guard let acknowledgements = reply["acknowledgements"] as? [[String: Any]], acknowledgements.count == markers.count else { throw WebFailure.invalid("missing-acks") }
        for (marker, ack) in zip(markers, acknowledgements) {
            guard ack["marker"] as? String == marker, let raw = ack["event_json"] as? String,
                  let data = raw.data(using: .utf8), ack["event_sha256"] as? String == SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined(),
                  ack["evidence_kind"] as? String == "datadog-mcp" else { throw WebFailure.invalid("invalid-ack") }
            evidence.record("writer-ack", fields: ack)
        }
    }
    private func fold(_ phase: String, controller: UIViewController) async throws {
        try topology("before-" + phase, controller: controller)
        let proof = try await exchange("human-fold", fields: ["phase": phase])
        guard proof["phase"] as? String == phase,
              let raw = proof["proof_json"] as? String, let data = raw.data(using: .utf8),
              let receipt = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hash = proof["proof_sha256"] as? String,
              hash == SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined(),
              receipt["kind"] as? String == "actual-display",
              receipt["state"] as? String == "PASS", receipt["phase"] as? String == phase,
              receipt["device"] as? String == WebSettings.device, !WebSettings.device.isEmpty,
              receipt["host_run"] as? String == WebSettings.hostRun, !WebSettings.hostRun.isEmpty,
              receipt["identity"] as? [String: String] == WebSettings.identity,
              receipt["request_sha256"] as? String == proof["request_sha256"] as? String
        else { throw WebFailure.invalid("fold-proof") }
        try topology("after-" + phase, controller: controller)
        evidence.record("fold-complete", fields: ["phase": phase, "proof_sha256": hash, "proof_json": raw])
    }
    private func run() async throws {
        guard WebSettings.deadline > DispatchTime.now().uptimeNanoseconds, let root, let nav = navigation else { throw WebFailure.invalid("admission") }
        try await wait("A-ready") { readyDocuments.contains("A") && shownControllers.contains(key(root)) }
        // Replay eligibility is a context prerequisite; captured content is outside acceptance.
        var replay = false
        while !replay {
            replay = await withCheckedContinuation { continuation in
                CoreRegistry.default.scope(for: RUMFeature.self).context { continuation.resume(returning: $0.hasReplay == true) }
            }
            guard DispatchTime.now().uptimeNanoseconds < WebSettings.deadline else { throw WebFailure.invalid("replay-context") }
            if !replay { try await Task.sleep(nanoseconds: 50_000_000) }
        }
        _ = try await start("NativeA", controller: root); try topology("A-ready", controller: root)
        let activeDate = Date(), activeTick = DispatchTime.now().uptimeNanoseconds
        try await wait("active-lifetime") { Date().timeIntervalSince(activeDate) > 181 && DispatchTime.now().uptimeNanoseconds - activeTick > 181_000_000_000 }
        guard let a = retainedA, let documentA = documents["A"] else { throw WebFailure.invalid("A-missing") }
        let first = try evidence.freeze(marker: "M1", service: WebSettings.browserService, documentID: documentA)
        try await emit("M1", body: first, webView: a, ownerName: "NativeA"); try await acknowledge(["M1"])
        let third = try evidence.freeze(marker: "M3", service: WebSettings.browserService, documentID: documentA)
        let fourth = try evidence.freeze(marker: "M4", service: WebSettings.browserService, documentID: documentA)
        try await fold("open", controller: root)
        let bController = UIViewController(); bController.title = "Native B"; second = bController
        webB = makeWebView(label: "B", controller: bController)
        evidence.record("navigation-start", fields: ["controller": key(bController)])
        nav.pushViewController(bController, animated: true)
        try await wait("B-shown") { shownControllers.contains(key(bController)) && readyDocuments.contains("B") }
        let deactivationEarliest = DispatchTime.now().uptimeNanoseconds
        _ = try await start("NativeB", controller: bController)
        try await wait("A-inactive") { owner("NativeA", active: false) != nil }
        guard let inactive = owner("NativeA", active: false), let event = inactive["event"] as? [String: Any],
              let view = event["view"] as? [String: Any] else { throw WebFailure.invalid("A-inactive") }
        evidence.record("native-inactive", fields: ["name": "NativeA", "view_id": view["id"] as Any,
            "mapper_sequence": inactive["sequence"] as Any])
        let deactivationLatest = Date(), deactivationTick = DispatchTime.now().uptimeNanoseconds
        try topology("B-ready", controller: bController)
        guard let b = webB, let documentB = documents["B"] else { throw WebFailure.invalid("B-missing") }
        let secondEnvelope = try evidence.freeze(marker: "M2", service: WebSettings.browserService, documentID: documentB)
        try await emit("M2", body: secondEnvelope, webView: b, ownerName: "NativeB")
        a.removeFromSuperview(); evidence.record("detached", fields: ["webview": "A", "window": a.window.map(key) as Any? ?? NSNull()])
        try await emit("M3", body: third, webView: a, ownerName: "NativeB")
        try await acknowledge(["M2", "M3"], deadline: deactivationEarliest + 180_000_000_000)
        try await fold("closed", controller: bController)
        try await wait("inactive-lifetime") { Date().timeIntervalSince(deactivationLatest) > 181 && DispatchTime.now().uptimeNanoseconds - deactivationTick > 181_000_000_000 }
        try await emit("M4", body: fourth, webView: a, ownerName: "NativeB"); try await acknowledge(["M4"])
        releasedA = a
        WebViewTracking.disable(webView: a); a.navigationDelegate = nil
        evidence.record("tracking-disabled", fields: ["webview": "A"])
        retainedA = nil
        // Returning releases the local A reference; the caller checks the weak witness.
    }
    private func finish(state: String) async throws {
        let cutoff = try evidence.close(state: state)
        try await evidence.flush()
        let snapshot = try Data(contentsOf: WebSettings.directory.appendingPathComponent("evidence.json"))
        let data = try JSONSerialization.data(withJSONObject: ["state": state, "identity": WebSettings.identity,
            "closed_sequence": cutoff,
            "evidence_sha256": SHA256.hash(data: snapshot).map({ String(format: "%02x", $0) }).joined()], options: [.sortedKeys])
        try data.write(to: WebSettings.directory.appendingPathComponent("terminal.json"), options: .atomic)
    }
}
