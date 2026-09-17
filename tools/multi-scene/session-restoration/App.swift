/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import DatadogCore
@_spi(Internal) import DatadogInternal
@testable import DatadogRUM

private final class Events: @unchecked Sendable {
    let lock = NSLock()
    var rows: [[String: String]] = []

    func append(_ row: [String: String]) {
        lock.lock()
        rows.append(row)
        lock.unlock()
    }

    func snapshot() -> [[String: String]] {
        lock.lock()
        defer { lock.unlock() }
        return rows
    }
}

@MainActor
private enum Fixture {
    static var windows: [UIWindow] = []
    static var requested = false
    static var started = false
    static var finished = false
    static var readinessDeadline = Date().addingTimeInterval(25)
    static var checks: [String: Bool] = [:]
    static var scenarios: [[String: Any]] = []

    static func ready() {
        guard !finished else { return }
        guard UIApplication.shared.applicationState == .active else {
            if Date() >= readinessDeadline { finish(setupFailure: "application did not become active"); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { ready() }
            return
        }
        if !requested {
            requested = true
            let activity = NSUserActivity(activityType: "com.datadoghq.restoration.peer")
            activity.targetContentIdentifier = UUID().uuidString
            UIApplication.shared.requestSceneSessionActivation(nil, userActivity: activity, options: nil) { _ in
                finish(setupFailure: "native scene activation failed")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
                if !started { finish(setupFailure: "second native scene did not become ready") }
            }
        }
        guard windows.count == 2, !started, !finished else { return }
        started = true
        Task { await run() }
    }

    static func drain(_ monitor: Monitor) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            monitor.currentSessionID { _ in continuation.resume() }
        }
    }

    static func configure(events: Events) -> Monitor? {
        Datadog.initialize(with: .init(clientToken: "local-fixture-no-credentials", env: "session-restoration"), trackingConsent: .granted)
        var configuration = RUM.Configuration(applicationID: "00000000-0000-0000-0000-000000000167")
        configuration.uiKitViewsPredicate = nil
        configuration.uiKitActionsPredicate = nil
        configuration.vitalsUpdateFrequency = nil
        configuration.trackSlowFrames = false
        configuration.trackFrustrations = false
        configuration.telemetrySampleRate = 0
        configuration.featureFlags = [.viewUpdates: false]
        configuration.customEndpoint = URL(string: "http://127.0.0.1:9/rum")!
        configuration.viewEventMapper = { event in
            events.append(["type": "view", "session": event.session.id, "view": event.view.id, "name": event.view.name ?? ""])
            return event
        }
        configuration.actionEventMapper = { event in
            events.append(["type": "action", "session": event.session.id, "view": event.view.id, "name": event.action.target?.name ?? ""])
            return event
        }
        configuration.resourceEventMapper = { event in
            events.append(["type": "resource", "session": event.session.id, "view": event.view.id])
            return event
        }
        RUM.enable(with: configuration)
        return RUMMonitor.shared() as? Monitor
    }

    static func run() async {
        let scenes = windows.compactMap(\.windowScene)
        let ids = scenes.map { RUMSceneIdentifier(rawValue: $0.session.persistentIdentifier) }
        checks["two_native_scenes"] = scenes.count == 2 && Set(ids).count == 2 && UIApplication.shared.connectedScenes.count == 2
        checks["both_controllers_mounted"] = windows.allSatisfy { $0.rootViewController?.viewIfLoaded?.window === $0 }
        checks["application_active"] = UIApplication.shared.applicationState == .active
        guard ids.count == 2 else { finish(setupFailure: "missing scene identities"); return }
        for boundary in ["stop", "timeout", "maximum"] {
            for navigation in ["start", "stop"] {
                let key = boundary + "_" + navigation
                let events = Events()
                guard let monitor = configure(events: events) else { finish(setupFailure: "monitor unavailable"); return }
                let start = Date()
                monitor.startView(viewController: windows[0].rootViewController!, name: "A", attributes: [:])
                monitor.startView(viewController: windows[1].rootViewController!, name: "B", attributes: [:])
                await drain(monitor)
                let oldA = monitor.rumContextSnapshot(for: .scene(ids[0]))
                let oldB = monitor.rumContextSnapshot(for: .scene(ids[1]))
                checks[key + "_initial_owners"] = oldA?.viewName == "A" && oldB?.viewName == "B"
                    && monitor.rumContextSnapshot(for: .processRepresentative)?.viewID == oldB?.viewID
                let duration = boundary == "stop" ? 1 : boundary == "timeout"
                    ? RUMSessionScope.Constants.sessionTimeoutDuration + 1
                    : RUMSessionScope.Constants.sessionMaxDuration + 1
                let end = start.addingTimeInterval(duration)
                if boundary == "maximum" {
                    var heartbeat = start.addingTimeInterval(60)
                    while heartbeat < end {
                        monitor.process(command: RUMAddUserActionCommand(time: heartbeat, attributes: [:], instrumentation: .manual, actionType: .custom, name: "Heartbeat"))
                        heartbeat.addTimeInterval(RUMSessionScope.Constants.sessionTimeoutDuration - 1)
                    }
                    await drain(monitor)
                    checks[key + "_maximum_not_timeout"] = monitor.rumContextSnapshot(for: .scene(ids[1]))?.sessionID == oldB?.sessionID
                }
                if boundary == "stop" {
                    monitor.stopSession()
                } else {
                    monitor.process(command: RUMHandleAppLifecycleEventCommand(time: end, event: .willEnterForeground))
                }
                await drain(monitor)
                checks[key + "_boundary_has_no_session"] = monitor.rumContextSnapshot(for: .processRepresentative) == nil
                let navigationTime = end.addingTimeInterval(1)
                if navigation == "start" {
                    monitor.process(command: RUMStartViewCommand(time: navigationTime, identity: ViewIdentifier("new"), name: "New", path: "new", globalAttributes: [:], attributes: [:], instrumentationType: .manual))
                } else {
                    monitor.process(command: RUMStopViewCommand(time: navigationTime, attributes: [:], identity: ViewIdentifier(windows[0].rootViewController!)))
                }
                await drain(monitor)
                // Observe immediately after navigation, before any marker could restore or select a peer.
                let newA = monitor.rumContextSnapshot(for: .scene(ids[0]))
                let newB = monitor.rumContextSnapshot(for: .scene(ids[1]))
                let peer = navigation == "start" ? newA : newB
                checks[key + "_navigation_owners"] = navigation == "start"
                    ? newA?.viewName == "A" && newB?.viewName == "New"
                    : newA == nil && newB?.viewName == "B"
                checks[key + "_fresh_session_and_views"] = peer != nil && peer?.sessionID != oldB?.sessionID
                    && (newA == nil || newA?.viewID != oldA?.viewID) && (newB == nil || newB?.viewID != oldB?.viewID)
                let peerScene = navigation == "start" ? ids[0] : ids[1]
                let markerTime = navigationTime.addingTimeInterval(1)
                var action = RUMAddUserActionCommand(time: markerTime, attributes: [:], instrumentation: .manual, actionType: .custom, name: "Peer marker")
                action.target = .scene(peerScene)
                monitor.process(command: action)
                var resource = RUMStartResourceCommand(resourceKey: key, time: markerTime, attributes: [:], url: "https://example.com/peer", httpMethod: .get, kind: .native, spanContext: nil)
                resource.target = .scene(peerScene)
                monitor.process(command: resource)
                monitor.process(command: RUMStopResourceCommand(resourceKey: key, time: markerTime.addingTimeInterval(1), attributes: [:], kind: .native, httpStatusCode: 200, size: 0))
                monitor.process(command: RUMStopSessionCommand(time: markerTime.addingTimeInterval(2)))
                await drain(monitor)
                let rows = events.snapshot()
                let markers = rows.filter { $0["type"] == "action" && $0["name"] == "Peer marker" }
                let resources = rows.filter { $0["type"] == "resource" }
                checks[key + "_peer_action"] = peer != nil && markers.count == 1 && markers[0]["view"] == peer?.viewID && markers[0]["session"] == peer?.sessionID
                checks[key + "_peer_resource"] = peer != nil && resources.count == 1 && resources[0]["view"] == peer?.viewID && resources[0]["session"] == peer?.sessionID
                let expected = Set([newA?.viewID, newB?.viewID].compactMap { $0 })
                let actual = Set(rows.filter { $0["type"] == "view" && $0["session"] == peer?.sessionID }.compactMap { $0["view"] })
                checks[key + "_exact_view_inventory"] = peer != nil && actual == expected
                scenarios.append(["name": key, "events": rows, "old_session": oldB?.sessionID ?? "", "new_session": peer?.sessionID ?? ""])
                Datadog.stopInstance()
            }
        }
        finish()
    }

    static func finish(setupFailure: String? = nil) {
        guard !finished else { return }
        finished = true
        let args = ProcessInfo.processInfo.arguments
        let index = args.firstIndex(of: "--run-id")
        let runID = index.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? ""
        let topology = windows.compactMap { window -> [String: Any]? in
            guard let scene = window.windowScene else { return nil }
            return ["scene_id": scene.session.persistentIdentifier, "activation_state": scene.activationState.rawValue,
                    "window_mounted": window.rootViewController?.viewIfLoaded?.window === window]
        }
        var result: [String: Any] = ["run_id": runID, "checks": checks, "details": ["topology": topology, "scenarios": scenarios]]
        if let setupFailure { result["setup_failure"] = setupFailure }
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
        let controller = UIViewController()
        controller.view.backgroundColor = .systemBackground
        window.rootViewController = controller
        self.window = window
        Fixture.windows.append(window)
        window.makeKeyAndVisible()
    }

    func sceneDidBecomeActive(_ scene: UIScene) { DispatchQueue.main.async { Fixture.ready() } }
}
