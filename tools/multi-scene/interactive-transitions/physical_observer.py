"""Physical-only fixture derivation; the previously frozen Duo observer is unchanged."""
import hashlib
from observation_variant import replace_once


def render(raw, fingerprint):
    if hashlib.sha256(raw).hexdigest() != fingerprint:
        raise ValueError('physical observer source changed')
    value = raw.decode()
    value = replace_once(value, '    private var failed = false', '''    private var failed = false
    private weak var expectedFrom: UIViewController?
    private weak var expectedTo: UIViewController?
    private var panBegins: [ObjectIdentifier: UInt64] = [:]
    private var probeIndex = 0''')
    start = value.index('        var pending: [UIView] = [window]')
    end = value.index('        guard !witnesses.isEmpty', start)
    value = value[:start] + '''        let graph = controllers()
        let pans: [UIPanGestureRecognizer]
        if phase.hasPrefix("pop.") {
            let navigations = graph.compactMap { $0 as? UINavigationController }.filter {
                $0.viewIfLoaded?.window === window && $0.viewControllers.count >= 2 && $0.presentedViewController == nil
            }
            guard navigations.count == 1, let navigation = navigations.first,
                  let pan = navigation.interactivePopGestureRecognizer as? UIPanGestureRecognizer else {
                fail("missing public interactive pop recognizer"); return
            }
            expectedFrom = navigation.viewControllers.last
            expectedTo = navigation.viewControllers[navigation.viewControllers.count - 2]
            pans = [pan]
        } else {
            let presented = graph.filter {
                $0.presentingViewController != nil && $0.presentedViewController == nil && $0.viewIfLoaded?.window === window
            }
            guard presented.count == 1, let controller = presented.first,
                  let container = controller.presentationController?.containerView, container.window === window else {
                fail("missing public presentation container"); return
            }
            expectedFrom = controller; expectedTo = controller.presentingViewController
            var pending = [container]; var seen = Set<ObjectIdentifier>(); var result = [UIPanGestureRecognizer]()
            while let view = pending.popLast() {
                guard seen.insert(ObjectIdentifier(view)).inserted else { continue }
                guard seen.count <= 4096 else { fail("presentation observation bound exceeded"); return }
                pending.append(contentsOf: view.subviews)
                result.append(contentsOf: (view.gestureRecognizers ?? []).compactMap { $0 as? UIPanGestureRecognizer })
            }
            pans = result
        }
        guard expectedFrom != nil, expectedTo != nil, expectedFrom !== expectedTo else {
            fail("missing public transition endpoints"); return
        }
        for pan in pans {
            guard pan.view?.window === window, pan.state == .possible else {
                fail("foreign or consumed public recognizer"); return
            }
            let witness = PanWitness(pan: pan, window: window, request: requestID, owner: self)
            witnesses.append(witness); pan.addTarget(witness, action: #selector(PanWitness.observe(_:)))
        }
''' + value[end:]
    value = replace_once(value, '"recognizers": witnesses.map(\\.initial), "uptime_ns": DispatchTime.now().uptimeNanoseconds])',
        '''"recognizers": witnesses.map(\\.initial), "uptime_ns": DispatchTime.now().uptimeNanoseconds,
            "expected_from": Self.key(expectedFrom), "expected_to": Self.key(expectedTo)])''')
    start = value.index('    fileprivate func began(')
    end = value.index('        let record = ActiveTransition(', start)
    value = value[:start] + EVENT_RESOLUTION + value[end:]
    value = replace_once(value, '"registration_uptime_ns": started]))', '''"registration_uptime_ns": started,
            "pan_began_uptime_ns": beganAt, "resolution_probe": probeID, "resolution_index": probeIndex]))''')
    value = replace_once(value, '        if recognizer.state == .began { owner?.began(self, recognizer: recognizer) }',
        '        owner?.observed(self, recognizer: recognizer)')
    value = replace_once(value, '        self.requestID = requestID; self.phase = phase',
        '        self.requestID = requestID; self.phase = phase; panBegins.removeAll(); probeIndex = 0')
    value = replace_once(value, '    let from: String; let to: String; let window: String; let scene: String',
        '    let from: String; let to: String; let window: String; let scene: String; let container: String')
    value = replace_once(value, '        self.coordinator = coordinator; self.request = request; self.phase = phase; self.recognizer = recognizer',
        '        self.coordinator = coordinator; self.request = request; self.phase = phase; self.recognizer = recognizer\n        self.container = TransitionObservation.key(coordinator.containerView)')
    value = replace_once(value, '"phase": record.phase, "from": Self.key(context.viewController(forKey: .from)),',
        '"phase": record.phase, "container": Self.key(context.containerView), "from": Self.key(context.viewController(forKey: .from)),')
    value = replace_once(value, '            && record.scene == context.containerView.window?.windowScene?.session.persistentIdentifier',
        '            && record.scene == context.containerView.window?.windowScene?.session.persistentIdentifier\n            && record.container == Self.key(context.containerView)')
    start = value.index('    private func finished(')
    end = value.index('    func close(reason:', start)
    value = value[:start] + TERMINAL_CALLBACK + value[end:]
    value += IDLE_SNAPSHOT
    return value.encode()


