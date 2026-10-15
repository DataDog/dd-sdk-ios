import UIKit
@_spi(Internal) import DatadogInternal
@_spi(Experimental) @testable import DatadogRUM

private final class Subscriber: RUMCommandSubscriber {
    var calls = 0
    func process(command: RUMCommand) { calls += 1 }
}

@MainActor enum InternalFixture {
    static func run(window: UIWindow) -> [String: Any] {
        ["retention": retention()]
    }

    private static func retention() -> [String: Any] {
        let center = NotificationCenter()
        let subscriber = Subscriber()
        let handler = RUMViewsHandler(
            dateProvider: SystemDateProvider(), uiKitPredicate: ViewsPredicate(),
            swiftUIPredicate: nil, swiftUIViewNameExtractor: nil,
            notificationCenter: center, isMultiSceneApplication: true,
            sceneIdentifierProvider: { controller in
                RUMSceneIdentifier(rawValue: controller.restorationIdentifier ?? "unknown")
            }, sceneIdentifierFromNotification: { notification in
                (notification.object as? String).map(RUMSceneIdentifier.init(rawValue:))
            }/* INITIAL_INVENTORY */
        )
        handler.publish(to: subscriber)
        var survivingControllers = 0
        var completedLifetimes = 0
        func cycles(_ range: Range<Int>) {
            for index in range {
                weak var released: UIViewController?
                autoreleasepool {
                    let controller = Screen(name: "Lifetime")
                    released = controller
                    controller.restorationIdentifier = "lifetime-\(index)"
                    center.post(name: UIScene.willConnectNotification, object: controller.restorationIdentifier)
                    handler.notify_viewDidAppear(viewController: controller, animated: false)
                    center.post(name: UIScene.didDisconnectNotification, object: controller.restorationIdentifier)
                }
                if released != nil { survivingControllers += 1 }
                completedLifetimes += 1
            }
        }
        func registryCounts() -> [String: Int] {
            var result: [String: Int] = [:]
            for child in Mirror(reflecting: handler).children {
                let value = Mirror(reflecting: child.value)
                if let label = child.label, [.collection, .dictionary, .set].contains(value.displayStyle) {
                    result[label] = value.children.count
                }
            }
            return result
        }
        let initialRegistry = registryCounts()
        cycles(0..<20)
        let warm = baseline_live_heap_bytes()
        let warmRegistry = registryCounts()
        cycles(20..<120)
        let first = baseline_live_heap_bytes()
        let firstRegistry = registryCounts()
        cycles(120..<220)
        let second = baseline_live_heap_bytes()
        return [
            "warmup_lifetimes": 20, "completed_lifetimes": completedLifetimes,
            "cycles_after_warmup": [100, 100], "heap_bytes": [warm, first, second],
            "surviving_controller_references": survivingControllers,
            "registry_initial": initialRegistry,
            "registry_after_warmup": warmRegistry, "registry_after_100": firstRegistry,
            "registry_after_200": registryCounts(), "published_commands": subscriber.calls,
            "boundary": "posted-disconnect handler lifetime; native host teardown remains EXP-168/171"
        ]
    }
}
