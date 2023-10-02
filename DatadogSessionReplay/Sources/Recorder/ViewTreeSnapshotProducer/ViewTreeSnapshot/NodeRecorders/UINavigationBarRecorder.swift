/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit

internal struct UINavigationBarRecorder: NodeRecorder {
    let identifier = UUID()

    func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) -> NodeSemantics? {
        guard let navigationBar = view as? UINavigationBar else {
            return nil
        }

        let builder = UINavigationBarWireframesBuilder(
            wireframeRect: inferOccupiedFrame(of: navigationBar, in: context),
            wireframeID: context.ids.nodeID(view: navigationBar, nodeRecorder: self),
            attributes: attributes,
            color: inferColor(of: navigationBar)
        )

        let node = Node(viewAttributes: attributes, wireframesBuilder: builder)
        return SpecificElement(subtreeStrategy: .record, nodes: [node])
    }

    private func inferOccupiedFrame(of navigationBar: UINavigationBar, in context: ViewTreeRecordingContext) -> CGRect {
        // TODO: RUMM-2791 Enhance appearance of `UITabBar` and `UINavigationBar` in SR
        var occupiedFrame = navigationBar.frame
        for subview in navigationBar.subviews {
            let subviewFrame = subview.convert(subview.bounds, to: context.coordinateSpace)
            occupiedFrame = occupiedFrame.union(subviewFrame)
        }
        return occupiedFrame
    }

    private func inferColor(of navigationBar: UINavigationBar) -> CGColor {
        // TODO: RUMM-2791 Enhance appearance of `UITabBar` and `UINavigationBar` in SR
        if #available(iOS 13.0, *) {
            switch UITraitCollection.current.userInterfaceStyle {
            case .light:
                return UIColor.white.cgColor
            case .dark:
                return UIColor.black.cgColor
            default:
                return UIColor.white.cgColor
            }
        } else {
            return UIColor.white.cgColor
        }
    }
}

internal struct UINavigationBarWireframesBuilder: NodeWireframesBuilder {
    let wireframeRect: CGRect
    let wireframeID: WireframeID
    /// Attributes of the `UIView`.
    let attributes: ViewAttributes
    /// The color of navigation bar.
    let color: CGColor

    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] {
        return [
            builder.createShapeWireframe(
                id: wireframeID,
                frame: wireframeRect,
                borderColor: UIColor.gray.cgColor,
                borderWidth: 1,
                backgroundColor: color,
                cornerRadius: attributes.layerCornerRadius,
                opacity: attributes.alpha
            )
        ]
    }
}
#endif
