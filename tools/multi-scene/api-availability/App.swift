import UIKit
@_spi(Internal) import DatadogCore
@_spi(Internal) @_spi(Experimental) import DatadogRUM

final class ReceiptStore: @unchecked Sendable {
    static let shared = ReceiptStore()
    private let lock = NSLock()
    private var callbacks = 0
    private var automaticID: String?
    func completed() { lock.lock(); callbacks += 1; lock.unlock() }
    func automaticView(_ id: String) { lock.lock(); automaticID = id; lock.unlock() }
    var automaticOwner: String? { lock.lock(); defer { lock.unlock() }; return automaticID }
    var count: Int { lock.lock(); defer { lock.unlock() }; return callbacks }
}

@main final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let args = ProcessInfo.processInfo.arguments
        func argument(_ name: String) -> String { args[args.firstIndex(of: name)! + 1] }
        Datadog.initialize(with: .init(clientToken: "local-fixture-no-credentials", env: "exp225-local", service: "api-availability"), trackingConsent: .granted)
        var config = RUM.Configuration(applicationID: "00000000-0000-0000-0000-000000000225")
        config.customEndpoint = URL(string: argument("--endpoint"))!
        config.uiKitViewsPredicate = argument("--automatic") == "on" ? DefaultUIKitRUMViewsPredicate() : nil
        config.viewEventMapper = { event in
            if event.view.name == NSStringFromClass(FixtureScreen.self), event.view.isActive == true {
                ReceiptStore.shared.automaticView(event.view.id)
            }
            return event
        }
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
        window.rootViewController = FixtureScreen()
        window.rootViewController?.view.backgroundColor = .white
        self.window = window
        window.makeKeyAndVisible()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            await Fixture.run(scene: scene, window: window)
        }
    }
}

@MainActor enum Fixture {
    static func exercise(scene: UIWindowScene, targeted: Bool) {
        let monitor = RUMMonitor.shared()
        let lane = targeted ? "swift-targeted" : "swift-legacy"
        let target: RUMOperationViewTarget? = targeted ? RUMViewTarget.current(in: scene) : nil
        let attrs: [String: Encodable] = ["lane": lane, "start": 1]
        func tagged(_ form: String) -> [String: Encodable] { attrs.merging(["form": form]) { _, new in new } }
        if targeted { monitor.startView(key: lane, name: lane, in: scene, attributes: attrs) }
        else { monitor.startView(key: lane, name: lane, attributes: attrs) }
        if let target {
            monitor.addFeatureFlagEvaluation(name: "flag", value: true, view: target)
            monitor.addTiming(name: "ready", view: target)
            monitor.addViewLoadingTime(overwrite: true, view: target)
            monitor.addViewAttribute(forKey: "keep-single", value: "value", view: target)
            monitor.addViewAttributes(["keep-batch": 7, "remove-single": 8, "remove-batch": 9], view: target)
            monitor.removeViewAttribute(forKey: "remove-single", view: target)
            monitor.removeViewAttributes(forKeys: ["remove-batch"], view: target)
            monitor.addError(message: "message", source: .custom, view: target, attributes: tagged("message"))
            monitor.addError(error: NSError(domain: "expected", code: 1), source: .custom, view: target, attributes: tagged("error"))
            monitor.addError(error: NSError(domain: "callback", code: 2), source: .custom, view: target, attributes: tagged("callback")) { ReceiptStore.shared.completed() }
        } else {
            monitor.addFeatureFlagEvaluation(name: "flag", value: true)
            monitor.addTiming(name: "ready")
            monitor.addViewLoadingTime(overwrite: true)
            monitor.addViewAttribute(forKey: "keep-single", value: "value")
            monitor.addViewAttributes(["keep-batch": 7, "remove-single": 8, "remove-batch": 9])
            monitor.removeViewAttribute(forKey: "remove-single")
            monitor.removeViewAttributes(forKeys: ["remove-batch"])
            monitor.addError(message: "message", source: .custom, attributes: tagged("message"))
            monitor.addError(error: NSError(domain: "expected", code: 1), source: .custom, attributes: tagged("error"))
            monitor.addError(error: NSError(domain: "callback", code: 2), source: .custom, attributes: tagged("callback")) { ReceiptStore.shared.completed() }
        }
        let url = URL(string: "https://fixture.invalid/resource")!
        if let target {
            monitor.startResource(resourceKey: lane + "-request", request: URLRequest(url: url), view: target, attributes: tagged("request"))
            monitor.startResource(resourceKey: lane + "-url", url: url, view: target, attributes: tagged("url"))
            monitor.startResource(resourceKey: lane + "-method", httpMethod: .put, urlString: url.absoluteString, view: target, attributes: tagged("method"))
            monitor.addAction(type: .custom, name: "instant", view: target, attributes: attrs)
            monitor.startAction(type: .custom, name: "continuous", view: target, attributes: attrs)
            monitor.stopAction(type: .custom, name: "ended", view: target, attributes: attrs)
            monitor.startOperation(name: "operation", operationKey: lane, view: target, attributes: attrs)
            monitor.succeedOperation(name: "operation", operationKey: lane, view: target, attributes: attrs)
            monitor.failOperation(name: "operation", operationKey: lane + "-failure", reason: .error, view: target, attributes: attrs)
            monitor.stopView(key: lane, in: scene, attributes: ["stop": 2])
        } else {
            monitor.startResource(resourceKey: lane + "-request", request: URLRequest(url: url), attributes: tagged("request"))
            monitor.startResource(resourceKey: lane + "-url", url: url, attributes: tagged("url"))
            monitor.startResource(resourceKey: lane + "-method", httpMethod: .put, urlString: url.absoluteString, attributes: tagged("method"))
            monitor.addAction(type: .custom, name: "instant", attributes: attrs)
            monitor.startAction(type: .custom, name: "continuous", attributes: attrs)
            monitor.stopAction(type: .custom, name: "ended", attributes: attrs)
            monitor.startOperation(name: "operation", operationKey: lane, attributes: attrs)
            monitor.succeedOperation(name: "operation", operationKey: lane, attributes: attrs)
            monitor.failOperation(name: "operation", operationKey: lane + "-failure", reason: .error, attributes: attrs)
            monitor.stopView(key: lane, attributes: ["stop": 2])
        }
        completeResources(lane)
    }

