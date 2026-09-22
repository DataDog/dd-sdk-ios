/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */
import Foundation
import SwiftUI
import UIKit
import DatadogCore
import DatadogInternal
import DatadogRUM

// Reuses the tested scalar, ordered, off-callback evidence writer.
enum HostingSettings {
    static func argument(_ key: String) -> String {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: key), args.indices.contains(index + 1) else { return "" }
        return args[index + 1]
    }
    static let mode = argument("--mode")
    static let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    static let identity = ["run_id": argument("--run-id"), "nonce": argument("--nonce"),
        "arm": argument("--arm"), "mode": mode,
        "source": Bundle.main.object(forInfoDictionaryKey: "HostingSource") as? String ?? "",
        "fixture": Bundle.main.object(forInfoDictionaryKey: "HostingFixture") as? String ?? ""]
    static let evidence = S2WebViewEvidence(identity: identity, output: output.appendingPathComponent("evidence.json"))
    static func mapper<T: Encodable>(_ event: T) {
        do {
            let data = try JSONEncoder().encode(event)
            guard let body = String(data: data, encoding: .utf8) else { throw HostingFailure.encoding }
            evidence.record("mapper", fields: ["event_json": body])
        } catch { evidence.record("encoding-failure") }
    }
}
enum HostingFailure: Error { case encoding, boundary(String) }

struct RootView: View {
    var body: some View { ContentSurface(name: "RootView") }
}
struct DetailView: View {
    var body: some View { ContentSurface(name: "DetailView") }
}
struct ModalView: View {
    var body: some View { ContentSurface(name: "ModalView") }
}
struct ContentSurface: View {
    let name: String
    var body: some View {
        Group {
            if HostingSettings.mode == "manual" {
                Text(name).trackRUMView(name: name)
            } else { Text(name) }
        }
        .onAppear { HostingSettings.evidence.record("swiftui-appear", fields: ["name": name]) }
        .onDisappear { HostingSettings.evidence.record("swiftui-disappear", fields: ["name": name]) }
    }
}

// Passive fixture observation of the SDK's value snapshot at TTID dispatch.
private struct HostingTTIDFeature: DatadogFeature {
    static let name = "s2-hosting-ttid-witness"
    let messageReceiver: FeatureMessageReceiver
}
private struct HostingTTIDReceiver: FeatureMessageReceiver {
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

@main @MainActor final class HostingApp: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let info = Bundle.main
        Datadog.initialize(with: .init(clientToken: info.object(forInfoDictionaryKey: "HostingClientToken") as? String ?? "",
            env: "s2-hosting", service: "ios-s2-hosting-validation"), trackingConsent: .granted)
        do {
            try CoreRegistry.default.register(feature: HostingTTIDFeature(messageReceiver: HostingTTIDReceiver(evidence: HostingSettings.evidence)))
            HostingSettings.evidence.record("ttid-observer-registered")
        } catch { HostingSettings.evidence.record("ttid-observer-failure") }
        var rum = RUM.Configuration(applicationID: info.object(forInfoDictionaryKey: "HostingApplicationID") as? String ?? "")
        rum.sessionSampleRate = 100
        rum.telemetrySampleRate = 0
        rum.trackFrustrations = false
        rum.trackBackgroundEvents = false
        rum.longTaskThreshold = nil
        rum.appHangThreshold = nil
        rum.vitalsUpdateFrequency = nil
        rum.trackMemoryWarnings = false
        rum.trackSlowFrames = false
        rum.trackWatchdogTerminations = false
        if HostingSettings.mode == "automatic" { rum.swiftUIViewsPredicate = DefaultSwiftUIRUMViewsPredicate() }
        rum.viewEventMapper = { HostingSettings.mapper($0); return $0 }
        rum.actionEventMapper = { HostingSettings.mapper($0); return $0 }
        rum.errorEventMapper = { HostingSettings.mapper($0); return $0 }
        rum.resourceEventMapper = { HostingSettings.mapper($0); return $0 }
        rum.longTaskEventMapper = { HostingSettings.mapper($0); return $0 }
        HostingSettings.evidence.record("rum-enable")
        RUM.enable(with: rum)
        HostingSettings.evidence.record("launch", fields: ["pid": ProcessInfo.processInfo.processIdentifier,
            "mode": HostingSettings.mode, "automatic_uikit": false,
            "automatic_swiftui": HostingSettings.mode == "automatic",
            "build_sdk": info.object(forInfoDictionaryKey: "DTSDKName") as Any? ?? NSNull(),
            "deployment": info.object(forInfoDictionaryKey: "MinimumOSVersion") as Any? ?? NSNull()])
        return true
    }
}

