/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import SwiftUI
import DatadogCore
@_spi(Internal) import DatadogInternal
@testable import DatadogLogs
@_spi(Experimental) @testable import DatadogRUM

private final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var rows: [[String: String]] = []
    func append(_ row: [String: String]) { lock.lock(); rows.append(row); lock.unlock() }
    func snapshot() -> [[String: String]] { lock.lock(); defer { lock.unlock() }; return rows }
}

private struct AutomaticPredicate: SwiftUIRUMViewsPredicate {
    func rumView(for extractedViewName: String) -> RUMView? { nil }
}

@available(iOS 27.0, *)
private struct ProvidingContent: SwiftUI.View, RUMNavigationTransitionProviding {
    let source: RUMNavigationTransitions
    let tick: Int
    var rumNavigationTransitions: RUMNavigationTransitions { source }
    var body: some SwiftUI.View { Text("Customer content \(tick)") }
}

@available(iOS 27.0, *)
private struct Content: SwiftUI.View {
    let source: RUMNavigationTransitions
    let mode: String
    let tick: Int
    var body: some SwiftUI.View {
        if mode == "explicit" {
            RUMNavigationHost(transitions: source) { Text("Customer content \(tick)") }
        } else {
            RUMNavigationHost { ProvidingContent(source: source, tick: tick) }
        }
    }
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

    static func settle() async {
        for _ in 0..<10 { try? await Task.sleep(nanoseconds: 20_000_000) }
    }

    static func readers(in view: UIView) -> [RUMSceneIdentifierReader.ObserverView] {
        (view as? RUMSceneIdentifierReader.ObserverView).map { [$0] } ?? view.subviews.flatMap { readers(in: $0) }
    }

    static func configure(events: Events) -> (Monitor, LoggerProtocol)? {
        Datadog.initialize(with: .init(clientToken: "local-fixture-no-credentials", env: "retained-reader"), trackingConsent: .granted)
        var configuration = RUM.Configuration(applicationID: "00000000-0000-0000-0000-000000000171")
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
        configuration.resourceEventMapper = { event in
            events.append(["type": "resource", "view": event.view.id, "url": event.resource.url, "session": event.session.id])
            return event
        }
        RUM.enable(with: configuration)
        Logs.enable(with: .init(eventMapper: { event in
            events.append(["type": "log", "message": event.message,
                           "view": event.attributes.internalAttributes?["view.id"] as? String ?? "",
                           "session": event.attributes.internalAttributes?["session_id"] as? String ?? ""])
            return event
        }, customEndpoint: URL(string: "http://127.0.0.1:9/logs")!))
        guard let monitor = RUMMonitor.shared() as? Monitor else { return nil }
        return (monitor, Logger.create(with: .init(bundleWithTraceEnabled: false)))
    }

    static func emit(_ name: String, monitor: Monitor, logger: LoggerProtocol) {
        // These reader lifecycle callbacks have no UI-event handoff. Use the
        // ordinary APIs immediately; their accepted command ordering must hold.
        monitor.startResource(resourceKey: name, url: URL(string: "https://fixture.invalid/\(name)")!, attributes: [:])
        logger.info(name)
        monitor.stopResource(resourceKey: name, statusCode: 200, kind: .native, size: 1, attributes: [:])
    }

    static func checkMarkers(_ name: String, context: RUMCoreContext?, events: Events) {
        let rows = events.snapshot()
        let resources = rows.filter { $0["type"] == "resource" && $0["url"] == "https://fixture.invalid/\(name)" }
        let logs = rows.filter { $0["type"] == "log" && $0["message"] == name }
        checks[name + "_resource_owner"] = context != nil && resources.count == 1
            && resources[0]["view"] == context?.viewID && resources[0]["session"] == context?.sessionID
        checks[name + "_log_owner"] = context != nil && logs.count == 1
            && logs[0]["view"] == context?.viewID && logs[0]["session"] == context?.sessionID
    }

    @available(iOS 27.0, *)
    static func observerCount(_ source: RUMNavigationTransitions) -> Int {
        guard let value = Mirror(reflecting: source).children.first(where: { $0.label == "observers" })?.value else { return -1 }
        return Mirror(reflecting: value).children.count
    }

