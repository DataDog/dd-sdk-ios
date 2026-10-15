import Foundation
import UIKit
import DatadogRUM

@MainActor enum TransitionModel {
    static private(set) var values: [String: Any] = ["path": [String](), "selection": NSNull(), "selection_occurrence": NSNull(), "sheet": false]
    static func path(_ path: [String]) { values["path"] = path; record() }
    static func select(_ selection: String?, occurrence: String?) {
        values["selection"] = selection as Any? ?? NSNull()
        values["selection_occurrence"] = occurrence as Any? ?? NSNull(); record()
    }
    static func sheet(_ presented: Bool) { values["sheet"] = presented; record() }
    private static func record() {
        ObservationStore.shared.append("native_model", ["model": values,
            "request_id": HumanObservation.shared.currentRequestID ?? "nil"])
    }
}

// Adds only an observation target to existing recognizers. No delegate, view,
// transition or recognizer configuration is replaced.
@MainActor final class TransitionObservation: NSObject {
    static let shared = TransitionObservation()
    private var witnesses: [PanWitness] = []
    private var active: ActiveTransition?
    private var requestID: String?
    private var phase = ""
    private var completed = Set<String>()
    private var failed = false
    private let interactivePhases = Set(["pop.finish.before", "pop.cancel.before", "dismiss.finish.before", "dismiss.cancel.before"])
    static func key(_ object: AnyObject?) -> String { HumanObservation.identity(object) }

    func prepare(requestID: String, phase: String) {
        guard active == nil else { fail("snapshot requested during an active transition"); return }
        close(reason: "next-readiness")
        self.requestID = requestID; self.phase = phase
        guard interactivePhases.contains(phase), !failed else { return }
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }.flatMap(\.windows)
            .filter { $0.isKeyWindow && !$0.isHidden && $0.windowLevel == .normal }
        guard windows.count == 1, let window = windows.first else { fail("missing unique owned key window"); return }
        var pending: [UIView] = [window]; var seen = Set<ObjectIdentifier>(); var visited = 0
        while let view = pending.popLast() {
            visited += 1; pending.append(contentsOf: view.subviews)
            guard visited <= 4096 else { fail("view observation bound exceeded"); return }
            for recognizer in view.gestureRecognizers ?? [] {
                guard let pan = recognizer as? UIPanGestureRecognizer, seen.insert(ObjectIdentifier(pan)).inserted else { continue }
                guard pan.state == .possible else { fail("recognizer already consumed at readiness"); return }
                let witness = PanWitness(pan: pan, window: window, request: requestID, owner: self)
                witnesses.append(witness); pan.addTarget(witness, action: #selector(PanWitness.observe(_:)))
            }
        }
        guard !witnesses.isEmpty else { fail("no public pan recognizer at interactive readiness"); return }
        ObservationStore.shared.append("transition_armed", ["request_id": requestID, "phase": phase,
            "recognizers": witnesses.map(\.initial), "uptime_ns": DispatchTime.now().uptimeNanoseconds])
    }

