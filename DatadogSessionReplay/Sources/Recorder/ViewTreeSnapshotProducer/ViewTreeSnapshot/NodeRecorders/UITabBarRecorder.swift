/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit

internal class UITabBarRecorder: NodeRecorder {
    let identifier = UUID()

    private var currentlyProcessedTabbar: UITabBar? = nil

    // Some notes
    //
    // 1) Comparison options
    // Since the image comparision is costly + on the main thread,
    // a slightly better way might be to store/cache in the recorder
    // each item's image the first time we traverse the tab bar.
    // This way, we don't have to regenerate the hash (srIdentifier) each time we record
    // the tabbar view hierarchy.
    // Following this option, we can also store an alternative hash,
    // but faster than the md5 used for srIdentifier.
    //
    // 2) Image data comparision
    // We could also do the comparision using a JPG representation instead of a PNG comparision,
    // which might be a bit faster.
    // Tabbar icons are typically small and transparent,
    // which probably makes PNG comparison more suited.
    // On another note, given the usual size the tab bar icons,
    // PNG comparison might be not that costly compared to JPG.
    //
    // It appears that none of these methods are ideal.
    // A benchmark could be useful to determine which one is the "less worse".

    private lazy var subtreeViewRecorder: ViewTreeRecorder = {
        ViewTreeRecorder(
            nodeRecorders: [
                UIImageViewRecorder(
                    tintColorProvider: { imageView in
                        guard let imageViewImage = imageView.image else { return nil }
                        //print("UIImageViewRecorder -- currentlyProcessedTabbar:", self.currentlyProcessedTabbar ?? "nil")
                        guard let tabBar = self.currentlyProcessedTabbar else { return imageView.tintColor }

                        // Access the selected item in the tabbar.
                        // Important note: our hypothesis is that each item uses a different image.

                        let currentItemInSelectedState = tabBar.items?.first {
                            //$0.image?.dd.srIdentifier == imageView.image?.dd.srIdentifier
                            let itemImage = $0.image
                            let itemSelectedImage = $0.selectedImage
                            //return itemImage?.pngData() == imageViewImage.pngData()
                            let sameImage = itemSelectedImage?.pngData() == imageViewImage.pngData()
                            return sameImage
                        }

                        // If item not selected, we return the unselectedItemTintColor,
                        // or the default gray color.
                        if currentItemInSelectedState == nil || tabBar.selectedItem != currentItemInSelectedState {
                            let unselectedColor = tabBar.unselectedItemTintColor ?? .lightGray.withAlphaComponent(0.5)
                            return tabBar.unselectedItemTintColor ?? .systemGray.withAlphaComponent(0.5)
                        }

                        // Otherwise we return the tabbar tint color,
                        // or the default blue color.
                        let selectedColor = tabBar.tintColor ?? UIColor.systemBlue
                        return tabBar.tintColor ?? UIColor.systemBlue
                    }/*,
                    shouldRecordImagePredicate: {_ in
                        return true
                    }*/
                )/*,
                UILabelRecorder()*/
            ]
        )
    }()

    /*init() {
        self.subtreeViewRecorder = {

        }()
    }*/

    func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) -> NodeSemantics? {
        guard let tabBar = view as? UITabBar else {
            return nil
        }

        //print("isVisible:", attributes.isVisible)
        currentlyProcessedTabbar = tabBar
        //print("semantics -- currentlyProcessedTabbar:", currentlyProcessedTabbar ?? "nil")

        let subtreeRecordingResults = subtreeViewRecorder.record(tabBar, in: context)
        let builder = UITabBarWireframesBuilder(
            wireframeRect: inferOccupiedFrame(of: tabBar, in: context),
            wireframeID: context.ids.nodeID(view: tabBar, nodeRecorder: self),
            attributes: attributes,
            color: inferColor(of: tabBar)
        )
        let node = Node(viewAttributes: attributes, wireframesBuilder: builder)

        let allNodes = subtreeRecordingResults.nodes + [node]
        print("allNodes:", allNodes.count)

        for node in allNodes {
            //print("node:", node.viewAttributes.frame)
        }
        //print(allNodes)
        return SpecificElement(subtreeStrategy: .record, nodes: allNodes)

        /*if let subtreeRecorder {
            print("subtree nodes:", subtreeRecorder.nodes.count)
            return SpecificElement(subtreeStrategy: .ignore, nodes: [node] + subtreeRecorder.nodes)
        } else {
            return SpecificElement(subtreeStrategy: .ignore, nodes: [node])
        }*/

    }

    private func inferOccupiedFrame(of tabBar: UITabBar, in context: ViewTreeRecordingContext) -> CGRect {
        var occupiedFrame = tabBar.frame
        for subview in tabBar.subviews {
            let subviewFrame = subview.convert(subview.bounds, to: context.coordinateSpace)
            occupiedFrame = occupiedFrame.union(subviewFrame)
        }
        print("Calculated occupied frame: \(occupiedFrame)")
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
        print("Building wireframes for UITabBar with rect: \(wireframeRect)")
        print("alpha:", attributes.alpha)

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
