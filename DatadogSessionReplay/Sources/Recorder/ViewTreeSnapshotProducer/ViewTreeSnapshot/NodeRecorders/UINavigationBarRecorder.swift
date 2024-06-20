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
        // Images (Icons)
        static let defaultIconTintColor = SystemColors.systemBlue
        // Texts
        static let defaultTitleFontColor = UIColor.black
        static let defaultTitleFontColorInBlackMode = UIColor.white
        static let defaultItemFontColor = SystemColors.systemBlue
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
        let subtreeRecordingResults = recordSubtree(of: navigationBar, in: context)
        let allNodes = [node] + subtreeRecordingResults.nodes
        let resources = subtreeRecordingResults.resources

        return SpecificElement(subtreeStrategy: .ignore, nodes: allNodes, resources: resources)
    }

    private func inferOccupiedFrame(of navigationBar: UINavigationBar, in context: ViewTreeRecordingContext) -> CGRect {
        var occupiedFrame = navigationBar.frame
        for subview in navigationBar.subviews {
            let subviewFrame = subview.convert(subview.bounds, to: context.coordinateSpace)
            occupiedFrame = occupiedFrame.union(subviewFrame)
        }
        return occupiedFrame
    }

    private func recordSubtree(of navBar: UINavigationBar, in context: ViewTreeRecordingContext) -> RecordingResult {
        var imageViewRecorder = UIImageViewRecorder(
            tintColorProvider: { imageView in
                imageView.tintColor ?? Constants.defaultIconTintColor
            }
        )
        imageViewRecorder.builderOverride = { builder in
            var builder = builder
            builder.backgroundColor = UIColor.clear.cgColor //self.inferBackgroundColor(of: navBar)
            return builder
        }

        let subtreeViewRecorder = ViewTreeRecorder(
            nodeRecorders: [
                // This is to record the items' icon color (eg. `＋` icon).
                imageViewRecorder,
                // This is to record the items' text color (eg. "Back").
                UILabelRecorder(
                    builderOverride: { builder in
                        var builder = builder
                        builder.textColor = Constants.defaultTitleFontColor.cgColor

                        guard let items = navBar.items else {
                            return builder
                        }

                        for item in items {
                            if self.updateBuilderTextColor(for: item, in: navBar, using: &builder) {
                                return builder
                            }
                        }

                        return builder
                    }
                )
            ]
        )

        return subtreeViewRecorder.record(navBar, in: context)
    }

    // MARK: Text Color
    private func updateBuilderTextColor(for item: UINavigationItem, in navBar: UINavigationBar, using builder: inout UILabelWireframesBuilder) -> Bool {
        if let title = item.title, title == builder.text {
            // Back item
            if let backItemTitle = navBar.backItem?.title,
               backItemTitle == title {
                builder.textColor = navBar.backItem?.titleView?.tintColor.cgColor ?? Constants.defaultItemFontColor.cgColor
                return true
            }

            // Title
            updateTitleTextColor(in: navBar, using: &builder)
            return true
        }

        // Left items
        if updateBarButtonItemsTextColor(for: item.leftBarButtonItems, using: &builder) {
            return true
        }

        // Right items
        if updateBarButtonItemsTextColor(for: item.rightBarButtonItems, using: &builder) {
            return true
        }

        return false
    }

    private func updateTitleTextColor(in navBar: UINavigationBar, using builder: inout UILabelWireframesBuilder) {
        if let attributes = navBar.titleTextAttributes,
           let color = attributes[NSAttributedString.Key.foregroundColor] as? UIColor {
            builder.textColor = color.cgColor
        } else {
            builder.textColor = (navBar.barStyle == .black) ? Constants.defaultTitleFontColorInBlackMode.cgColor : Constants.defaultTitleFontColor.cgColor
        }
    }

    private func updateBarButtonItemsTextColor(for items: [UIBarButtonItem]?, using builder: inout UILabelWireframesBuilder) -> Bool {
        guard let items else {
            return false
        }

        for item in items {
            if let title = item.title, title == builder.text {
                builder.textColor = item.tintColor?.cgColor ?? Constants.defaultItemFontColor.cgColor
                return true
            }
        }

        return false
    }

    // MARK: Background color
    private func inferBackgroundColor(of navigationBar: UINavigationBar) -> CGColor {
        if let color = navigationBar.backgroundColor {
            return colorWithAlphaAdjustment(color, for: navigationBar.isTranslucent)
        // ignore tint color because only visible when scrolled
        /*} else if let barTintColor = navigationBar.barTintColor {
            return colorWithAlphaAdjustment(barTintColor, for: navigationBar.isTranslucent)*/
        // ignore black style?
        /*} else if navigationBar.barStyle == .black {
            return inferBlackBarColor(of: navigationBar)*/
        }

        return defaultColor()
    }

    private func colorWithAlphaAdjustment(_ color: UIColor, for isTranslucent: Bool) -> CGColor {
        guard color != UIColor.clear else {
            return color.cgColor
        }
        return isTranslucent ? color.withAlphaComponent(0.8).cgColor : color.cgColor
    }

    private func inferBlackBarColor(of navigationBar: UINavigationBar) -> CGColor {
        let backgroundColor = navigationBar.barTintColor ?? UIColor.black
        return colorWithAlphaAdjustment(backgroundColor, for: navigationBar.isTranslucent)
    }

    private func defaultColor() -> CGColor {
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
                borderWidth: 1,
                backgroundColor: color,
                cornerRadius: attributes.layerCornerRadius,
                opacity: attributes.alpha
            )
        ]
    }
}
#endif
