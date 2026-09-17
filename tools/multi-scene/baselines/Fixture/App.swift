import UIKit
import DatadogCore
@_spi(Internal) import DatadogInternal
@_spi(Experimental) @testable import DatadogRUM

final class EventStore: @unchecked Sendable {
    static let shared = EventStore()
    private let lock = NSLock()
    private var rows: [[String: Any]] = []
    func append(_ row: [String: Any]) { lock.lock(); rows.append(row); lock.unlock() }
    func snapshot() -> [[String: Any]] { lock.lock(); defer { lock.unlock() }; return rows }
}

@MainActor enum Fixture {
    static let arguments = ProcessInfo.processInfo.arguments
    static func value(_ key: String, default fallback: String = "") -> String {
        guard let index = arguments.firstIndex(of: key), arguments.indices.contains(index + 1) else { return fallback }
        return arguments[index + 1]
    }
    static let mode = value("--mode", default: "automatic")
    static let manual = mode == "manual"
    static var window: UIWindow?
    static var started = false
    static let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("result.json")
    static func configure() {
        guard mode != "disabled" else { return }
        Datadog.initialize(with: Datadog.Configuration(clientToken: "local-fixture-no-credentials", env: "exp160-baseline", service: "exp160-baseline"), trackingConsent: .granted)
        var configuration = RUM.Configuration(applicationID: "00000000-0000-0000-0000-000000000160")
        configuration.uiKitViewsPredicate = manual ? nil : ViewsPredicate()
        configuration.uiKitActionsPredicate = DefaultUIKitRUMActionsPredicate()
        configuration.vitalsUpdateFrequency = nil
        configuration.trackSlowFrames = false
        configuration.trackFrustrations = false
        configuration.telemetrySampleRate = 0
        configuration.customEndpoint = URL(string: "http://127.0.0.1:9/rum")!
        configuration.viewEventMapper = { event in
            EventStore.shared.append(["type": "view", "id": event.view.id, "name": event.view.name ?? "", "active": event.view.isActive ?? false])
            return event
        }
        configuration.actionEventMapper = { event in
            EventStore.shared.append(["type": "action", "id": event.action.id, "owner": event.view.id, "name": event.action.target?.name ?? ""])
            return nil
        }
        configuration.resourceEventMapper = { event in
            EventStore.shared.append(["type": "resource", "id": event.resource.id, "owner": event.view.id, "url": event.resource.url])
            return nil
        }
        configuration.errorEventMapper = { event in
            EventStore.shared.append(["type": "error", "message": event.error.message]); return nil
        }
        RUM.enable(with: configuration)
    }
    static func mount(_ newWindow: UIWindow) {
        guard !started else { return }; started = true
        window = newWindow
        let home = Screen(name: "Home")
        let navigation = UINavigationController(rootViewController: home)
        newWindow.rootViewController = navigation
        newWindow.makeKeyAndVisible()
        Task { await execute(navigation) }
    }
    static func waitFor(_ predicate: () -> Bool) async -> Bool {
        for _ in 0..<400 {
            if predicate() { return true }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        return false
    }
    static func views(_ name: String) -> [String] {
        var ids: [String] = []
        for row in EventStore.shared.snapshot() where row["type"] as? String == "view" && row["name"] as? String == name {
            if let id = row["id"] as? String, !ids.contains(id) { ids.append(id) }
        }
        return ids
    }
    static func marker(_ phase: String) {
        let monitor = RUMMonitor.shared()
        monitor.addAction(type: .custom, name: phase)
        monitor.startResource(resourceKey: phase, url: URL(string: "https://fixture.invalid/" + phase)!)
        monitor.stopResource(resourceKey: phase, statusCode: 200, kind: .native)
    }
    static func samples(_ operation: () -> Void, count: Int = 20_000) -> [Double] {
        for _ in 0..<count { operation() } // Explicit discarded warm-up batch.
        return (0..<7).map { _ in
            let begin = DispatchTime.now().uptimeNanoseconds
            for _ in 0..<count { operation() }
            return Double(DispatchTime.now().uptimeNanoseconds - begin) / Double(count)
        }
    }
    static func eventSamples(_ operation: () -> Void) -> [UInt64] {
        var samples: [UInt64] = []; samples.reserveCapacity(2_000)
        for _ in 0..<2_000 {
            let begin = DispatchTime.now().uptimeNanoseconds
            operation()
            samples.append(DispatchTime.now().uptimeNanoseconds - begin)
        }
        return samples
    }
    static func execute(_ navigation: UINavigationController) async {
        var result: [String: Any] = ["mode": mode, "os": UIDevice.current.systemVersion, "model": UIDevice.current.model, "scene_count": UIApplication.shared.connectedScenes.count, "has_scene_manifest": Bundle.main.object(forInfoDictionaryKey: "UIApplicationSceneManifest") != nil, "run_id": value("--run-id"), "fixture_version": 1]
        var failures: [String] = []
        if mode == "automatic" || manual {
            if !(await waitFor { views("Home").count == 1 }) { failures.append("initial Home missing") }
            marker("Home1")
            navigation.pushViewController(Screen(name: "Detail"), animated: false)
            if !(await waitFor { views("Detail").count == 1 }) { failures.append("Detail missing") }
            marker("Detail1")
            navigation.popViewController(animated: false)
            if !(await waitFor { views("Home").count == 2 }) { failures.append("fresh Home missing") }
            marker("Home2")
            if !(await waitFor { EventStore.shared.snapshot().filter { ["action", "resource"].contains($0["type"] as? String ?? "") }.count >= 6 }) { failures.append("marker events missing") }
            result["events"] = EventStore.shared.snapshot()
        }
        if mode == "dispatch" || mode == "disabled" {
            // Actual UIApplication dispatch with an empty UIEvent: discarded-event path.
            // The internal fixture additionally measures a scene-bearing filtered touch.
            let event = UIEvent()
            result["dispatch_ns"] = samples { UIApplication.shared.sendEvent(event) }
            result["dispatch_event_ns"] = eventSamples { UIApplication.shared.sendEvent(event) }
            result["iterations_per_batch"] = 20_000
        }
        if mode == "internal" {
            if !(await waitFor { views("Home").count == 1 }) { failures.append("internal fixture live Home missing") }
            result["internal"] = InternalFixture.run(window: window!)
        }
        result["failures"] = failures
        do {
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: output, options: .atomic)
            print("EXP160_RESULT " + output.path)
        } catch { print("EXP160_WRITE_FAILED") }
    }
}

final class ViewsPredicate: UIKitRUMViewsPredicate {
    func rumView(for viewController: UIViewController) -> RUMView? {
        guard let screen = viewController as? Screen else { return nil }
        return RUMView(name: screen.screenName)
    }
}
final class Screen: UIViewController {
    let screenName: String
    init(name: String) { screenName = name; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("Fixture does not use storyboards") }
    override func viewDidLoad() { super.viewDidLoad(); view.backgroundColor = .systemBackground; title = screenName }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if Fixture.manual { RUMMonitor.shared().startView(key: screenName, name: screenName) }
    }
    override func viewWillDisappear(_ animated: Bool) {
        if Fixture.manual { RUMMonitor.shared().stopView(key: screenName) }
        super.viewWillDisappear(animated)
    }
}
@main final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Fixture.configure()
        if Bundle.main.object(forInfoDictionaryKey: "UIApplicationSceneManifest") == nil {
            let window = UIWindow(frame: UIScreen.main.bounds); self.window = window; Fixture.mount(window)
        }
        return true
    }
}
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene); self.window = window; Fixture.mount(window)
    }
}