    func snapshot() -> [String: Any] {
        ["model": TransitionModel.values, "controllers": controllers().map(describe),
         "armed": witnesses.map(\.initial), "active_transition": active?.id ?? "nil"]
    }
    private func controllers() -> [UIViewController] {
        let roots = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).filter(\.isKeyWindow).compactMap(\.rootViewController)
        var pending = roots; var seen = Set<ObjectIdentifier>(); var result = [UIViewController]()
        while let controller = pending.popLast() {
            guard seen.insert(ObjectIdentifier(controller)).inserted else { continue }
            guard result.count < 256 else { fail("controller observation bound exceeded"); break }
            result.append(controller); pending.append(contentsOf: controller.children)
            if let presented = controller.presentedViewController { pending.append(presented) }
        }
        return result
    }
    private func describe(_ controller: UIViewController) -> [String: Any] {
        var value: [String: Any] = ["id": Self.key(controller), "parent": Self.key(controller.parent),
            "presented": Self.key(controller.presentedViewController), "presenting": Self.key(controller.presentingViewController),
            "window": Self.key(controller.viewIfLoaded?.window), "view": Self.key(controller.viewIfLoaded),
            "accessibility_id": controller.viewIfLoaded?.accessibilityIdentifier ?? "nil",
            "bundle": Bundle(for: type(of: controller)).bundleURL.path,
            "children": controller.children.map { Self.key($0) }]
        if let navigation = controller as? UINavigationController {
            value["navigation_stack"] = navigation.viewControllers.map { Self.key($0) }
            value["top"] = Self.key(navigation.topViewController); value["visible"] = Self.key(navigation.visibleViewController)
        }
        if let split = controller as? UISplitViewController {
            value["split_collapsed"] = split.isCollapsed; value["split_display_mode"] = split.displayMode.rawValue
        }
        return value
    }
    fileprivate func began(_ witness: PanWitness, recognizer: UIPanGestureRecognizer) {
        let started = DispatchTime.now().uptimeNanoseconds
        guard !failed, witness.request == requestID, HumanObservation.shared.currentRequestID == requestID,
              witness.unchanged(), recognizer.state == .began else { fail("foreign or changed gesture boundary"); return }
        let candidates = controllers().compactMap(\.transitionCoordinator)
        var unique: [ObjectIdentifier: UIViewControllerTransitionCoordinator] = [:]
        for candidate in candidates where candidate.initiallyInteractive && candidate.isInteractive
            && candidate.containerView.window === witness.window
            && candidate.containerView.window?.windowScene === witness.window?.windowScene {
            unique[ObjectIdentifier(candidate)] = candidate
        }
        guard unique.count == 1, let coordinator = unique.values.first,
              let from = coordinator.viewController(forKey: .from), let to = coordinator.viewController(forKey: .to),
              from !== to, coordinator.containerView.window === witness.window else {
            fail("no unique interactive coordinator at gesture began"); return
        }
        if let active = active {
            guard active.coordinator === coordinator else { fail("overlapping native transitions"); return }
            return
        }
        let record = ActiveTransition(coordinator: coordinator, request: witness.request,
            phase: phase, recognizer: Self.key(recognizer), from: Self.key(from), to: Self.key(to),
            window: Self.key(witness.window), scene: witness.window?.windowScene?.session.persistentIdentifier ?? "nil")
        active = record
        ObservationStore.shared.append("transition_begin", fields(record, context: coordinator, extra: [
            "recognizer": witness.initial, "recognizer_state": recognizer.state.rawValue,
            "registration_uptime_ns": started]))
        coordinator.notifyWhenInteractionChanges { [weak self, weak record] context in
            guard let self = self else { return }
            guard let record = record else { self.fail("interaction callback after observer closure"); return }
            self.changed(record, context: context)
        }
        // A completion-only registration is public UIKit API. Its Boolean result
        // is retained, not used to synthesize a completion or gesture result.
        let queued = coordinator.animate(alongsideTransition: nil) { [weak self, weak record] context in
            guard let self = self else { return }
            guard let record = record else { self.fail("completion callback after observer closure"); return }
            self.finished(record, context: context)
        }
        ObservationStore.shared.append("transition_registered", fields(record, context: coordinator,
            extra: ["animations_queued": queued, "duration_ns": DispatchTime.now().uptimeNanoseconds - started]))
    }
    private func fields(_ record: ActiveTransition, context: UIViewControllerTransitionCoordinatorContext,
                        extra: [String: Any] = [:]) -> [String: Any] {
        var result: [String: Any] = ["transition_id": record.id, "coordinator": Self.key(record.coordinator),
            "request_id": record.request, "current_request_id": HumanObservation.shared.currentRequestID ?? "nil",
            "phase": record.phase, "from": Self.key(context.viewController(forKey: .from)),
            "to": Self.key(context.viewController(forKey: .to)), "window": Self.key(context.containerView.window),
            "scene": context.containerView.window?.windowScene?.session.persistentIdentifier ?? "nil",
            "initially_interactive": context.initiallyInteractive, "interactive": context.isInteractive,
            "cancelled": context.isCancelled, "percent_complete": context.percentComplete,
            "uptime_ns": DispatchTime.now().uptimeNanoseconds, "model": TransitionModel.values]
        result.merge(extra) { _, new in new }; return result
    }
    private func valid(_ record: ActiveTransition, context: UIViewControllerTransitionCoordinatorContext) -> Bool {
        active === record && !completed.contains(record.id) && record.request == HumanObservation.shared.currentRequestID
            && record.from == Self.key(context.viewController(forKey: .from))
            && record.to == Self.key(context.viewController(forKey: .to))
            && record.window == Self.key(context.containerView.window)
            && record.scene == context.containerView.window?.windowScene?.session.persistentIdentifier
    }
    private func changed(_ record: ActiveTransition, context: UIViewControllerTransitionCoordinatorContext) {
        guard valid(record, context: context) else { fail("late or foreign interaction change"); return }
        record.changes += 1
        ObservationStore.shared.append("transition_change", fields(record, context: context))
    }
    private func finished(_ record: ActiveTransition, context: UIViewControllerTransitionCoordinatorContext) {
        guard valid(record, context: context), record.changes > 0 else { fail("missing interaction change or duplicate terminal"); return }
        let callback = UUID().uuidString.lowercased()
        ObservationStore.shared.append("transition_complete", fields(record, context: context,
            extra: ["callback_id": callback, "controllers": controllers().map(describe)]))
        RUMMonitor.shared().addAction(type: .custom, name: "transition.callback", attributes: [
            "transition_callback": callback, "transition_run": Settings.runID])
        completed.insert(record.id); active = nil; close(reason: "completion")
    }
    func close(reason: String) {
        guard active == nil else { fail("observer closed before transition terminal"); return }
        guard !witnesses.isEmpty else { return }
        let unchanged = witnesses.allSatisfy { $0.policiesUnchanged() }
        let terminal = witnesses.map { $0.current() }
        witnesses.forEach { $0.close() }
        ObservationStore.shared.append("transition_closed", ["request_id": requestID ?? "nil",
            "phase": phase, "reason": reason, "configuration_unchanged": unchanged,
            "recognizers": witnesses.map(\.initial), "terminal_recognizers": terminal])
        witnesses.removeAll()
        if !unchanged { fail("recognizer configuration changed during observation") }
    }
    fileprivate func fail(_ reason: String) {
        witnesses.forEach { $0.close() }; witnesses.removeAll(); active = nil
        ObservationStore.shared.append("transition_observer_rejected", ["reason": reason, "request_id": requestID ?? "nil"])
        guard !failed else { return }; failed = true
        ObservationStore.shared.append("human_failure", ["reason": reason,
            "request_id": requestID ?? "nil", "phase": phase])
    }
}

