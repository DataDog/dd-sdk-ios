import UIKit
@_spi(Internal) import DatadogInternal
@_spi(Experimental) @testable import DatadogRUM

private struct FocusedHeatmapRegistry: HeatmapIdentifierRegistry {
    func setHeatmapIdentifiers(_ values: [ObjectIdentifier: HeatmapIdentifier]) {}
    func heatmapIdentifier(for identifier: ObjectIdentifier) -> HeatmapIdentifier? { nil }
}
private final class FocusedTouch: UITouch {
    let source: UIView
    init(source: UIView) { self.source = source; super.init() }
    override var view: UIView? { source }
    override var phase: UITouch.Phase { get { .moved } set {} }
}
private final class FocusedEvent: UIEvent {
    let touches: Set<UITouch>
    init(source: UIView) { touches = [FocusedTouch(source: source)]; super.init() }
    override var allTouches: Set<UITouch>? { touches }
}
private enum FocusedError: Error { case expected }

@MainActor enum FocusedChecks {
    static func run(window: UIWindow) -> [String: Any] {
        let source = UIButton(); window.addSubview(source)
        defer { source.removeFromSuperview() }
        let event = FocusedEvent(source: source)
        let factory = UITouchCommandFactory(dateProvider: SystemDateProvider(), heatmapIdentifierRegistry: FocusedHeatmapRegistry(), uiKitPredicate: DefaultUIKitRUMActionsPredicate(), swiftUIPredicate: nil, swiftUIDetector: nil)
        let handler = RUMActionsHandler(dateProvider: SystemDateProvider(), eventCommandsFactory: factory, isUIEventContextHandoffEnabled: true)
        if let subscriber = RUMMonitor.shared() as? RUMCommandSubscriber { handler.publish(to: subscriber) }
        let expectedScene = window.windowScene?.session.persistentIdentifier
        var expected: RUMCoreContext?
        _ = handler.intercept_sendEvent(application: .shared, event: event) {
            expected = RUMContextHandoff.current?.rumContext
            return true
        }
        let live = expected?.applicationID == "00000000-0000-0000-0000-000000000160"
            && expected?.sessionID.isEmpty == false && expected?.viewID?.isEmpty == false
            && expected?.viewName == "Home" && expectedScene != nil
        var errors = 0
        var originalCalls = 0
        var checks = 0
        var caughtThrows = 0
        func checkA() {
            checks += 1
            guard let current = RUMContextHandoff.current,
                  current.rumContext == expected, current.rumContext != nil,
                  current.sceneIdentifier == expectedScene,
                  !current.hasPendingUserAction, current.excludedUserActionID == nil else {
                errors += 1; return
            }
        }
        func checkB() {
            checks += 1
            guard let current = RUMContextHandoff.current,
                  current.rumContext == nil, current.sceneIdentifier == "B",
                  current.hasPendingUserAction, current.excludedUserActionID == "B-action" else {
                errors += 1; return
            }
        }
        for _ in 0..<10_000 {
            _ = handler.intercept_sendEvent(application: .shared, event: event) {
                originalCalls += 1
                checkA()
                RUMContextHandoff.withValue(rumContext: nil, sceneIdentifier: "B", hasPendingUserAction: true, excludedUserActionID: "B-action") {
                    checkB()
                    let returned = handler.intercept_sendEvent(application: .shared, event: event) {
                        originalCalls += 1
                        checkA()
                        return false
                    }
                    checks += 1
                    if returned { errors += 1 }
                    checkB()
                }
                checkA()
                do {
                    try RUMContextHandoff.withValue(rumContext: nil, sceneIdentifier: "B", hasPendingUserAction: true, excludedUserActionID: "B-action") {
                        checkB()
                        throw FocusedError.expected
                    }
                } catch { caughtThrows += 1 }
                checkA()
                return true
            }
            checks += 1
            if RUMContextHandoff.current != nil { errors += 1 }
        }
        return ["oracle": "full-RUMCoreContext-Equatable-and-handoff-fields-v1", "iterations": 10_000,
                "live_home_context": live, "original_dispatches": originalCalls,
                "expected_dispatches": 20_000, "boundary_checks": checks,
                "caught_throws": caughtThrows, "errors": errors,
                "timing_claim": false]
    }
}
