import UIKit
@_spi(Internal) import DatadogInternal
@_spi(Experimental) @testable import DatadogRUM

private struct EmptyHeatmapRegistry: HeatmapIdentifierRegistry {
    func setHeatmapIdentifiers(_ values: [ObjectIdentifier: HeatmapIdentifier]) {}
    func heatmapIdentifier(for identifier: ObjectIdentifier) -> HeatmapIdentifier? { nil }
}
private final class FixtureTouch: UITouch {
    let source: UIView
    init(source: UIView) { self.source = source; super.init() }
    override var view: UIView? { source }
    override var phase: UITouch.Phase { get { .moved } set {} }
}
private final class FixtureEvent: UIEvent {
    let touches: Set<UITouch>
    init(source: UIView) { touches = [FixtureTouch(source: source)]; super.init() }
    override var allTouches: Set<UITouch>? { touches }
}
private final class Subscriber: RUMCommandSubscriber {
    var calls = 0
    func process(command: RUMCommand) { calls += 1 }
}
private final class LegacyMonitor: NOPMonitor {
    var calls: [String] = []
    override func addAction(type: RUMActionType, name: String, attributes: [AttributeKey: AttributeValue]) { calls.append("add:" + name) }
    override func startAction(type: RUMActionType, name: String, attributes: [AttributeKey: AttributeValue]) { calls.append("start:" + name) }
    override func stopAction(type: RUMActionType, name: String?, attributes: [AttributeKey: AttributeValue]) { calls.append("stop:" + (name ?? "nil")) }
}

