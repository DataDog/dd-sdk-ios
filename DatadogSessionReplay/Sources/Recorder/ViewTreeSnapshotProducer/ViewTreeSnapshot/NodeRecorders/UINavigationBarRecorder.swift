/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit

internal final class UINavigationBarRecorder: NodeRecorder {
    let identifier = UUID()

    private enum Constants {
        static let defaultTitleFontColor = UIColor.black
        static let defaultTitleFontColorInBlackMode = UIColor.white
        static let defaultIconTintColor = SystemColors.systemBlue
    }

    private var currentlyProcessedNavbar: UINavigationBar? = nil
    private lazy var subtreeViewRecorder: ViewTreeRecorder = {
        ViewTreeRecorder(
            nodeRecorders: [
                // This is to record the icons' color.
                UIImageViewRecorder(
                    tintColorProvider: { imageView in
                        guard let imageViewImage = imageView.image else {
                            return nil
                        }

                        if let tintColor = imageView.tintColor {
                            print("image tintColor:", tintColor)
                        }

                        let superview = imageView.superview
                        let sup2 = superview?.superview
                        let sup3 = sup2?.superview
                        print("superview:", superview ?? "nil")
                        print("sup2:", sup2 ?? "nil")
                        print("sup3:", sup3 ?? "nil")

                        return imageView.tintColor ?? Constants.defaultIconTintColor

                        /*guard let navBar = self.currentlyProcessedNavbar else {
                            return imageView.tintColor
                        }*/

                        // Retrieve the tab bar item containing the imageView.
                        /*let currentItemInSelectedState = tabBar.items?.first {
                            let itemSelectedImage = $0.selectedImage

                            // Important note when comparing the different tab bar items' icons:
                            // our hypothesis is that each item uses a different image.
                            return itemSelectedImage?.uniqueDescription == imageViewImage.uniqueDescription
                        }

                        // If the item is not selected,
                        // return the unselectedItemTintColor,
                        // or the default gray color if not set.
                        if currentItemInSelectedState == nil || tabBar.selectedItem != currentItemInSelectedState {
                            return tabBar.unselectedItemTintColor ?? SystemColors.systemGray.withAlphaComponent(0.5)
                        }

                        // Otherwise, return the tab bar tint color,
                        // or the default blue color if not set.
                        return tabBar.tintColor ?? SystemColors.systemBlue*/
                    }
                ),
                // This is to record the title's and text item's color.
                UILabelRecorder(
                    builderOverride: { builder in
                        guard let navBar = self.currentlyProcessedNavbar else {
                            return builder
                        }

                        var builder = builder
                        builder.textColor = Constants.defaultTitleFontColor.cgColor

                        // Title
                        navBar.items?.forEach { item in
                            // Title item
                            if let title = item.title {
                                print("title:", title)

                                if let attributes = navBar.titleTextAttributes,
                                   let color = attributes[NSAttributedString.Key.foregroundColor] as? UIColor {
                                    print("text color:", color)
                                    builder.textColor = color.cgColor
                                } else if navBar.barStyle == .black {
                                    builder.textColor = Constants.defaultTitleFontColorInBlackMode.cgColor
                                }
                            // Other items
                            } else {
                                //if let item =
                            }
                        }

                        return builder
                    }
                )
            ]
        )
    }()

    func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) -> NodeSemantics? {
        guard let navigationBar = view as? UINavigationBar else {
            return nil
        }

        guard attributes.isVisible else {
            return InvisibleElement.constant
        }

        currentlyProcessedNavbar = navigationBar

        let builder = UINavigationBarWireframesBuilder(
            wireframeRect: inferOccupiedFrame(of: navigationBar, in: context),
            wireframeID: context.ids.nodeID(view: navigationBar, nodeRecorder: self),
            attributes: attributes,
            color: inferColor(of: navigationBar)
        )

        let node = Node(viewAttributes: attributes, wireframesBuilder: builder)
        let subtreeRecordingResults = subtreeViewRecorder.record(navigationBar, in: context)
        let allNodes = [node] + subtreeRecordingResults.nodes
        let resources = subtreeRecordingResults.resources

        return SpecificElement(subtreeStrategy: .ignore, nodes: allNodes, resources: resources)
        //return SpecificElement(subtreeStrategy: .record, nodes: [node])
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

        if let color = navigationBar.backgroundColor {
            return color.cgColor
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
                borderColor: UIColor.lightGray.withAlphaComponent(0.5).cgColor,
                borderWidth: 0.5,
                backgroundColor: color,
                cornerRadius: attributes.layerCornerRadius,
                opacity: attributes.alpha
            )
        ]
    }
}
#endif
