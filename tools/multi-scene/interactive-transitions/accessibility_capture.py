"""Opt-in public accessibility traversal for copied SwiftUI capture fixtures."""
import hashlib

FUNCTION_SHA256 = '190fb105cfedb01313a634cf5e7d3d8c5a040b97013a45685ab35a27a99132ce'
START = '    private func accessibility(_ window: UIWindow) -> [[String: Any]] {'
END = '\n    func topology('

PUBLIC_CAPTURE = r'''    private func publicAccessibility(_ window: UIWindow) -> [[String: Any]] {
        typealias Visual = (view: UIView, parent: String, hidden: Bool, alpha: CGFloat,
                            localHidden: Bool, localAlpha: CGFloat, children: [ObjectIdentifier])
        func actualView(_ view: UIView) -> [String: Any] {
            return ["id": Self.identity(view), "parent": Self.identity(view.superview),
                    "window": Self.identity(view.window), "hidden": view.isHidden,
                    "alpha": view.alpha.isFinite ? view.alpha as Any : String(describing: view.alpha),
                    "children": view.subviews.map { Self.identity($0) }]
        }
        func capturedView(_ state: Visual) -> [String: Any] {
            return ["id": Self.identity(state.view), "parent": state.parent,
                    "window": Self.identity(window), "hidden": state.localHidden, "alpha": state.localAlpha,
                    "children": state.children.map { String(describing: $0) }]
        }
        var visual = [ObjectIdentifier: Visual]()
        var viewPending: [(UIView, String, Bool, CGFloat)] = [(window, "nil", false, 1)]
        while let (view, parent, inheritedHidden, inheritedAlpha) = viewPending.popLast() {
            let identity = ObjectIdentifier(view)
            guard visual[identity] == nil, visual.count < 4096,
                  Self.identity(view.superview) == parent,
                  (view === window && parent == "nil") || (view.window === window && parent != "nil") else {
                return [["capture_error": "invalid owned view ancestry", "expected_parent": parent,
                         "current_view": actualView(view)]]
            }
            let localHidden = view.isHidden, localAlpha = view.alpha
            guard localAlpha.isFinite, localAlpha >= 0, localAlpha <= 1 else {
                return [["capture_error": "invalid owned view alpha"]]
            }
            let hidden = inheritedHidden || localHidden, alpha = inheritedAlpha * localAlpha
            let children = view.subviews
            guard children.count <= 4096, viewPending.count + children.count <= 4096 else {
                return [["capture_error": "owned view inventory exceeded fixture bound"]]
            }
            visual[identity] = (view, parent, hidden, alpha, localHidden, localAlpha,
                                children.map { ObjectIdentifier($0) })
            for child in children { viewPending.append((child, Self.identity(view), hidden, alpha)) }
        }
        func unchanged(_ state: Visual) -> Bool {
            let view = state.view
            return (view === window || view.window === window)
                && Self.identity(view.superview) == state.parent
                && view.isHidden == state.localHidden && view.alpha == state.localAlpha
                && view.subviews.map { ObjectIdentifier($0) } == state.children
        }
        typealias Item = (object: NSObject, parent: String, edge: String, hidden: Bool, alpha: CGFloat)
        var pending: [Item] = [(window, "nil", "owned-window", false, 1)]
        var observed = [ObjectIdentifier: NSObject]()
        var order = [String]()
        var records = [String: [String: Any]]()
        var visibility = [String: (Bool, CGFloat)]()
        var visibilityPaths = [String: [String: Any]]()
        var pathObservations = [String: [String: [String: Any]]]()
        var containers = [String: Set<String>]()
        var edges = [String: Set<String>]()
        var error: String?
        func enqueue(_ children: [Any], parent: String, edge: String, hidden: Bool, alpha: CGFloat) {
            guard children.count <= 4096, pending.count + children.count <= 4096 else {
                error = "public accessibility child inventory exceeded fixture bound"; return
            }
            for child in children {
                guard let object = child as? NSObject else {
                    error = "public accessibility child is not an NSObject"; return
                }
                pending.append((object, parent, edge, hidden, alpha))
            }
        }
        while let item = pending.popLast() {
            let object = item.object, id = Self.identity(object)
            var hidden = item.hidden, alpha = item.alpha
            var pathHidden = hidden, pathAlpha = alpha
            var viewState: [String: Any]?
            if let view = object as? UIView {
                guard let state = visual[ObjectIdentifier(view)] else {
                    return [["capture_error": "public accessibility view has missing owned ancestry",
                             "current_view": actualView(view)]]
                }
                guard unchanged(state) else {
                    return [["capture_error": "public accessibility view has changed owned ancestry",
                             "first_view": capturedView(state), "current_view": actualView(view)]]
                }
                pathHidden = item.hidden || state.localHidden; pathAlpha = item.alpha * state.localAlpha
                hidden = state.hidden; alpha = state.alpha
                viewState = ["parent": state.parent, "window": Self.identity(window),
                             "hidden": state.localHidden, "alpha": state.localAlpha]
            }
            guard alpha.isFinite, alpha >= 0 else {
                return [["capture_error": "invalid public accessibility visibility"]]
            }
            containers[id, default: []].insert(item.parent)
            edges[id, default: []].insert(item.parent + ":" + item.edge)
            let visibilityPath: [String: Any] = [
                "parent": item.parent, "edge": item.edge,
                "inherited_hidden": item.hidden, "inherited_alpha": item.alpha,
                "hidden": pathHidden, "alpha": pathAlpha]
            let edgeKey = item.parent + ":" + item.edge
            pathObservations[id, default: [:]][edgeKey] = visibilityPath
            let identity = ObjectIdentifier(object)
            if observed[identity] != nil {
                guard let prior = visibility[id], prior.0 == hidden, prior.1 == alpha else {
                    return [["capture_error": "conflicting public accessibility visibility paths",
                        "conflict": ["object_id": id,
                            "first_path": visibilityPaths[id] ?? [:],
                            "current_path": visibilityPath,
                            "first_record": records[id] ?? [:]]]]
                }
                continue
            }
            observed[identity] = object
            guard observed.count <= 4096 else {
                return [["capture_error": "public accessibility inventory exceeded fixture bound"]]
            }
            visibility[id] = (hidden, alpha); visibilityPaths[id] = visibilityPath; order.append(id)
            let frame: CGRect
            let kind: String
            if let view = object as? UIView {
                frame = view.convert(view.bounds, to: window); kind = "UIView"
            } else {
                frame = window.screen.coordinateSpace.convert(object.accessibilityFrame, to: window)
                kind = object is UIAccessibilityElement ? "UIAccessibilityElement" : "UIAccessibilityObject"
            }
            let elementsHidden = object.accessibilityElementsHidden
            records[id] = ["id": id,
                "identifier": (object as? UIAccessibilityIdentification)?.accessibilityIdentifier ?? "nil",
                "label": object.accessibilityLabel ?? "nil", "value": object.accessibilityValue ?? "nil",
                "frame_in_window": Self.rect(frame), "hidden": hidden, "alpha": alpha, "kind": kind,
                "visibility_basis": viewState == nil ? "container-path" : "view-hierarchy",
                "accessibility_elements_hidden": elementsHidden]
            if let viewState = viewState { records[id]?["view_state"] = viewState }
            let childrenHidden = hidden || elementsHidden
            if let view = object as? UIView {
                enqueue(view.subviews, parent: id, edge: "subviews", hidden: childrenHidden, alpha: alpha)
            }
            if let values = object.accessibilityElements {
                enqueue(values, parent: id, edge: "accessibilityElements", hidden: childrenHidden, alpha: alpha)
            }
            if #available(iOS 17.0, *) {
                if let values = object.automationElements {
                    enqueue(values, parent: id, edge: "automationElements", hidden: childrenHidden, alpha: alpha)
                }
            }
            let count = object.accessibilityElementCount()
            guard count == NSNotFound || (count >= 0 && count <= 4096) else {
                return [["capture_error": "invalid public accessibility indexed child count"]]
            }
            if count != NSNotFound && count > 0 {
                for index in 0..<count {
                    guard let child = object.accessibilityElement(at: index) else {
                        return [["capture_error": "public accessibility indexed child missing"]]
                    }
                    enqueue([child], parent: id, edge: "accessibilityElementAtIndex", hidden: childrenHidden, alpha: alpha)
                    if error != nil { break }
                }
            }
            if let error = error { return [["capture_error": error]] }
        }
        if let changed = visual.values.first(where: { !unchanged($0) }) {
            return [["capture_error": "owned view ancestry changed during public inventory",
                     "first_view": capturedView(changed), "current_view": actualView(changed.view)]]
        }
        return order.compactMap { id in
            guard var record = records[id] else { return nil }
            record["container_ids"] = (containers[id] ?? []).sorted()
            record["container_edges"] = (edges[id] ?? []).sorted()
            record["visibility_paths"] = (pathObservations[id] ?? [:]).sorted { $0.key < $1.key }.map { $0.value }
            return record
        }
    }
'''


def original_function(source):
    text = source.decode()
    if text.count(START) != 1 or text.count(END) != 1:
        raise ValueError('ambiguous accessibility inventory source')
    start = text.index(START); end = text.index(END, start)
    function = text[start:end]
    if hashlib.sha256(function.encode()).hexdigest() != FUNCTION_SHA256:
        raise ValueError('accessibility inventory source changed')
    return text, start, end, function


def render_human(source, source_sha256):
    if hashlib.sha256(source).hexdigest() != source_sha256:
        raise ValueError('human capture source binding changed')
    text, start, end, function = original_function(source)
    dispatch = START + '\n        if Settings.framework == "SwiftUI" { return publicAccessibility(window) }'
    replacement = function.replace(START, dispatch, 1) + '\n' + PUBLIC_CAPTURE
    return (text[:start] + replacement + text[end:]).encode()
