/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit

internal struct UINavigationBarRecorder: NodeRecorder {
    internal let identifier: UUID

    init(identifier: UUID) {
        self.identifier = identifier
    }

    func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) -> NodeSemantics? {
        guard let navigationBar = view as? UINavigationBar else {
            return nil
        }

        guard attributes.isVisible else {
            return InvisibleElement.constant
        }

        let builder = UINavigationBarWireframesBuilder(
            wireframeRect: inferOccupiedFrame(of: navigationBar, in: context),
            wireframeID: context.ids.nodeID(view: navigationBar, nodeRecorder: self),
            attributes: attributes,
            color: inferBackgroundColor(of: navigationBar)
        )

        let node = Node(viewAttributes: attributes, wireframesBuilder: builder)
        return SpecificElement(subtreeStrategy: .record, nodes: [node])
    }

    private func inferOccupiedFrame(of navigationBar: UINavigationBar, in context: ViewTreeRecordingContext) -> CGRect {
        var occupiedFrame = navigationBar.frame
        var largeTitleFrame: CGRect?

        for subview in navigationBar.subviews {
            let subviewFrame = subview.convert(subview.bounds, to: context.coordinateSpace)

            if subview.isNavigationBarLargeTitleView {
                largeTitleFrame = subviewFrame
            }

            occupiedFrame = occupiedFrame.union(subviewFrame)
        }

        if #available(iOS 26, *), navigationBar.isSwiftUINavigationBar, let largeTitleFrame {
            // For SwiftUI navigation bars, exclude the large title view from `occupiedFrame`
            // to prevent occluding the large title that's rendered as a sibling view
            let height = max(0, min(largeTitleFrame.height, occupiedFrame.height))
            occupiedFrame = occupiedFrame.inset(by: .init(top: 0, left: 0, bottom: height, right: 0))
        }

        return occupiedFrame
    }

    private func inferBackgroundColor(of navigationBar: UINavigationBar) -> CGColor {
        if let color = navigationBar.backgroundColor {
            return color.cgColor
        } else if !navigationBar.isTranslucent {
            return UIColor.black.cgColor
        }

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
                clip: attributes.clip,
                borderColor: UIColor.lightGray.withAlphaComponent(0.5).cgColor,
                borderWidth: 1,
                backgroundColor: color,
                cornerRadius: attributes.layerCornerRadius,
                opacity: attributes.alpha
            )
        ]
    }
}

extension UIView {
    private enum Constants {
        static let UIKitNavigationBarClass: AnyClass? = NSClassFromString("SwiftUI.UIKitNavigationBar")
        static let NavigationBarLargeTitleView: AnyClass? = NSClassFromString("UIKit.NavigationBarLargeTitleView")
    }

    fileprivate var isSwiftUINavigationBar: Bool {
        guard let cls = Constants.UIKitNavigationBarClass else {
            return false
        }
        return type(of: self).isSubclass(of: cls)
    }

    fileprivate var isNavigationBarLargeTitleView: Bool {
        guard let cls = Constants.NavigationBarLargeTitleView else {
            return false
        }
        return type(of: self).isSubclass(of: cls)
    }
}

#endif
