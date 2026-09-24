"""Opt-in public accessibility traversal for copied SwiftUI capture fixtures."""
import hashlib

FUNCTION_SHA256 = '190fb105cfedb01313a634cf5e7d3d8c5a040b97013a45685ab35a27a99132ce'
START = '    private func accessibility(_ window: UIWindow) -> [[String: Any]] {'
END = '\n    func topology('

PUBLIC_CAPTURE = r'''    private func publicAccessibility(_ window: UIWindow) -> [[String: Any]] {
        typealias Item = (object: NSObject, parent: String, edge: String, hidden: Bool, alpha: CGFloat)
        var pending: [Item] = [(window, "nil", "owned-window", false, 1)]
        var observed = [ObjectIdentifier: NSObject]()
        var order = [String]()
        var records = [String: [String: Any]]()
        var visibility = [String: (Bool, CGFloat)]()
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
            if let view = object as? UIView {
                guard view === window || view.window === window else {
                    return [["capture_error": "public accessibility view belongs to another window"]]
                }
                hidden = hidden || view.isHidden; alpha *= view.alpha
            }
            guard alpha.isFinite, alpha >= 0 else {
                return [["capture_error": "invalid public accessibility visibility"]]
            }
            containers[id, default: []].insert(item.parent)
            edges[id, default: []].insert(item.parent + ":" + item.edge)
            let identity = ObjectIdentifier(object)
            if observed[identity] != nil {
                guard let prior = visibility[id], prior.0 == hidden, prior.1 == alpha else {
                    return [["capture_error": "conflicting public accessibility visibility paths"]]
                }
                continue
            }
            observed[identity] = object
            guard observed.count <= 4096 else {
                return [["capture_error": "public accessibility inventory exceeded fixture bound"]]
            }
            visibility[id] = (hidden, alpha); order.append(id)
            let frame: CGRect
            let kind: String
            if let view = object as? UIView {
                frame = view.convert(view.bounds, to: window); kind = "UIView"
            } else {
                frame = window.screen.coordinateSpace.convert(object.accessibilityFrame, to: window)
                kind = object is UIAccessibilityElement ? "UIAccessibilityElement" : "UIAccessibilityObject"
            }
            records[id] = ["id": id,
                "identifier": (object as? UIAccessibilityIdentification)?.accessibilityIdentifier ?? "nil",
                "label": object.accessibilityLabel ?? "nil", "value": object.accessibilityValue ?? "nil",
                "frame_in_window": Self.rect(frame), "hidden": hidden, "alpha": alpha, "kind": kind]
            let childrenHidden = hidden || object.accessibilityElementsHidden
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
        return order.compactMap { id in
            guard var record = records[id] else { return nil }
            record["container_ids"] = (containers[id] ?? []).sorted()
            record["container_edges"] = (edges[id] ?? []).sorted()
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
