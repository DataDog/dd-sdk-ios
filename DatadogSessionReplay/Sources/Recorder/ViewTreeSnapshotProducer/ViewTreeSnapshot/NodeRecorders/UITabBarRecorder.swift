/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit

internal struct UITabBarRecorder: NodeRecorder {
    let identifier = UUID()
    func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) -> NodeSemantics? {
        guard let tabBar = view as? UITabBar else {
            return nil
        }

        let builder = UITabBarWireframesBuilder(
            wireframeRect: inferOccupiedFrame(of: tabBar, in: context),
            wireframeID: context.ids.nodeID(view: tabBar, nodeRecorder: self),
            attributes: attributes,
            color: inferColor(of: tabBar)
        )
        let node = Node(viewAttributes: attributes, wireframesBuilder: builder)
        return SpecificElement(subtreeStrategy: .record, nodes: [node])
    }

    private func inferOccupiedFrame(of tabBar: UITabBar, in context: ViewTreeRecordingContext) -> CGRect {
        // TODO: RUMM-2791 Enhance appearance of `UITabBar` and `UINavigationBar` in SR
        var occupiedFrame = tabBar.frame
        for subview in tabBar.subviews {
            let subviewFrame = subview.convert(subview.bounds, to: context.coordinateSpace)
            occupiedFrame = occupiedFrame.union(subviewFrame)
        }
        return occupiedFrame
    }

    private func inferColor(of tabBar: UITabBar) -> CGColor {
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

internal struct UITabBarWireframesBuilder: NodeWireframesBuilder {
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
