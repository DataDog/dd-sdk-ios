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
    private var resolving = Set<ObjectIdentifier>()''')
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
    value = replace_once(value, '    fileprivate func began(_ witness: PanWitness, recognizer: UIPanGestureRecognizer) {', '''    fileprivate func began(_ witness: PanWitness, recognizer: UIPanGestureRecognizer) {
        guard !failed, witness.request == requestID, HumanObservation.shared.currentRequestID == requestID,
              witness.unchanged(), recognizer.state == .began,
              resolving.insert(ObjectIdentifier(recognizer)).inserted else { fail("invalid native gesture begin"); return }
        let beganAt = DispatchTime.now().uptimeNanoseconds
        ObservationStore.shared.append("transition_pan_began", ["request_id": witness.request,
            "phase": phase, "recognizer": witness.initial, "uptime_ns": beganAt,
            "expected_from": Self.key(expectedFrom), "expected_to": Self.key(expectedTo)])
        // A single queued turn lets UIKit's existing targets finish this event.
        // No timer or repeated search supplies a missed transition boundary.
        DispatchQueue.main.async { [weak self, weak witness, weak recognizer] in
            guard let self = self, let witness = witness, let recognizer = recognizer else { return }
            self.resolve(witness, recognizer: recognizer, beganAt: beganAt)
        }
    }
    private func resolve(_ witness: PanWitness, recognizer: UIPanGestureRecognizer, beganAt: UInt64) {''')
    value = replace_once(value, 'witness.unchanged(), recognizer.state == .began else { fail("foreign or changed gesture boundary"); return }',
        '''witness.unchanged(), resolving.remove(ObjectIdentifier(recognizer)) != nil,
              recognizer.state == .began || recognizer.state == .changed else {
            fail("gesture ended or changed before single-turn coordinator resolution"); return
        }''')
    value = replace_once(value, '&& candidate.containerView.window?.windowScene === witness.window?.windowScene {',
        '''&& candidate.containerView.window?.windowScene === witness.window?.windowScene
            && candidate.viewController(forKey: .from) === expectedFrom
            && candidate.viewController(forKey: .to) === expectedTo {''')
    value = replace_once(value, 'fail("no unique interactive coordinator at gesture began"); return',
        'fail("no unique bound coordinator in the single resolution turn"); return')
    value = replace_once(value, '"registration_uptime_ns": started]))', '''"registration_uptime_ns": started,
            "pan_began_uptime_ns": beganAt, "resolution_turns": 1]))''')
    value += IDLE_SNAPSHOT
    return value.encode()


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