@MainActor enum InternalFixture {
    static func run(window: UIWindow) -> [String: Any] {
        let source = UIButton(); window.addSubview(source)
        let event = FixtureEvent(source: source)
        let factory = UITouchCommandFactory(dateProvider: SystemDateProvider(), heatmapIdentifierRegistry: EmptyHeatmapRegistry(), uiKitPredicate: DefaultUIKitRUMActionsPredicate(), swiftUIPredicate: nil, swiftUIDetector: nil)
        let ordinary = RUMActionsHandler(dateProvider: SystemDateProvider(), eventCommandsFactory: factory)
        let monitorSubscriber = RUMMonitor.shared() as? RUMCommandSubscriber
        if let monitorSubscriber { ordinary.publish(to: monitorSubscriber) }
        var dispatches = 0
        let dispatch = { dispatches += 1; return true }
        let ordinaryWork: () -> Void = {
            #if CANDIDATE
            _ = ordinary.intercept_sendEvent(application: .shared, event: event, dispatch: dispatch)
            #else
            ordinary.notify_sendEvent(application: .shared, event: event)
            _ = dispatch()
            #endif
        }
        var result: [String: Any] = ["filtered_touch_ns": Fixture.samples(ordinaryWork), "iterations_per_batch": 20_000, "filtered_touch_event_ns": Fixture.eventSamples(ordinaryWork)]
        #if CANDIDATE
        let enabled = RUMActionsHandler(dateProvider: SystemDateProvider(), eventCommandsFactory: factory, isUIEventContextHandoffEnabled: true)
        if let monitorSubscriber { enabled.publish(to: monitorSubscriber) }
        var liveContext = false
        _ = enabled.intercept_sendEvent(application: .shared, event: event) {
            liveContext = RUMContextHandoff.current?.rumContext?.viewID != nil
            return true
        }
        result["handoff_live_context"] = liveContext
        result["handoff_ns"] = Fixture.samples { _ = enabled.intercept_sendEvent(application: .shared, event: event, dispatch: dispatch) }
        result["handoff_event_ns"] = Fixture.eventSamples { _ = enabled.intercept_sendEvent(application: .shared, event: event, dispatch: dispatch) }
        var errors = 0
        var nestedCalls = 0
        let expectedScene = window.windowScene.map { RUMSceneIdentifier(rawValue: $0.session.persistentIdentifier) }
        for _ in 0..<10_000 {
            _ = enabled.intercept_sendEvent(application: .shared, event: event) {
                nestedCalls += 1
                if RUMUIEventNetworkContext.currentSceneIdentifier != expectedScene { errors += 1 }
                RUMContextHandoff.withValue(rumContext: nil, sceneIdentifier: "B") {
                    if RUMContextHandoff.current?.sceneIdentifier != "B" { errors += 1 }
                    _ = enabled.intercept_sendEvent(application: .shared, event: event) {
                        nestedCalls += 1
                        if RUMUIEventNetworkContext.currentSceneIdentifier != expectedScene { errors += 1 }
                        return false // Early return must still restore B.
                    }
                    if RUMContextHandoff.current?.sceneIdentifier != "B" { errors += 1 }
                }
                if RUMUIEventNetworkContext.currentSceneIdentifier != expectedScene { errors += 1 }
                return true
            }
            if RUMContextHandoff.current != nil { errors += 1 }
        }
        result["reentrancy"] = ["iterations": 10_000, "original_dispatches": nestedCalls, "expected_dispatches": 20_000, "errors": errors]
        #endif
        let custom = LegacyMonitor()
        let erased: RUMMonitorProtocol = custom
        erased.addAction(type: .custom, name: "one")
        erased.startAction(type: .custom, name: "two")
        erased.stopAction(type: .custom, name: "three")
        var expected = ["add:one", "start:two", "stop:three"]
        var nopCompletions = 0
        let nop: RUMMonitorProtocol = NOPMonitor()
        nop.currentSessionID { value in if value == nil { nopCompletions += 1 } }
        #if CANDIDATE
        if #available(iOS 27.0, *), let scene = window.windowScene {
            erased.addAction(type: .custom, name: "target-one", view: .current(in: scene))
            erased.startAction(type: .custom, name: "target-two", view: .current(in: scene))
            erased.stopAction(type: .custom, name: "target-three", view: .current(in: scene))
            nop.startAction(type: .custom, name: "noop", view: .current(in: scene))
            nop.stopAction(type: .custom, name: "noop", view: .current(in: scene))
            expected += ["add:target-one", "start:target-two", "stop:target-three"]
        }
        #endif
        result["compatibility"] = ["custom_calls": custom.calls, "expected_calls": expected, "nop_nil_callbacks": nopCompletions]
        // Allocation instrumentation is deliberately installed after every timing batch.
        let installed = baseline_allocation_counter_install() == 1
        let calibrated = installed && baseline_allocation_calibrate() == 1
        if calibrated {
            for _ in 0..<20_000 { ordinaryWork() }
            baseline_allocation_begin()
            for _ in 0..<20_000 { ordinaryWork() }
            baseline_allocation_end()
            result["allocations"] = ["count": baseline_allocation_count(), "requested_bytes": baseline_allocation_bytes(), "events": 20_000, "calibrated": true, "method": "malloc_logger; successful heap allocations on workload thread; realloc counted at requested size"]
            #if CANDIDATE
            for _ in 0..<20_000 { _ = enabled.intercept_sendEvent(application: .shared, event: event, dispatch: dispatch) }
            baseline_allocation_begin()
            for _ in 0..<20_000 { _ = enabled.intercept_sendEvent(application: .shared, event: event, dispatch: dispatch) }
            baseline_allocation_end()
            result["handoff_allocations"] = ["count": baseline_allocation_count(), "requested_bytes": baseline_allocation_bytes(), "events": 20_000, "calibrated": true]
            #else
            result["handoff_allocations"] = result["allocations"]
            #endif
        } else {
            result["allocations"] = ["calibrated": false, "installed": installed, "observed_calibration_count": baseline_allocation_count(), "observed_calibration_bytes": baseline_allocation_bytes()]
        }
        #if CANDIDATE
        result["retention"] = retention()
        #endif
        source.removeFromSuperview()
        result["ordinary_dispatches"] = dispatches
        return result
    }
    #if CANDIDATE
    private static func retention() -> [String: Any] {
        let center = NotificationCenter()
        let subscriber = Subscriber()
        let handler = RUMViewsHandler(dateProvider: SystemDateProvider(), uiKitPredicate: ViewsPredicate(), swiftUIPredicate: nil, swiftUIViewNameExtractor: nil, notificationCenter: center, isMultiSceneApplication: true, sceneIdentifierProvider: { controller in
            RUMSceneIdentifier(rawValue: controller.restorationIdentifier ?? "unknown")
        }, sceneIdentifierFromNotification: { notification in
            (notification.object as? String).map(RUMSceneIdentifier.init(rawValue:))
        })
        handler.publish(to: subscriber)
        var survivingControllers = 0
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
            }
        }
        func registryCounts() -> [String: Int] {
            let keys = ["stacks", "sceneActivityByIdentifier", "disconnectedSceneIdentifiers", "uiKitSplitViewContexts", "pendingUIKitSplitViewRemovals"]
            var result: [String: Int] = [:]
            for child in Mirror(reflecting: handler).children {
                if let label = child.label, keys.contains(label) { result[label] = Mirror(reflecting: child.value).children.count }
            }
            return result
        }
        cycles(0..<20)
        let warm = baseline_live_heap_bytes()
        let warmRegistry = registryCounts()
        cycles(20..<120)
        let first = baseline_live_heap_bytes()
        let firstRegistry = registryCounts()
        cycles(120..<220)
        let second = baseline_live_heap_bytes()
        return ["cycles_after_warmup": [100, 100], "heap_bytes": [warm, first, second], "surviving_controller_references": survivingControllers, "registry_after_warmup": warmRegistry, "registry_after_100": firstRegistry, "registry_after_200": registryCounts(), "boundary": "focused posted-disconnect handler lifetime; not genuine OS scene or SwiftUI host teardown"]
    }
    #endif
}