@MainActor final class HostingScene: UIResponder, UIWindowSceneDelegate, UINavigationControllerDelegate {
    var window: UIWindow?
    private var root: UIViewController?
    private var navigation: UINavigationController?
    private var started = false
    private var phase = "root"
    private let evidence = HostingSettings.evidence
    private var fixtureControllers: Set<String> = []

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let root = UIHostingController(rootView: RootView())
        let nav = UINavigationController(rootViewController: root)
        self.root = root; self.navigation = nav; nav.delegate = self
        fixtureControllers = [key(root), key(nav)]
        let window = UIWindow(windowScene: scene)
        window.rootViewController = nav
        self.window = window
        evidence.record("scene-connected", fields: ["scene": session.persistentIdentifier,
            "window": key(window), "root_controller": key(root), "navigation": key(nav)])
        window.makeKeyAndVisible()
    }
    func sceneDidBecomeActive(_ scene: UIScene) {
        evidence.record("scene-active", fields: ["scene": scene.session.persistentIdentifier])
        guard !started else { return }; started = true
        Task { @MainActor in
            do { try await run(); try await finish("PASS", nil) }
            catch { try? await finish("INVALID", String(describing: error)) }
        }
    }
    func sceneWillResignActive(_ scene: UIScene) { evidence.record("scene-inactive", fields: ["scene": scene.session.persistentIdentifier]) }
    func sceneDidDisconnect(_ scene: UIScene) { evidence.record("scene-disconnected", fields: ["scene": scene.session.persistentIdentifier]) }
    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        evidence.record("did-show", fields: ["phase": phase, "controller": key(viewController),
            "top": navigationController.topViewController.map(key) as Any? ?? NSNull(), "animated": animated])
    }
    private func key(_ object: AnyObject) -> String { String(describing: ObjectIdentifier(object)) }
    private func containsFixture(_ controller: UIViewController?) -> Bool {
        guard let controller else { return false }
        return fixtureControllers.contains(key(controller)) || controller.children.contains { containsFixture($0) }
            || containsFixture(controller.presentedViewController)
    }
    private func wait(_ name: String, _ predicate: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 20
        while !predicate() {
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw HostingFailure.boundary(name) }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
    private func views() -> [[String: Any]] {
        evidence.matching("mapper").compactMap { row in
            guard let raw = row["event_json"] as? String, let data = raw.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  event["type"] as? String == "view" else { return nil }
            return event
        }
    }
    private func distinctViewIDs() -> Set<String> {
        Set(views().compactMap { ($0["view"] as? [String: Any])?["name"] as? String == "ApplicationLaunch" ? nil : ($0["view"] as? [String: Any])?["id"] as? String })
    }
    private func snapshot(_ name: String, controller: UIViewController, occurrence: Int) async throws {
        try await wait("mapper-" + name) { distinctViewIDs().count >= occurrence && navigation?.transitionCoordinator == nil && controller.transitionCoordinator == nil }
        guard let window, let scene = window.windowScene, let nav = navigation else { throw HostingFailure.boundary("missing-owned-window") }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let rows: [[String: Any]] = scenes.map { s in
            ["id": s.session.persistentIdentifier, "activation": s.activationState.rawValue,
             "windows": s.windows.map { w -> [String: Any] in
                ["id": key(w), "owned": w === window, "key": w.isKeyWindow, "hidden": w.isHidden,
                 "alpha": w.alpha, "level": w.windowLevel.rawValue,
                 "root": w.rootViewController.map(key) as Any? ?? NSNull(),
                 "class": String(describing: type(of: w)), "width": w.bounds.width, "height": w.bounds.height,
                 "screen": key(w.screen), "root_is_navigation": w.rootViewController === nav, "contains_fixture_controller": containsFixture(w.rootViewController)]
             }]
        }
        let latest = views().last
        evidence.record("boundary", fields: ["phase": name, "occurrence": occurrence,
            "controller": key(controller), "controller_attached": controller.viewIfLoaded?.window === window,
            "top": nav.topViewController.map(key) as Any? ?? NSNull(),
            "presented": nav.presentedViewController.map(key) as Any? ?? NSNull(),
            "transition_finished": nav.transitionCoordinator == nil && controller.transitionCoordinator == nil,
            "scene": scene.session.persistentIdentifier, "window": key(window), "inventory": rows,
            "screen": ["id": key(scene.screen), "width": scene.screen.bounds.width,
                       "height": scene.screen.bounds.height, "scale": scene.screen.scale],
            "latest_view": (latest?["view"] as? [String: Any]) as Any? ?? NSNull(),
            "session": (latest?["session"] as? [String: Any])?["id"] as Any? ?? NSNull()])
    }
    private func run() async throws {
        guard let root, let nav = navigation else { throw HostingFailure.boundary("missing-navigation") }
        try await wait("root-did-show") { !evidence.matching("did-show", field: "phase", value: "root").isEmpty }
        try await snapshot("root", controller: root, occurrence: 1)
        phase = "push"
        let detail = UIHostingController(rootView: DetailView()); fixtureControllers.insert(key(detail))
        evidence.record("transition-start", fields: ["phase": phase, "controller": key(detail)])
        nav.pushViewController(detail, animated: true)
        try await wait("push-did-show") { !evidence.matching("did-show", field: "phase", value: "push").isEmpty }
        try await snapshot("push", controller: detail, occurrence: 2)
        phase = "pop"
        evidence.record("transition-start", fields: ["phase": phase, "controller": key(root)])
        nav.popViewController(animated: true)
        try await wait("pop-did-show") { !evidence.matching("did-show", field: "phase", value: "pop").isEmpty }
        try await snapshot("pop", controller: root, occurrence: 3)
        phase = "present"
        let modal = UIHostingController(rootView: ModalView()); fixtureControllers.insert(key(modal)); modal.modalPresentationStyle = .fullScreen
        evidence.record("transition-start", fields: ["phase": phase, "controller": key(modal)])
        nav.present(modal, animated: true) { [evidence] in
            evidence.record("completion", fields: ["phase": "present", "controller": String(describing: ObjectIdentifier(modal))])
        }
        try await wait("present-completion") { !evidence.matching("completion", field: "phase", value: "present").isEmpty }
        try await snapshot("present", controller: modal, occurrence: 4)
        phase = "dismiss"
        evidence.record("transition-start", fields: ["phase": phase, "controller": key(root)])
        nav.dismiss(animated: true) { [evidence] in
            evidence.record("completion", fields: ["phase": "dismiss", "controller": String(describing: ObjectIdentifier(root))])
        }
        try await wait("dismiss-completion") { !evidence.matching("completion", field: "phase", value: "dismiss").isEmpty }
        try await snapshot("dismiss", controller: root, occurrence: 5)
        evidence.record("native-teardown")
        window?.rootViewController = UIViewController()
        try await wait("final-inactive") {
            var latest: [String: Bool] = [:]
            for row in views() {
                if let view = row["view"] as? [String: Any], let id = view["id"] as? String, let active = view["is_active"] as? Bool { latest[id] = active }
            }
            return latest.count == 6 && latest.values.allSatisfy { !$0 }
        }
        try await wait("ttid-witness") { evidence.matching("ttid-message").count == 1 }
        evidence.record("stop-session")
        RUMMonitor.shared().stopSession()
    }
    private func finish(_ state: String, _ reason: String?) async throws {
        evidence.record("terminal", fields: ["state": state, "reason": reason as Any? ?? NSNull()])
        try await evidence.flush()
        let data = try JSONSerialization.data(withJSONObject: ["state": state, "identity": HostingSettings.identity], options: [.sortedKeys])
        try data.write(to: HostingSettings.output.appendingPathComponent("terminal.json"), options: .atomic)
    }
}