@MainActor private final class ActiveTransition {
    let id = UUID().uuidString.lowercased()
    let coordinator: UIViewControllerTransitionCoordinator
    let request: String; let phase: String; let recognizer: String
    let from: String; let to: String; let window: String; let scene: String
    var changes = 0
    init(coordinator: UIViewControllerTransitionCoordinator, request: String, phase: String,
         recognizer: String, from: String, to: String, window: String, scene: String) {
        self.coordinator = coordinator; self.request = request; self.phase = phase; self.recognizer = recognizer
        self.from = from; self.to = to; self.window = window; self.scene = scene
    }
}
@MainActor private final class PanWitness: NSObject {
    weak var pan: UIPanGestureRecognizer?
    weak var window: UIWindow?
    weak var owner: TransitionObservation?
    let request: String
    let initial: [String: Any]
    private var closed = false
    init(pan: UIPanGestureRecognizer, window: UIWindow, request: String, owner: TransitionObservation) {
        self.pan = pan; self.window = window; self.request = request; self.owner = owner
        initial = Self.configuration(pan)
    }
    static func configuration(_ pan: UIPanGestureRecognizer) -> [String: Any] {
        var value: [String: Any] = ["id": TransitionObservation.key(pan), "view": TransitionObservation.key(pan.view),
            "window": TransitionObservation.key(pan.view?.window), "delegate": TransitionObservation.key(pan.delegate),
            "enabled": pan.isEnabled, "cancels_touches": pan.cancelsTouchesInView,
            "delays_began": pan.delaysTouchesBegan, "delays_ended": pan.delaysTouchesEnded,
            "exclusive_touch": pan.requiresExclusiveTouchType, "touch_types": pan.allowedTouchTypes,
            "press_types": pan.allowedPressTypes, "minimum_touches": pan.minimumNumberOfTouches,
            "maximum_touches": pan.maximumNumberOfTouches]
        if let edge = pan as? UIScreenEdgePanGestureRecognizer { value["edges"] = edge.edges.rawValue }
        return value
    }
    func current() -> [String: Any] { pan.map(Self.configuration) ?? ["released": true] }
    func policiesUnchanged() -> Bool {
        guard let pan = pan else { return false }
        var before = initial; var after = Self.configuration(pan)
        // UIKit legitimately changes attachment and enablement when a pop or
        // dismissal finishes. Preserve those observations separately; this
        // observer never assigns either property.
        for key in ["enabled", "window"] { before.removeValue(forKey: key); after.removeValue(forKey: key) }
        return NSDictionary(dictionary: before).isEqual(to: after)
    }
    func unchanged() -> Bool {
        guard let pan = pan else { return false }
        return NSDictionary(dictionary: initial).isEqual(to: Self.configuration(pan))
    }
    @objc func observe(_ recognizer: UIPanGestureRecognizer) {
        guard !closed, recognizer === pan else { owner?.fail("recognizer callback after observation closure"); return }
        if recognizer.state == .began { owner?.began(self, recognizer: recognizer) }
    }
    func close() {
        guard !closed else { return }; closed = true
        pan?.removeTarget(self, action: #selector(observe(_:)))
    }
}
