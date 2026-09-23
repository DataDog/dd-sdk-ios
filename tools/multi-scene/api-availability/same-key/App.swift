import UIKit
@_spi(Internal) import DatadogCore
@_spi(Experimental) import DatadogRUM

@main final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Datadog.initialize(with: .init(clientToken: "local-fixture-no-credentials", env: "exp225-local", service: "same-key-api"), trackingConsent: .granted)
        var config = RUM.Configuration(applicationID: "00000000-0000-0000-0000-000000000225")
        config.customEndpoint = URL(string: Fixture.argument("--endpoint"))!
        config.uiKitViewsPredicate = nil
        config.uiKitActionsPredicate = nil
        config.longTaskThreshold = nil
        config.vitalsUpdateFrequency = nil
        config.trackSlowFrames = false
        config.trackFrustrations = false
        config.trackMemoryWarnings = false
        config.telemetrySampleRate = 0
        RUM.enable(with: config)
        return true
    }
}

final class FixtureScreen: UIViewController {
    private(set) var appeared = false
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); appeared = true }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        let controller = FixtureScreen()
        controller.view.backgroundColor = .white
        window.rootViewController = controller
        self.window = window
        window.makeKeyAndVisible()
        Fixture.connect(scene, window: window, activities: options.userActivities)
    }
}

