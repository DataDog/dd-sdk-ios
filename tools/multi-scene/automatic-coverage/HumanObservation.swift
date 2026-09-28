import CryptoKit
import Foundation
import UIKit
import SwiftUI

// Fixture-only observation. This object neither delivers input nor controls navigation.
@MainActor final class HumanObservation {
    static let shared = HumanObservation()
    private let requests = HumanSnapshotRequests()
    private var failureRecorded = false
    private var firstAppearance: String?
    private weak var ownedWindow: UIWindow?
    private weak var ownedRoot: UIViewController?
    private var boundWindowID: String?
    private var boundRootID: String?
    private var boundSceneID: String?
    private let scrollWitnesses = NSMapTable<UIScrollView, ScrollWitness>(keyOptions: .weakMemory, valueOptions: .strongMemory)
    private(set) var currentRequestID: String?
    private var currentPhase: String?
    private var currentRequestHash: String?
    private var backgroundObserver: NSObjectProtocol?

    static func identity(_ object: AnyObject?) -> String {
        guard let object = object else { return "nil" }
        return String(describing: ObjectIdentifier(object))
    }
    static func rect(_ value: CGRect) -> [CGFloat] { [value.origin.x, value.origin.y, value.width, value.height] }
    static func point(_ value: CGPoint) -> [CGFloat] { [value.x, value.y] }
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    func appeared(_ screen: String) {
        let started = DispatchTime.now().uptimeNanoseconds
        if firstAppearance == nil { firstAppearance = screen }
        bindWindowIfReady()
        let event = ObservationStore.shared.append("human_appearance", ["screen": screen,
            "request_id": currentRequestID ?? "nil", "uptime_ns": started])
        cost("appearance", started: started, event: event)
    }
    private func bindWindowIfReady() {
        guard boundWindowID == nil, firstAppearance != nil else { return }
        var candidates: [UIWindow] = []
        for value in UIApplication.shared.connectedScenes {
            guard let scene = value as? UIWindowScene, scene.activationState == .foregroundActive else { continue }
            for window in scene.windows {
                guard window.isKeyWindow, !window.isHidden, window.alpha > 0,
                      window.windowLevel == UIWindow.Level.normal,
                      let root = window.rootViewController, root.viewIfLoaded?.window === window else { continue }
                candidates.append(window)
            }
        }
        guard candidates.count == 1, let window = candidates.first, let root = window.rootViewController else { return }
        ownedWindow = window; ownedRoot = root
        boundWindowID = Self.identity(window); boundRootID = Self.identity(root)
        boundSceneID = window.windowScene?.session.persistentIdentifier
        ObservationStore.shared.append("human_window_binding", ["window": boundWindowID ?? "nil",
            "root": boundRootID ?? "nil", "scene": boundSceneID ?? "nil", "first_native_appearance": firstAppearance ?? "nil",
            "basis": "single fixture scene and sole normal key content window after native appearance"])
    }
    private func views(_ root: UIView) -> [UIView] {
        var result = [UIView](); var pending = [root]
        while let view = pending.popLast() {
            result.append(view); pending.append(contentsOf: view.subviews)
        }
        return result
    }
    private func observeScrolls() {
        guard let window = ownedWindow else { return }
        for scroll in views(window).compactMap({ $0 as? UIScrollView }) where scrollWitnesses.object(forKey: scroll) == nil {
            let witness = ScrollWitness(scroll: scroll)
            scrollWitnesses.setObject(witness, forKey: scroll)
            scroll.panGestureRecognizer.addTarget(witness, action: #selector(ScrollWitness.observe(_:)))
        }
    }
    func start() {
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.recordHomeIdle() }
        }
        requests.start { [weak self] requestID, phase, fingerprint, error in
            Task { @MainActor in
                guard let self = self else { return }
                if let error = error { self.fail(error, fingerprint: fingerprint); return }
                self.snapshot(requestID: requestID, phase: phase, fingerprint: fingerprint)
            }
        }
    }
    private func snapshot(requestID: String, phase: String, fingerprint: String) {
        let started = DispatchTime.now().uptimeNanoseconds
        bindWindowIfReady(); observeScrolls()
        guard boundWindowID != nil else {
            fail("native content window was not bound before snapshot", fingerprint: fingerprint); return
        }
        currentRequestID = requestID
        currentPhase = phase; currentRequestHash = fingerprint
        var payload: [String: Any] = ["request_id": requestID, "request_sha256": fingerprint,
            "phase": phase, "uptime_ns": DispatchTime.now().uptimeNanoseconds, "topology": topology(includeControls: true)]
        if phase == "cleanup.idle" { payload["input_state"] = cleanupInputState() }
        let event = ObservationStore.shared.append("human_snapshot", payload)
        cost("snapshot", started: started, event: event)
        ObservationStore.shared.checkpoint(requestID)
    }
    fileprivate func cost(_ operation: String, started: UInt64, event: Int) {
        let elapsed = DispatchTime.now().uptimeNanoseconds - started
        ObservationStore.shared.append("human_observer_cost", ["operation": operation, "event_sequence": event,
            "request_id": currentRequestID ?? "nil", "duration_ns": elapsed])
    }
    private func fail(_ message: String, fingerprint: String) {
        guard !failureRecorded else { return }; failureRecorded = true
        ObservationStore.shared.append("human_failure", ["reason": message, "request_sha256": fingerprint])
    }

    private func cleanupInputState() -> [String: Any] {
        var result: [String: Any] = ["valid": false, "window": boundWindowID ?? "nil",
            "root": boundRootID ?? "nil", "scene": boundSceneID ?? "nil"]
        guard let window = ownedWindow, let root = ownedRoot,
              window.rootViewController === root, root.viewIfLoaded?.window === window,
              window.windowScene?.session.persistentIdentifier == boundSceneID else { return result }
        var pending = [UIView](arrayLiteral: window), seen = Set<ObjectIdentifier>()
        var gestures = [[String: Any]](), controls = [[String: Any]](), scrolls = [[String: Any]]()
        var gestureIDs = Set<ObjectIdentifier>()
        while let view = pending.popLast() {
            guard seen.insert(ObjectIdentifier(view)).inserted else { continue }
            guard seen.count <= 4096 else { return result }
            pending.append(contentsOf: view.subviews)
            for gesture in view.gestureRecognizers ?? [] where gestureIDs.insert(ObjectIdentifier(gesture)).inserted {
                gestures.append(["id": Self.identity(gesture), "state": gesture.state.rawValue, "touches": gesture.numberOfTouches])
            }
            if let control = view as? UIControl { controls.append(["id": Self.identity(control), "tracking": control.isTracking]) }
            if let scroll = view as? UIScrollView {
                scrolls.append(["id": Self.identity(scroll), "tracking": scroll.isTracking,
                    "dragging": scroll.isDragging, "decelerating": scroll.isDecelerating])
            }
        }
        var controllers = [root], visited = Set<ObjectIdentifier>(), coordinators = [String]()
        while let controller = controllers.popLast() {
            guard visited.insert(ObjectIdentifier(controller)).inserted else { continue }
            guard visited.count <= 256 else { return result }
            controllers.append(contentsOf: controller.children)
            if let presented = controller.presentedViewController { controllers.append(presented) }
            if let coordinator = controller.transitionCoordinator { coordinators.append(Self.identity(coordinator)) }
        }
        result.merge(["valid": true, "view_count": seen.count, "controller_count": visited.count,
            "gestures": gestures, "controls": controls, "scrolls": scrolls, "coordinators": coordinators]) { _, value in value }
        return result
    }
    private func recordHomeIdle() {
        guard currentPhase == "background.before", let request = currentRequestID,
              let fingerprint = currentRequestHash else { return }
        let payload: [String: Any] = ["schema_version": 1, "run_id": Settings.runID,
            "request_id": request, "request_sha256": fingerprint,
            "pid": ProcessInfo.processInfo.processIdentifier,
            "notification": "UIApplication.didEnterBackgroundNotification",
            "topology": topology(includeControls: false), "input_state": cleanupInputState()]
        guard let bytes = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("home-input-idle-" + request + ".json")
        DispatchQueue.global(qos: .utility).async { try? bytes.write(to: url, options: .atomic) }
    }
    func input(_ target: String) {
        let started = DispatchTime.now().uptimeNanoseconds
        guard let requestID = currentRequestID else { return }
        let event = ObservationStore.shared.append("human_callback", ["request_id": requestID, "target": target,
            "uptime_ns": DispatchTime.now().uptimeNanoseconds, "topology": topology(includeControls: false)])
        cost("callback", started: started, event: event)
    }
    private func accessibility(_ window: UIWindow) -> [[String: Any]] {
        var pending: [NSObject] = [window]; var seen = Set<ObjectIdentifier>(); var result = [[String: Any]]()
        while let object = pending.popLast() {
            guard seen.insert(ObjectIdentifier(object)).inserted else { continue }
            guard seen.count <= 4096 else {
                return [["capture_error": "public accessibility inventory exceeded fixture bound"]]
            }
            if let view = object as? UIView {
                pending.append(contentsOf: view.subviews)
                if let elements = view.accessibilityElements { pending.append(contentsOf: elements.compactMap { $0 as? NSObject }) }
                let count = view.accessibilityElementCount()
                if count != NSNotFound && count > 0 && count <= 4096 {
                    for index in 0..<count {
                        if let element = view.accessibilityElement(at: index) as? NSObject { pending.append(element) }
                    }
                } else if count != NSNotFound && count > 4096 {
                    return [["capture_error": "public accessibility child inventory exceeded fixture bound"]]
                }
                if let identifier = view.accessibilityIdentifier, !identifier.isEmpty {
                    var control: [String: Any] = ["id": Self.identity(view), "identifier": identifier,
                        "label": view.accessibilityLabel ?? "nil", "value": view.accessibilityValue ?? "nil",
                        "frame_in_window": Self.rect(view.convert(view.bounds, to: window)),
                        "hidden": view.isHidden, "alpha": view.alpha, "kind": "UIView"]
                    if identifier.hasSuffix(".receipt"), let label = view as? UILabel {
                        control["text"] = label.text ?? "nil"
                    }
                    result.append(control)
                }
            } else if let element = object as? UIAccessibilityElement,
                      let identifier = element.accessibilityIdentifier, !identifier.isEmpty {
                result.append(["id": Self.identity(element), "identifier": identifier,
                    "label": element.accessibilityLabel ?? "nil", "value": element.accessibilityValue ?? "nil",
                    "frame_in_window": Self.rect(window.screen.coordinateSpace.convert(element.accessibilityFrame, to: window)),
                    "kind": "UIAccessibilityElement"])
            }
        }
        return result
    }

    func topology(includeControls: Bool) -> [String: Any] {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let inventory: [[String: Any]] = scenes.map { scene in
            ["id": scene.session.persistentIdentifier, "activation": scene.activationState.rawValue,
             "orientation": scene.interfaceOrientation.rawValue,
             "screen_bounds": Self.rect(scene.screen.bounds), "screen_scale": scene.screen.scale,
             "coordinate_bounds": Self.rect(scene.coordinateSpace.bounds),
             "windows": scene.windows.map { window -> [String: Any] in
                ["id": Self.identity(window), "key": window.isKeyWindow, "hidden": window.isHidden,
                 "alpha": window.alpha, "level": window.windowLevel.rawValue, "bounds": Self.rect(window.bounds),
                 "root": Self.identity(window.rootViewController), "root_attached": window.rootViewController?.viewIfLoaded?.window === window,
                 "root_bundle": window.rootViewController.map { Bundle(for: type(of: $0)).bundleURL.path } ?? "nil",
                 "window_bundle": Bundle(for: type(of: window)).bundleURL.path,
                 "owned": window === ownedWindow]
             }]
        }
        return ["app_state": UIApplication.shared.applicationState.rawValue, "framework": Settings.framework,
            "public_bundles": ["uikit_window": Bundle(for: UIWindow.self).bundleURL.path,
                "uikit_navigation": Bundle(for: UINavigationController.self).bundleURL.path,
                "uikit_split": Bundle(for: UISplitViewController.self).bundleURL.path,
                "swiftui_hosting": Bundle(for: UIHostingController<EmptyView>.self).bundleURL.path],
            "window_framework_bundle": Bundle(for: UIWindow.self).bundleURL.path,
            "controller_framework_bundle": Bundle(for: UIViewController.self).bundleURL.path,
            "fixture_bundle": Bundle.main.bundleURL.path,
            "bound_window": boundWindowID ?? "nil", "bound_root": boundRootID ?? "nil", "bound_scene": boundSceneID ?? "nil",
            "window_alive": ownedWindow != nil, "root_alive": ownedRoot != nil,
            "bound_root_unchanged": ownedWindow?.rootViewController === ownedRoot,
            "scene_inventory": inventory,
            "accessibility": includeControls ? ownedWindow.map(accessibility) ?? [] : [],
            "scrolls": includeControls ? ownedWindow.map { window in views(window).compactMap { ($0 as? UIScrollView).map(scrollSnapshot) } } ?? [] : []]
    }
    func scrollSnapshot(_ scroll: UIScrollView) -> [String: Any] {
        let window = scroll.window
        return ["id": Self.identity(scroll), "window": Self.identity(window),
            "scene": window?.windowScene?.session.persistentIdentifier ?? "nil", "owned": window != nil && window === ownedWindow,
            "frame_in_window": window.map { Self.rect(scroll.convert(scroll.bounds, to: $0)) } ?? [],
            "bounds": Self.rect(scroll.bounds), "offset": Self.point(scroll.contentOffset),
            "content_size": [scroll.contentSize.width, scroll.contentSize.height],
            "hidden": scroll.isHidden, "alpha": scroll.alpha, "enabled": scroll.isScrollEnabled,
            "tracking": scroll.isTracking, "dragging": scroll.isDragging, "decelerating": scroll.isDecelerating,
            "accessibility_id": scroll.accessibilityIdentifier ?? "nil"]
    }
}