    @available(iOS 27.0, *)
    static func scenario(_ mode: String, window: UIWindow) async {
        let events = Events()
        guard let (monitor, logger) = configure(events: events), let scene = window.windowScene,
              let instrumentation = CoreRegistry.default.get(feature: RUMFeature.self)?.instrumentation else { return }
        let handler = instrumentation.viewsHandler
        let registry = instrumentation.swiftUIViewAuthorityRegistry
        let sceneID = RUMSceneIdentifier(rawValue: scene.session.persistentIdentifier)
        let peerID = RUMSceneIdentifier(rawValue: "logical-peer")
        let source = RUMNavigationTransitions(currentDestination: RUMView(name: "Initial"))
        let host = UIHostingController(rootView: Content(source: source, mode: mode, tick: 0))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        await settle()
        await drain(monitor)
        checks[mode + "_mounted"] = host.viewIfLoaded?.window === window
        checks[mode + "_registry_present"] = registry != nil
        let initial = monitor.rumContextSnapshot(for: .scene(sceneID))
        checks[mode + "_initial_owner"] = initial?.viewName == "Initial"
        handler.notify_semanticDestinationAppear(identity: "peer", name: "Peer", path: "/peer", attributes: [:], sceneIdentifier: peerID)
        await drain(monitor)
        let peer = monitor.rumContextSnapshot(for: .scene(peerID))
        checks[mode + "_peer_owner"] = peer?.viewName == "Peer"
        guard let reader = readers(in: host.view).first, let retainedMount = reader.onMount else { return }
        checks[mode + "_reader_present"] = reader.currentSceneIdentifier == sceneID
        checks[mode + "_existing_callback_ready"] = observerCount(source) == 1
        window.rootViewController = UIViewController()
        await settle()
        await drain(monitor)
        checks[mode + "_removed_native_window"] = reader.window == nil && host.viewIfLoaded?.window == nil
        checks[mode + "_detach_releases"] = registry?.isAutomaticViewSuppressed(for: host) == false
            && monitor.rumContextSnapshot(for: .scene(sceneID))?.viewID == nil
        checks[mode + "_source_unsubscribed"] = observerCount(source) == 0
        source.willNavigate(id: "while-detached", destination: RUMView(name: "Latest"))
        source.commit(id: "while-detached")
        await drain(monitor)
        checks[mode + "_input_while_detached_no_owner"] = monitor.rumContextSnapshot(for: .scene(sceneID))?.viewID == nil
        checks[mode + "_peer_unchanged"] = monitor.rumContextSnapshot(for: .scene(peerID))?.viewID == peer?.viewID
        checks[mode + "_retained_reader_still_exists"] = readers(in: host.view).contains { $0 === reader }
        var mountCount = 0
        var beforeBody = false
        var mountedScene: RUMSceneIdentifier?
        reader.onMount = { mounted in
            mountCount += 1
            if mountCount == 1 {
                beforeBody = observerCount(source) == 0
                mountedScene = mounted
            }
            retainedMount(mounted)
            if mountCount == 1 {
                // Submit inside the first actual reader mount, before UIKit/SwiftUI can rerender.
                emit(mode + "_mount", monitor: monitor, logger: logger)
            }
        }
        // Deliberately keep the exact root value and retained hosting controller.
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        checks[mode + "_first_mount_intercepted"] = mountCount == 1
        checks[mode + "_first_mount_before_body"] = beforeBody
        checks[mode + "_first_mount_source_scene"] = mountedScene == sceneID && reader.window === window
        checks[mode + "_source_reobserved"] = observerCount(source) == 1
        checks[mode + "_authority_restored"] = registry?.isAutomaticViewSuppressed(for: host) == true
        await drain(monitor)
        let restored = monitor.rumContextSnapshot(for: .scene(sceneID))
        checks[mode + "_latest_owner"] = restored?.viewName == "Latest"
        checks[mode + "_fresh_id"] = restored?.viewID != nil && restored?.viewID != initial?.viewID
        await settle()
        checkMarkers(mode + "_mount", context: restored, events: events)
        reader.notifyCurrentAttachment()
        await drain(monitor)
        checks[mode + "_duplicate_reader_no_change"] = monitor.rumContextSnapshot(for: .scene(sceneID))?.viewID == restored?.viewID
        checks[mode + "_peer_survives_mount"] = monitor.rumContextSnapshot(for: .scene(peerID))?.viewID == peer?.viewID
        window.rootViewController = UIViewController()
        await settle()
        await drain(monitor)
        checks[mode + "_final_detach_releases"] = registry?.isAutomaticViewSuppressed(for: host) == false
            && monitor.rumContextSnapshot(for: .scene(sceneID))?.viewID == nil
        checks[mode + "_source_unsubscribed_final"] = observerCount(source) == 0
        handler.notify_semanticDestinationDisappear(identity: "peer", sceneIdentifier: peerID)
        monitor.stopSession()
        await drain(monitor)
        let rows = events.snapshot()
        let owned = rows.filter { $0["type"] == "view" && ["Initial", "Latest"].contains($0["name"] ?? "") }
        checks[mode + "_two_owned_occurrences"] = Set(owned.compactMap { $0["id"] }).count == 2
            && Set(owned.compactMap { $0["name"] }) == Set(["Initial", "Latest"])
        checks[mode + "_one_peer_occurrence"] = Set(rows.filter { $0["type"] == "view" && $0["name"] == "Peer" }.compactMap { $0["id"] }).count == 1
        checks[mode + "_no_intermediate_home"] = !rows.contains { $0["type"] == "view" && !["Initial", "Latest", "Peer", "ApplicationLaunch"].contains($0["name"] ?? "") }
        scenarios.append(["mode": mode, "scene_id": sceneID.rawValue, "peer": "logical", "mount_callback_count": mountCount,
                          "root_value_replaced": false, "events": rows])
        Datadog.stopInstance()
    }

    static func run(window: UIWindow) async {
        guard !started else { return }
        started = true
        await settle()
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
