/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import SwiftUI
import DatadogCore
@_spi(Internal) import DatadogInternal
@_spi(Experimental) @testable import DatadogRUM

private final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var rows: [[String: String]] = []
    func append(_ row: [String: String]) { lock.lock(); rows.append(row); lock.unlock() }
    func snapshot() -> [[String: String]] { lock.lock(); defer { lock.unlock() }; return rows }
}

private struct AutomaticPredicate: SwiftUIRUMViewsPredicate {
    func rumView(for extractedViewName: String) -> RUMView? { RUMView(name: "Automatic") }
}

@available(iOS 27.0, *)
private struct ProvidingContent: SwiftUI.View, RUMNavigationTransitionProviding {
    let source: RUMNavigationTransitions
    var rumNavigationTransitions: RUMNavigationTransitions { source }
    var body: some SwiftUI.View { Text("Customer navigation") }
}

@MainActor
private enum Fixture {
    static var started = false
    static var checks: [String: Bool] = [:]
    static var scenarios: [[String: Any]] = []

    static func drain(_ monitor: Monitor) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            monitor.currentSessionID { _ in continuation.resume() }
        }
    }

    static func configure(events: Events) -> Monitor? {
        Datadog.initialize(with: .init(clientToken: "local-fixture-no-credentials", env: "pending-authority"), trackingConsent: .granted)
        var configuration = RUM.Configuration(applicationID: "00000000-0000-0000-0000-000000000169")
        configuration.uiKitViewsPredicate = nil
        configuration.swiftUIViewsPredicate = AutomaticPredicate()
        configuration.uiKitActionsPredicate = nil
        configuration.vitalsUpdateFrequency = nil
        configuration.trackSlowFrames = false
        configuration.trackFrustrations = false
        configuration.telemetrySampleRate = 0
        configuration.featureFlags = [.viewUpdates: false]
        configuration.customEndpoint = URL(string: "http://127.0.0.1:9/rum")!
        configuration.viewEventMapper = { event in
            events.append(["type": "view", "id": event.view.id, "name": event.view.name ?? "", "session": event.session.id])
            return event
        }
        configuration.actionEventMapper = { event in
            events.append(["type": "action", "view": event.view.id, "name": event.action.target?.name ?? "", "session": event.session.id])
            return event
        }
        RUM.enable(with: configuration)
        return RUMMonitor.shared() as? Monitor
    }

    @available(iOS 27.0, *)
    static func scenario(_ mode: String, window: UIWindow) async {
        let events = Events()
        guard let monitor = configure(events: events), let scene = window.windowScene else { return }
        let sceneID = RUMSceneIdentifier(rawValue: scene.session.persistentIdentifier)
        let source = RUMNavigationTransitions()
        let content: AnyView
        if mode == "explicit" {
            content = AnyView(RUMNavigationHost(transitions: source) { Text("Customer navigation") })
        } else {
            content = AnyView(RUMNavigationHost { ProvidingContent(source: source) })
        }
        let host = UIHostingController(rootView: content)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        for _ in 0..<15 { try? await Task.sleep(nanoseconds: 20_000_000) }
        await drain(monitor)
        let registry = CoreRegistry.default.get(feature: RUMFeature.self)?.instrumentation.swiftUIViewAuthorityRegistry
        checks[mode + "_mounted"] = host.viewIfLoaded?.window === window
        checks[mode + "_registry_present"] = registry != nil
        checks[mode + "_pending_automatic_eligible"] = registry?.isAutomaticViewSuppressed(for: host) == false
        let automatic = monitor.rumContextSnapshot(for: .scene(sceneID))
        checks[mode + "_pending_automatic_owner"] = automatic?.viewName == "Automatic"
        source.willNavigate(id: "cancelled", destination: RUMView(name: "Unaccepted"))
        source.cancel(id: "cancelled")
        source.commit(id: "cancelled")
        checks[mode + "_proposal_keeps_owner"] = registry?.isAutomaticViewSuppressed(for: host) == false
            && monitor.rumContextSnapshot(for: .scene(sceneID))?.viewID == automatic?.viewID
        monitor.addAction(type: .custom, name: "Before", attributes: [:])
        await drain(monitor)
        let before = events.snapshot().filter { $0["type"] == "action" && $0["name"] == "Before" }
        checks[mode + "_before_marker_owner"] = automatic != nil && before.count == 1 && before[0]["view"] == automatic?.viewID

        source.setInitialDestination(RUMView(name: "Semantic"))
        // Submit at the accepted-input boundary, before waiting or another UI lifecycle callback.
        monitor.addAction(type: .custom, name: "Immediate", attributes: [:])
        checks[mode + "_semantic_authority"] = registry?.isAutomaticViewSuppressed(for: host) == true
        await drain(monitor)
        let semantic = monitor.rumContextSnapshot(for: .scene(sceneID))
        checks[mode + "_semantic_owner"] = semantic?.viewName == "Semantic"
        checks[mode + "_fresh_semantic_id"] = semantic != nil && automatic != nil && semantic?.viewID != automatic?.viewID
        let immediate = events.snapshot().filter { $0["type"] == "action" && $0["name"] == "Immediate" }
        checks[mode + "_immediate_marker_owner"] = semantic != nil && immediate.count == 1
            && immediate[0]["view"] == semantic?.viewID && immediate[0]["session"] == semantic?.sessionID
        source.setInitialDestination(RUMView(name: "Ignored"))
        await drain(monitor)
        checks[mode + "_duplicate_initial_no_change"] = monitor.rumContextSnapshot(for: .scene(sceneID))?.viewID == semantic?.viewID
        window.rootViewController = UIViewController()
        for _ in 0..<10 { try? await Task.sleep(nanoseconds: 20_000_000) }
        await drain(monitor)
        checks[mode + "_final_detach_releases"] = registry?.isAutomaticViewSuppressed(for: host) == false
        monitor.stopSession()
        await drain(monitor)
        let rows = events.snapshot()
        let semanticViews = rows.filter { $0["type"] == "view" && $0["name"] == "Semantic" }
        checks[mode + "_one_semantic_view"] = Set(semanticViews.compactMap { $0["id"] }).count == 1
        checks[mode + "_no_unaccepted_views"] = !rows.contains { $0["type"] == "view" && ["Unaccepted", "Ignored"].contains($0["name"] ?? "") }
        scenarios.append(["mode": mode, "scene_id": sceneID.rawValue, "events": rows])
        Datadog.stopInstance()
    }

    static func run(window: UIWindow) async {
        guard !started else { return }
        started = true
        for _ in 0..<5 { try? await Task.sleep(nanoseconds: 20_000_000) }
        checks["native_scene_active"] = window.windowScene != nil && UIApplication.shared.applicationState == .active
        if #available(iOS 27.0, *) {
            await scenario("explicit", window: window)
            await scenario("capability", window: window)
        }
        let args = ProcessInfo.processInfo.arguments
        let index = args.firstIndex(of: "--run-id")
        let runID = index.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? ""
        let result: [String: Any] = ["run_id": runID, "checks": checks, "details": ["scenarios": scenarios]]
        let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("result.json")
        try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: file, options: .atomic)
    }
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController()
        self.window = window
        window.makeKeyAndVisible()
    }
    func sceneDidBecomeActive(_ scene: UIScene) {
        guard let window else { return }
        Task { await Fixture.run(window: window) }
    }
}