@MainActor private final class ScrollWitness: NSObject {
    private weak var scroll: UIScrollView?
    private var gestureID: String?
    private var requestID: String?
    init(scroll: UIScrollView) { self.scroll = scroll }
    @objc func observe(_ recognizer: UIPanGestureRecognizer) {
        guard let scroll = scroll, recognizer === scroll.panGestureRecognizer else { return }
        let owner = HumanObservation.shared
        switch recognizer.state {
        case .began:
            guard let current = owner.currentRequestID else { return }
            requestID = current; gestureID = UUID().uuidString.lowercased()
            record("human_scroll_begin", recognizer, scroll, owner)
        case .ended, .cancelled, .failed:
            guard gestureID != nil else { return }
            record("human_scroll_end", recognizer, scroll, owner)
            gestureID = nil; requestID = nil
        default: break
        }
    }
    private func record(_ kind: String, _ recognizer: UIPanGestureRecognizer, _ scroll: UIScrollView, _ owner: HumanObservation) {
        let started = DispatchTime.now().uptimeNanoseconds
        let event = ObservationStore.shared.append(kind, ["gesture_id": gestureID ?? "nil", "request_id": requestID ?? "nil",
            "current_request_id": owner.currentRequestID ?? "nil", "state": recognizer.state.rawValue,
            "uptime_ns": DispatchTime.now().uptimeNanoseconds, "translation": HumanObservation.point(recognizer.translation(in: scroll)),
            "scroll": owner.scrollSnapshot(scroll)])
        owner.cost("scroll", started: started, event: event)
    }
}


