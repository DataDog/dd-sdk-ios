/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit

internal final class UITabBarRecorder: NodeRecorder {
    let identifier = UUID()

    private var currentlyProcessedTabbar: UITabBar? = nil
    private lazy var subtreeViewRecorder: ViewTreeRecorder = {
        ViewTreeRecorder(
            nodeRecorders: [
                UIImageViewRecorder(
                    tintColorProvider: { imageView in
                        guard let imageViewImage = imageView.image else {
                            return nil
                        }
                        guard let tabBar = self.currentlyProcessedTabbar else {
                            return imageView.tintColor
                        }

                        // Retrieve the tab bar item containing the imageView.
                        let currentItemInSelectedState = tabBar.items?.first {
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
                        return tabBar.tintColor ?? SystemColors.systemBlue
                    }
                ),
                UILabelRecorder(),
                // This is for recording the badge view
                UIViewRecorder()
            ]
        )
    }()

    func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) -> NodeSemantics? {
        guard let tabBar = view as? UITabBar else {
            return nil
        }

        currentlyProcessedTabbar = tabBar

        let builder = UITabBarWireframesBuilder(
            wireframeRect: inferOccupiedFrame(of: tabBar, in: context),
            wireframeID: context.ids.nodeID(view: tabBar, nodeRecorder: self),
            attributes: attributes,
            color: inferColor(of: tabBar)
        )

        let node = Node(viewAttributes: attributes, wireframesBuilder: builder)

        let subtreeRecordingResults = subtreeViewRecorder.record(tabBar, in: context)
        let allNodes = [node] + subtreeRecordingResults.nodes
        let resources = subtreeRecordingResults.resources

        return SpecificElement(subtreeStrategy: .ignore, nodes: allNodes, resources: resources)
    }

    private func inferOccupiedFrame(of tabBar: UITabBar, in context: ViewTreeRecordingContext) -> CGRect {
        var occupiedFrame = tabBar.frame
        for subview in tabBar.subviews {
            let subviewFrame = subview.convert(subview.bounds, to: context.coordinateSpace)
            occupiedFrame = occupiedFrame.union(subviewFrame)
        }
        return occupiedFrame
    }

    private func inferColor(of tabBar: UITabBar) -> CGColor {
        if let color = tabBar.backgroundColor {
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

fileprivate extension UIImage {
    /// Returns a unique description of the image.
    /// It is calculated from `CGImage` properties,
    /// Favors performance over acurracy (collisions are unlikely, but possible).
    /// May return `nil` if the image has no associated `CGImage`.
    var uniqueDescription: String? {
        // Some images may not have an associated `CGImage`,
        // e.g., vector-based images (PDF, SVG), `CIImage`.
        // In the case of tab bar icons,
        // it is likely they have an associated `CGImage`.
        guard let cgImage = self.cgImage else {
            return nil
        }
        // Combine properties to create an unique ID.
        // Note: it is unlikely but not impossible for two different images to have the same ID.
        // This could occur if two images have identical properties and pixel structures.
        // In many use cases, such as tab bar icons in an app, the risk of collision is acceptable.
        return "\(cgImage.width)x\(cgImage.height)-\(cgImage.bitsPerComponent)x\(cgImage.bitsPerPixel)-\(cgImage.bytesPerRow)-\(cgImage.bitmapInfo)"
    }
}
