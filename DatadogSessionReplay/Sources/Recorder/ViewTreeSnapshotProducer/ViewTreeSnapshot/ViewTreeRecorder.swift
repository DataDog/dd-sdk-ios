/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit
import DatadogInternal

internal struct ViewTreeRecorder {
    /// An array of enabled node recorders.
    ///
    /// The order in this this array  should be managed consciously. For each node, the implementation loops
    /// through `nodeRecorders` and stops on the one that recorded node semantics with highes importance.
    let nodeRecorders: [NodeRecorder]

    /// The bundle identifier used for heatmap identifier computation
    private let bundleIdentifier: () -> String?

    init(
        nodeRecorders: [NodeRecorder],
        bundleIdentifier: @autoclosure @escaping () -> String? = Bundle.main.bundleIdentifier
    ) {
        self.nodeRecorders = nodeRecorders
        self.bundleIdentifier = bundleIdentifier
    }

    /// Creates `Nodes` for given view and its subtree hierarchy.
    func record(_ anyView: UIView, in context: ViewTreeRecordingContext) -> [Node] {
        var nodes: [Node] = []
        recordRecursively(nodes: &nodes, view: anyView, typeIndex: 0, context: context, overrides: anyView.dd._privacyOverrides)
        return nodes
    }

    // MARK: - Private

    private func recordRecursively(
        nodes: inout [Node],
        view: UIView,
        typeIndex: Int,
        context: ViewTreeRecordingContext,
        overrides: PrivacyOverrides?
    ) {
        var context = context
        if let viewController = view.next as? UIViewController {
            context.viewControllerContext.parentType = .init(viewController)
            context.viewControllerContext.isRootView = view == viewController.view
        } else {
            context.viewControllerContext.isRootView = false
        }

        // Convert the frame in root view space
        let frame = view.convert(view.bounds, to: context.coordinateSpace)

        if view.clipsToBounds {
            // Propagate view's clipping intersection when clipsToBounds is
            // enabled.
            context.clip = frame.intersection(context.clip)
        }

        // Compute the heatmap identifier
        let heatmapIdentifier = context.recorder.viewPath.map { viewPath in
            let component: String
            if let accessibilityIdentifier = view.accessibilityIdentifier, !accessibilityIdentifier.isEmpty {
                component = accessibilityIdentifier
            } else {
                component = "cls:\(String(describing: type(of: view)))#\(typeIndex)"
            }
            context.nodePath.append(component)

            let heatmapIdentifier = HeatmapIdentifier(
                elementPath: context.nodePath,
                screenName: viewPath,
                bundleIdentifier: bundleIdentifier() ?? "unknown"
            )

            context.heatmapCache.identifiers[ObjectIdentifier(view)] = heatmapIdentifier
            return heatmapIdentifier
        }

        let attributes = ViewAttributes(view: view, frame: frame, clip: context.clip, overrides: overrides)
        let semantics = nodeSemantics(for: view, with: attributes, in: context)

        if !semantics.nodes.isEmpty {
            nodes.append(
                contentsOf: heatmapIdentifier.map { heatmapIdentifier in
                    semantics.nodes.map {
                        $0.withHeatmapIdentifier(heatmapIdentifier)
                    }
                } ?? semantics.nodes
            )
        }

        switch semantics.subtreeStrategy {
        case .record:
            let typeIndices = self.typeIndices(for: view.subviews)
            for (index, subview) in view.subviews.enumerated() {
                let subviewOverrides = SessionReplayPrivacyOverrides.merge(subview.dd._privacyOverrides, with: overrides)
                recordRecursively(
                    nodes: &nodes,
                    view: subview,
                    typeIndex: typeIndices[index],
                    context: context,
                    overrides: subviewOverrides
                )
            }
        case .ignore:
            break
        }
    }

    /// Computes same type sibling indices for an array of subviews in a single O(N) pass.
    private func typeIndices(for subviews: [UIView]) -> [Int] {
        var typeCounts: [ObjectIdentifier: Int] = [:]
        return subviews.map { subview in
            let identifier = ObjectIdentifier(type(of: subview))
            let index = typeCounts[identifier, default: 0]
            typeCounts[identifier] = index + 1
            return index
        }
    }

    private func nodeSemantics(for view: UIView, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) -> NodeSemantics {
        var semantics: NodeSemantics = UnknownElement.constant

        for nodeRecorder in nodeRecorders {
            guard let nextSemantics = nodeRecorder.semantics(of: view, with: attributes, in: context) else {
                continue
            }

            if nextSemantics.importance >= semantics.importance {
                semantics = nextSemantics

                if nextSemantics.importance == .max {
                    // We know the current semantics is best we can get, so skip querying other `nodeRecorders`:
                    break
                }
            }
        }

        return semantics
    }
}

extension Node {
    fileprivate func withHeatmapIdentifier(_ heatmapIdentifier: HeatmapIdentifier) -> Self {
        var node = self
        node.heatmapIdentifier = heatmapIdentifier
        return node
    }
}
#endif