@MainActor enum Fixture {
    static var windows: [UIWindow] = []
    static var started = false
    static var operations: [String] = []
    static var acknowledgments: [[String: Any]] = []
    static var activitiesByScene: [String: [[String: String]]] = [:]
    static var activationRequested = false
    static var activationError: String?
    static let key = "shared-key"
    static var language: String { argument("--language") }
    static func argument(_ name: String) -> String {
        let args = ProcessInfo.processInfo.arguments
        return args[args.firstIndex(of: name)! + 1]
    }
    static func connect(_ scene: UIWindowScene, window: UIWindow, activities: Set<NSUserActivity>) {
        activitiesByScene[scene.session.persistentIdentifier] = activities.map { ["type": $0.activityType, "run_id": $0.userInfo?["run_id"] as? String ?? ""] }
        windows.append(window)
        guard !started else { return }
        started = true
        Task { await run() }
    }
    static func rectangle(_ value: CGRect) -> [Double] { [value.origin.x, value.origin.y, value.width, value.height] }
    static func identity(_ object: AnyObject) -> String { String(describing: ObjectIdentifier(object)) }
    static func topology() -> [[String: Any]] {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.map { scene in
            let owned = windows.firstIndex { $0.windowScene === scene }
            return ["scene": scene.session.persistentIdentifier, "state": scene.activationState.rawValue,
                    "owner": owned.map { $0 == 0 ? "A" : "B" } as Any? ?? NSNull(),
                    "activities": activitiesByScene[scene.session.persistentIdentifier] ?? [],
                    "role": scene.session.role.rawValue, "bounds": rectangle(scene.coordinateSpace.bounds),
                    "screen": rectangle(scene.screen.bounds), "windows": scene.windows.map { window -> [String: Any] in
                        let controller = window.rootViewController
                        return ["id": identity(window), "fixture_owned": windows.contains { $0 === window },
                                "scene_match": window.windowScene === scene, "key": window.isKeyWindow,
                                "hidden": window.isHidden, "alpha": window.alpha, "bounds": rectangle(window.bounds),
                                "controller": controller.map(identity) as Any? ?? NSNull(),
                                "appeared": (controller as? FixtureScreen)?.appeared == true,
                                "mounted": controller?.viewIfLoaded?.window === window]
                    }]
        }.sorted { ($0["scene"] as! String) < ($1["scene"] as! String) }
    }
    static func ready(_ count: Int) -> Bool {
        windows.count == count && UIApplication.shared.connectedScenes.count == count && UIApplication.shared.applicationState == .active &&
        windows.allSatisfy { window in
            window.windowScene?.activationState == .foregroundActive && window.isKeyWindow && !window.isHidden &&
            window.alpha > 0 && window.bounds.width > 0 && window.bounds.height > 0 &&
            (window.rootViewController as? FixtureScreen)?.appeared == true && window.rootViewController?.viewIfLoaded?.window === window
        }
    }
    static func waitReady(_ count: Int, deadline: TimeInterval) async -> Bool {
        while !ready(count) && ProcessInfo.processInfo.systemUptime < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return ready(count)
    }
    static func native(_ phase: String) -> [String: Any] {
        ["run_id": argument("--run-id"), "source": Bundle.main.object(forInfoDictionaryKey: "FixtureSource") as! String,
         "pid": ProcessInfo.processInfo.processIdentifier, "os": UIDevice.current.systemVersion, "language": language,
         "activation_requested": activationRequested, "activation_error": activationError as Any? ?? NSNull(),
         "phase": phase, "at": Date().timeIntervalSince1970, "uptime": ProcessInfo.processInfo.systemUptime,
         "application_active": UIApplication.shared.applicationState == .active, "topology": topology(),
         "operations": operations, "key": key]
    }
    static func checkpoint(_ phase: String) async throws {
        guard ready(2), activationError == nil else { throw NSError(domain: "topology-or-activation", code: 1) }
        Datadog.flush()
        var components = URLComponents(string: argument("--endpoint"))!
        components.path = "/checkpoint"
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.httpBody = try JSONSerialization.data(withJSONObject: native(phase), options: [.sortedKeys])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let ack = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              ack["run_id"] as? String == argument("--run-id"), ack["phase"] as? String == phase else {
            throw NSError(domain: "checkpoint-rejected", code: 1)
        }
        acknowledgments.append(ack)
        guard ready(2) else { throw NSError(domain: "topology-after-ack", code: 1) }
    }
    static func invoke(_ operation: String, owner: String) throws {
        guard ready(2), let scene = windows[owner == "A" ? 0 : 1].windowScene else { throw NSError(domain: "precritical-topology", code: 1) }
        if language == "objc" {
            guard SameKeyInvoke(operation, owner, scene) else { throw NSError(domain: "objc-call", code: 1) }
        } else {
            let monitor = RUMMonitor.shared()
            let target = RUMViewTarget.current(in: scene)
            let attrs: [String: Encodable] = ["owner": owner]
            switch operation {
            case "start": monitor.startView(key: key, name: "view-" + owner, in: scene, attributes: attrs)
            case "work":
                monitor.addViewAttribute(forKey: "metadata", value: owner, view: target)
                monitor.addAction(type: .custom, name: "action-" + owner, view: target, attributes: attrs)
                monitor.addError(message: "error-" + owner, source: .custom, view: target, attributes: attrs)
                monitor.startResource(resourceKey: "resource-" + owner, url: URL(string: "https://fixture.invalid/" + owner)!, view: target, attributes: attrs)
            case "stop": monitor.stopView(key: key, in: scene, attributes: ["stopped": owner])
            case "complete": monitor.stopResource(resourceKey: "resource-" + owner, statusCode: 200, kind: .native, size: 1, attributes: ["finished": owner])
            case "reject":
                monitor.addAction(type: .custom, name: "rejected-B", view: target, attributes: attrs)
                monitor.addError(message: "rejected-B", source: .custom, view: target, attributes: attrs)
                monitor.addViewAttribute(forKey: "metadata", value: "rejected-B", view: target)
            case "peer": monitor.addAction(type: .custom, name: "peer-A", view: target, attributes: attrs)
            default: throw NSError(domain: "operation", code: 1)
            }
        }
        operations.append(operation + "-" + owner)
    }
    static func run() async {
        do {
            let deadline = ProcessInfo.processInfo.systemUptime + 30
            guard await waitReady(1, deadline: deadline) else { throw NSError(domain: "first-scene-readiness", code: 1) }
            let activity = NSUserActivity(activityType: "com.datadoghq.exp225.same-key")
            activity.userInfo = ["run_id": argument("--run-id")]
            activationRequested = true
            UIApplication.shared.requestSceneSessionActivation(nil, userActivity: activity, options: nil) { _ in
                activationError = "ordinary scene activation rejected"
            }
            guard await waitReady(2, deadline: deadline) else { throw NSError(domain: activationError ?? "concurrent-scene-readiness", code: 1) }
            try await checkpoint("ready")
            try invoke("start", owner: "A"); try invoke("start", owner: "B")
            try invoke("work", owner: "A"); try invoke("work", owner: "B")
            try await checkpoint("overlap")
            try invoke("stop", owner: "B"); try invoke("complete", owner: "B")
            try invoke("reject", owner: "B"); try invoke("peer", owner: "A")
            try await checkpoint("stopped-B")
            try invoke("stop", owner: "A"); try invoke("complete", owner: "A")
            try await checkpoint("stopped-A")
            var result = native("complete"); result["acknowledgments"] = acknowledgments
            write(result)
        } catch {
            var result = native("failed"); result["failure"] = (error as NSError).domain
            result["acknowledgments"] = acknowledgments; write(result)
        }
    }
    static func write(_ value: [String: Any]) {
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("result.json")
        do { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]).write(to: output, options: .atomic) }
        catch { print("Same-key receipt write failed") }
    }
}
