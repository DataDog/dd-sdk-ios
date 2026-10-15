/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import MachO
import DatadogCore
@_spi(Internal)
import DatadogInternal
@testable import DatadogRUM

private final class Events: @unchecked Sendable {
    static let shared = Events()
    private let lock = NSLock()
    private var rows: [[String: Any]] = []

    func append(_ row: [String: Any]) {
        lock.lock()
        rows.append(row)
        lock.unlock()
    }

    func snapshot() -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return rows
    }
}

private final class Controller: UIViewController {
    private let readsLock = NSLock()
    private var backgroundReads = 0

    var backgroundReadCount: Int {
        readsLock.lock()
        defer { readsLock.unlock() }
        return backgroundReads
    }

    override var viewIfLoaded: UIView? {
        if !Thread.isMainThread {
            readsLock.lock()
            backgroundReads += 1
            readsLock.unlock()
        }
        return super.viewIfLoaded
    }
}

@MainActor
private enum Fixture {
    static var started = false

    static func configure() {
        Datadog.initialize(
            with: .init(clientToken: "local-fixture-no-credentials", env: "controller-threads"),
            trackingConsent: .granted
        )
        var configuration = RUM.Configuration(applicationID: "00000000-0000-0000-0000-000000000164")
        configuration.uiKitViewsPredicate = nil
        configuration.uiKitActionsPredicate = nil
        configuration.vitalsUpdateFrequency = nil
        configuration.trackSlowFrames = false
        configuration.trackFrustrations = false
        configuration.telemetrySampleRate = 0
        configuration.customEndpoint = URL(string: "http://127.0.0.1:9/rum")!
        configuration.viewEventMapper = { event in
            Events.shared.append([
                "id": event.view.id, "name": event.view.name ?? "", "active": event.view.isActive ?? false
            ])
            return event
        }
        RUM.enable(with: configuration)
    }

    static func drain(_ monitor: Monitor) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            monitor.currentSessionID { _ in continuation.resume() }
        }
    }

    static func background(_ body: @escaping () -> Void) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let isBackground = !Thread.isMainThread
                body()
                continuation.resume(returning: isBackground)
            }
        }
    }

    static func run(window: UIWindow, controller: Controller) async {
        guard !started else {
            return
        }
        started = true
        var checks: [String: Bool] = [:]
        let checkerLoaded = (0..<_dyld_image_count()).contains { index in
            guard let path = _dyld_get_image_name(index) else {
                return false
            }
            return String(cString: path).contains("libMainThreadChecker.dylib")
        }
        checks["main_thread_checker_loaded"] = checkerLoaded
        guard let nativeScene = window.windowScene,
              let monitor = RUMMonitor.shared() as? Monitor else {
            finish(checks: checks, details: ["setup_failure": "missing native scene or initialized monitor"])
            return
        }
        let sceneA = RUMSceneIdentifier(rawValue: nativeScene.session.persistentIdentifier)
        let sceneB = RUMSceneIdentifier(rawValue: "fixture-peer-B")
        checks["controller_mounted_in_native_scene"] = controller.viewIfLoaded?.window === window
        RUMContextHandoff.withValue(rumContext: nil, sceneIdentifier: sceneB.rawValue) {
            monitor.startView(viewController: controller, name: "Main A", attributes: [:])
        }
        await drain(monitor)
        let initialA = monitor.rumContextSnapshot(for: .scene(sceneA))
        checks["main_native_scene_overrides_handoff"] = initialA?.viewName == "Main A"
        checks["main_does_not_create_inferred_peer"] = monitor.rumContextSnapshot(for: .scene(sceneB)) == nil

        func startPeer(_ name: String) {
            RUMContextHandoff.withValue(rumContext: nil, sceneIdentifier: sceneB.rawValue) {
                monitor.startView(key: name, name: name, attributes: [:])
            }
        }
        startPeer("Peer B1")
        await drain(monitor)
        checks["background_start_worker"] = await background {
            monitor.startView(viewController: controller, name: "Background representative", attributes: [:])
        }
        await drain(monitor)
        checks["background_uses_representative"] = monitor.rumContextSnapshot(for: .scene(sceneB))?.viewName == "Background representative"
        checks["background_start_preserves_native_peer"] = monitor.rumContextSnapshot(for: .scene(sceneA))?.viewID == initialA?.viewID
        checks["background_stop_worker"] = await background {
            monitor.stopView(viewController: controller, attributes: [:])
        }
        await drain(monitor)
        checks["background_stop_removes_owned_branch"] = monitor.rumContextSnapshot(for: .scene(sceneB)) == nil
        checks["background_stop_preserves_native_peer"] = monitor.rumContextSnapshot(for: .scene(sceneA))?.viewID == initialA?.viewID

        startPeer("Peer B2")
        await drain(monitor)
        checks["inferred_start_worker"] = await background {
            RUMContextHandoff.withValue(rumContext: nil, sceneIdentifier: sceneB.rawValue) {
                monitor.startView(viewController: controller, name: "Background inferred", attributes: [:])
            }
        }
        await drain(monitor)
        checks["background_preserves_handoff"] = monitor.rumContextSnapshot(for: .scene(sceneB))?.viewName == "Background inferred"
        checks["inferred_start_preserves_native_peer"] = monitor.rumContextSnapshot(for: .scene(sceneA))?.viewID == initialA?.viewID
        checks["inferred_stop_worker"] = await background {
            RUMContextHandoff.withValue(rumContext: nil, sceneIdentifier: sceneB.rawValue) {
                monitor.stopView(viewController: controller, attributes: [:])
            }
        }
        await drain(monitor)
        checks["inferred_stop_removes_owned_branch"] = monitor.rumContextSnapshot(for: .scene(sceneB)) == nil

        monitor.startView(viewController: controller, name: "Main A2", attributes: [:])
        startPeer("Peer B3")
        await drain(monitor)
        let peerID = monitor.rumContextSnapshot(for: .scene(sceneB))?.viewID
        checks["identity_stop_worker"] = await background {
            monitor.stopView(viewController: controller, attributes: [:])
        }
        await drain(monitor)
        checks["identity_stop_removes_nonrepresentative_owner"] = monitor.rumContextSnapshot(for: .scene(sceneA)) == nil
        checks["identity_stop_preserves_representative_peer"] = peerID != nil && monitor.rumContextSnapshot(for: .scene(sceneB))?.viewID == peerID
        checks["no_background_hierarchy_reads"] = controller.backgroundReadCount == 0
        finish(checks: checks, details: [
            "native_scene_id": sceneA.rawValue,
            "native_scene_count": UIApplication.shared.connectedScenes.count,
            "peer_kind": "injected logical branch; not a second native window",
            "background_hierarchy_reads": controller.backgroundReadCount,
            "views": Events.shared.snapshot()
        ])
    }

    static func finish(checks: [String: Bool], details: [String: Any]) {
        let args = ProcessInfo.processInfo.arguments
        let index = args.firstIndex(of: "--run-id")
        let runID = index.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? ""
        let result: [String: Any] = ["run_id": runID, "checks": checks, "details": details]
        let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("result.json")
        do {
            try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                .write(to: file, options: .atomic)
        } catch {
            print("CONTROLLER_FIXTURE_WRITE_FAILED")
        }
    }
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Fixture.configure()
        return true
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else {
            return
        }
        let window = UIWindow(windowScene: scene)
        let controller = Controller()
        self.window = window
        window.rootViewController = controller
        window.makeKeyAndVisible()
        Task { await Fixture.run(window: window, controller: controller) }
    }
}