// All request bytes and JSON are handled on this serial queue. Main-thread work
// is limited to an explicit UIKit snapshot after the request is validated.
private final class HumanSnapshotRequests: @unchecked Sendable {
    private let queue = DispatchQueue(label: "fixture.human.requests", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var previousBytes: String?
    private var requests = Set<String>()
    private var payloads = Set<String>()
    func start(_ receive: @escaping @Sendable (String, String, String, String?) -> Void) {
        let run = Settings.runID
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("human-snapshot-request.json")
        queue.async { [self] in
            guard timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(200))
            timer.setEventHandler { [weak self] in
                guard let self = self, let bytes = try? Data(contentsOf: path) else { return }
                let fingerprint = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
                guard fingerprint != self.previousBytes else { return }
                self.previousBytes = fingerprint
                guard let request = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                      Set(request.keys) == Set(["schema_version", "run_id", "request_id", "phase"]),
                      request["schema_version"] as? Int == 1,
                      request["run_id"] as? String == run, !run.isEmpty,
                      let identifier = request["request_id"] as? String, UUID(uuidString: identifier)?.uuidString.lowercased() == identifier,
                      let phase = request["phase"] as? String, !phase.isEmpty,
                      !self.requests.contains(identifier), !self.payloads.contains(fingerprint) else {
                    receive("nil", "nil", fingerprint, "invalid or consumed native snapshot request"); return
                }
                self.requests.insert(identifier); self.payloads.insert(fingerprint)
                receive(identifier, phase, fingerprint, nil)
            }
            self.timer = timer; timer.resume()
        }
    }
}