EVENT_RESOLUTION = r'''
    fileprivate func observed(_ witness: PanWitness, recognizer: UIPanGestureRecognizer) {
        let state = recognizer.state
        guard state == .began || state == .changed || state == .ended || state == .cancelled else { return }
        guard !failed, witness.request == requestID, HumanObservation.shared.currentRequestID == requestID,
              witness.policiesUnchanged() else { fail("foreign or changed gesture callback"); return }
        if let active = active {
            guard active.recognizer == Self.key(recognizer) else { fail("overlapping native gestures"); return }
            return
        }
        let identity = ObjectIdentifier(recognizer)
        if state == .began {
            guard panBegins[identity] == nil, witness.unchanged() else { fail("duplicate or changed pan begin"); return }
            let beganAt = DispatchTime.now().uptimeNanoseconds
            panBegins[identity] = beganAt
            ObservationStore.shared.append("transition_pan_began", ["request_id": witness.request,
                "phase": phase, "recognizer": witness.initial, "uptime_ns": beganAt,
                "expected_from": Self.key(expectedFrom), "expected_to": Self.key(expectedTo)])
        }
        guard let beganAt = panBegins[identity] else { fail("pan callback without its actual begin"); return }
        guard state == .began || state == .changed else {
            ObservationStore.shared.append("transition_unmatched_pan_end", ["request_id": witness.request,
                "phase": phase, "recognizer": witness.initial, "recognizer_state": state.rawValue,
                "pan_began_uptime_ns": beganAt, "uptime_ns": DispatchTime.now().uptimeNanoseconds])
            return
        }
        guard witness.unchanged() else { fail("recognizer changed before coordinator registration"); return }
        let started = DispatchTime.now().uptimeNanoseconds
        let candidates = controllers().compactMap(\.transitionCoordinator)
        var unique: [ObjectIdentifier: UIViewControllerTransitionCoordinator] = [:]
        for candidate in candidates { unique[ObjectIdentifier(candidate)] = candidate }
        let inventory: [[String: Any]] = unique.values.map { candidate in
            ["coordinator": Self.key(candidate), "from": Self.key(candidate.viewController(forKey: .from)),
             "to": Self.key(candidate.viewController(forKey: .to)), "window": Self.key(candidate.containerView.window),
             "scene": candidate.containerView.window?.windowScene?.session.persistentIdentifier ?? "nil",
             "interactive": candidate.isInteractive, "initially_interactive": candidate.initiallyInteractive,
             "percent_complete": candidate.percentComplete]
        }.sorted { ($0["coordinator"] as? String ?? "") < ($1["coordinator"] as? String ?? "") }
        probeIndex += 1
        guard probeIndex <= 1024 else { fail("gesture observation bound exceeded"); return }
        let probeID = UUID().uuidString.lowercased()
        ObservationStore.shared.append("transition_probe", ["request_id": witness.request, "phase": phase,
            "probe_id": probeID, "index": probeIndex, "recognizer": witness.initial,
            "recognizer_state": state.rawValue, "pan_began_uptime_ns": beganAt,
            "uptime_ns": started, "coordinators": inventory])
        let interactive = unique.values.filter { $0.initiallyInteractive && $0.isInteractive }
        // A native sheet pan can begin before a controller dismissal begins.
        // Only subsequent real recognizer callbacks can supply that boundary.
        // No queued work, timer, delegate replacement or synthetic gesture is used.
        guard !interactive.isEmpty else {
            if unique.values.contains(where: { $0.initiallyInteractive && !$0.isInteractive }) {
                fail("interaction already ended before coordinator registration")
            }
            return
        }
        guard interactive.count == 1, let coordinator = interactive.first,
              coordinator.containerView.window === witness.window,
              coordinator.containerView.window?.windowScene === witness.window?.windowScene,
              let from = coordinator.viewController(forKey: .from), let to = coordinator.viewController(forKey: .to),
              from === expectedFrom, to === expectedTo, from !== to else {
            fail("foreign or ambiguous interactive coordinator"); return
        }
'''