    static func completeResources(_ prefix: String) {
        for form in ["request", "url", "method"] {
            RUMMonitor.shared().stopResource(resourceKey: prefix + "-" + form, statusCode: 200, kind: .native, size: 1, attributes: ["finish": 3])
        }
    }

    static func run(scene: UIWindowScene, window: UIWindow) async {
        let args = ProcessInfo.processInfo.arguments
        func argument(_ name: String) -> String { args[args.firstIndex(of: name)! + 1] }
        let sceneID = scene.session.persistentIdentifier
        let automatic = argument("--automatic") == "on"
        func ready() -> Bool {
            (window.rootViewController as? FixtureScreen)?.appeared == true && window.isKeyWindow &&
                window.windowScene === scene && UIApplication.shared.applicationState == .active &&
                (!automatic || ReceiptStore.shared.automaticOwner != nil)
        }
        for _ in 0..<200 where !ready() { try? await Task.sleep(nanoseconds: 20_000_000) }
        let preflight: [String: Any] = ["ready": ready(), "at": Date().timeIntervalSince1970,
            "scene": sceneID, "automatic_owner": ReceiptStore.shared.automaticOwner as Any? ?? NSNull(),
            "expected_automatic_name": NSStringFromClass(FixtureScreen.self),
            "controller_appeared": (window.rootViewController as? FixtureScreen)?.appeared == true,
            "key_window": window.isKeyWindow, "owned_scene": window.windowScene === scene,
            "foreground": UIApplication.shared.applicationState == .active]
        guard ready() else {
            write(["run_id": argument("--run-id"), "preflight": preflight, "failure": "owned foreground view not ready"])
            return
        }
        exercise(scene: scene, targeted: false)
        exercise(scene: scene, targeted: true)
        let main = APIInvokeMain(scene)
        completeResources("objc-main")
        let monitor = RUMMonitor.shared()
        monitor.startView(key: "guard", name: "guard", attributes: ["lane": "guard"])
        monitor.addViewAttributes(["keep-single": "single", "keep-batch": "batch"])
        monitor.startAction(type: .custom, name: "guard-action", attributes: ["lane": "guard"])
        Datadog.flush()
        var boundaryURL = URLComponents(string: argument("--endpoint"))!
        boundaryURL.path = "/boundary"
        boundaryURL.queryItems = [URLQueryItem(name: "run_id", value: argument("--run-id"))]
        let boundary: [String: Any]
        do {
            let (data, response) = try await URLSession.shared.data(from: boundaryURL.url!)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  value["run_id"] as? String == argument("--run-id") else { throw NSError(domain: "boundary", code: 1) }
            boundary = value
        } catch {
            write(["run_id": argument("--run-id"), "failure": "pre-background capture boundary unavailable"])
            return
        }
        let background: NSDictionary = await withCheckedContinuation { continuation in
            APIInvokeBackground(scene) { receipt in continuation.resume(returning: receipt as NSDictionary) }
        }
        // A main-queue turn makes a deferred actor/UIKit hop observable before the terminal event.
        await Task.yield()
        monitor.stopAction(type: .custom, name: "guard-ended", attributes: ["lane": "guard", "finish": 3])
        monitor.stopView(key: "guard", attributes: ["stop": 2])
        completeResources("off-main")
        let receipt: [String: Any] = [
            "run_id": argument("--run-id"), "os": UIDevice.current.systemVersion,
            "automatic": argument("--automatic"), "pid": ProcessInfo.processInfo.processIdentifier,
            "main": main, "background": background, "callbacks": ReceiptStore.shared.count,
            "scene_reads_after_main_turn": APIUnreadSceneReads(),
            "scene_unchanged": sceneID == scene.session.persistentIdentifier,
            "owned_window": window.windowScene === scene && window.isKeyWindow && window.rootViewController != nil,
            "source": Bundle.main.object(forInfoDictionaryKey: "FixtureSource") as! String, "preflight": preflight,
            "pre_background": boundary
        ]
        Datadog.flush()
        write(receipt)
    }

    static func write(_ receipt: [String: Any]) {
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("result.json")
        do { try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys]).write(to: output, options: .atomic) }
        catch { print("EXP225 receipt write failed") }
    }
}