IDLE_SNAPSHOT = '''

// Cleanup observation only. This never removes a recognizer or changes a transition.
@MainActor enum PhysicalInputState {
    static func snapshot() -> [String: Any] {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\\.windows).filter { $0.isKeyWindow && $0.windowLevel == .normal }
        guard windows.count == 1, let window = windows.first, let root = window.rootViewController else {
            return ["valid": false]
        }
        var pending: [UIView] = [window]; var pans = [[String: Any]](); var seen = Set<ObjectIdentifier>()
        while let view = pending.popLast() {
            guard seen.insert(ObjectIdentifier(view)).inserted else { continue }
            guard seen.count <= 4096 else { return ["valid": false] }
            pending.append(contentsOf: view.subviews)
            for pan in (view.gestureRecognizers ?? []).compactMap({ $0 as? UIPanGestureRecognizer }) {
                pans.append(["id": HumanObservation.identity(pan), "state": pan.state.rawValue,
                    "touches": pan.numberOfTouches])
            }
        }
        var controllers = [root]; var known = Set<ObjectIdentifier>(); var coordinators = Set<String>()
        while let controller = controllers.popLast() {
            guard known.insert(ObjectIdentifier(controller)).inserted else { continue }
            guard known.count <= 256 else { return ["valid": false] }
            controllers.append(contentsOf: controller.children)
            if let presented = controller.presentedViewController { controllers.append(presented) }
            if let coordinator = controller.transitionCoordinator {
                coordinators.insert(HumanObservation.identity(coordinator))
            }
        }
        return ["valid": true, "window": HumanObservation.identity(window), "root": HumanObservation.identity(root),
            "scene": window.windowScene?.session.persistentIdentifier ?? "nil", "pans": pans,
            "coordinators": coordinators.sorted(), "uptime_ns": DispatchTime.now().uptimeNanoseconds]
    }
}
'''


TERMINAL_CALLBACK = r'''
    private func finished(_ record: ActiveTransition, context: UIViewControllerTransitionCoordinatorContext) {
        let from = context.viewController(forKey: .from)
        let to = context.viewController(forKey: .to)
        let result = context.isCancelled ? from : to
        let resultWindow = result?.viewIfLoaded?.window
        let containerWindow = context.containerView.window
        var reasons = [String]()
        if failed { reasons.append("failed observer") }
        if active !== record { reasons.append("inactive transition record") }
        if completed.contains(record.id) { reasons.append("duplicate terminal") }
        if record.request != requestID || record.request != HumanObservation.shared.currentRequestID {
            reasons.append("consumed or foreign request")
        }
        if record.changes != 1 { reasons.append("missing or repeated interaction change") }
        if record.from != Self.key(from) || record.to != Self.key(to) { reasons.append("changed transition endpoints") }
        if record.container != Self.key(context.containerView) { reasons.append("changed transition container") }
        if !context.initiallyInteractive || context.isInteractive { reasons.append("nonterminal interaction") }
        if Self.key(resultWindow) != record.window || resultWindow?.windowScene?.session.persistentIdentifier != record.scene
            || resultWindow?.isKeyWindow != true {
            reasons.append("return controller lost owned key window")
        }
        let attached = Self.key(containerWindow) == record.window
            && containerWindow?.windowScene?.session.persistentIdentifier == record.scene
        // Completion runs after the transition. A dismissed presentation container
        // may be detached; the actual returning controller must still own the window.
        let detachedDismissal = record.phase == "dismiss.finish.before" && !context.isCancelled
            && containerWindow == nil && from?.viewIfLoaded?.window == nil
        if !attached && !detachedDismissal { reasons.append("foreign or missing transition container owner") }
        let observed = fields(record, context: context, extra: [
            "active_record": active === record, "completed_record": completed.contains(record.id),
            "observer_failed": failed, "observer_request_id": requestID ?? "nil",
            "interaction_changes": record.changes, "rejections": reasons,
            "from_window": Self.key(from?.viewIfLoaded?.window), "to_window": Self.key(to?.viewIfLoaded?.window),
            "result_window": Self.key(resultWindow), "result_scene": resultWindow?.windowScene?.session.persistentIdentifier ?? "nil",
            "result_is_key": resultWindow?.isKeyWindow ?? false])
        // Retain actual callback values even when a predicate rejects them.
        ObservationStore.shared.append("transition_terminal_observed", observed)
        guard reasons.isEmpty else { fail(reasons.joined(separator: "; ")); return }
        let callback = UUID().uuidString.lowercased()
        var terminal = observed
        terminal["callback_id"] = callback; terminal["controllers"] = controllers().map(describe)
        ObservationStore.shared.append("transition_complete", terminal)
        RUMMonitor.shared().addAction(type: .custom, name: "transition.callback", attributes: [
            "transition_callback": callback, "transition_run": Settings.runID])
        completed.insert(record.id); active = nil; close(reason: "completion")
    }
'''
