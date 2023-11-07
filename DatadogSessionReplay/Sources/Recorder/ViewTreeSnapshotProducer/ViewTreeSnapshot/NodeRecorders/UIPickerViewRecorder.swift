/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit

/// Records `UIPickerView` nodes.
///
/// The look of picker view in SR is approximated by capturing the text from "selected row" and ignoring all other values on the wheel:
/// - If the picker defines multiple components, there will be multiple selected values.
/// - We can't request `picker.dataSource` to receive the value - doing so will result in calling applicaiton code, which could be
/// dangerous (if the code is faulty) and may significantly slow down the performance (e.g. if the underlying source requires database fetch).
/// - Similarly, we don't call `picker.delegate` to avoid running application code outside `UIKit's` lifecycle.
/// - Instead, we infer the value by traversing picker's subtree and finding texts that have no "3D wheel" effect applied.
/// - If privacy mode is elevated, we don't replace individual characters with "x" letter - instead we change whole options to fixed-width mask value.
internal struct UIPickerViewRecorder: NodeRecorder {
    let identifier = UUID()
    /// Records all shapes in picker's subtree.
    /// It is used to capture the background of selected option.
    private let selectionRecorder: ViewTreeRecorder
    /// Records all labels in picker's subtree.
    /// It is used to capture titles for displayed options.
    private let labelsRecorder: ViewTreeRecorder

    init(
        textObfuscator: @escaping (ViewTreeRecordingContext) -> TextObfuscating = { context in
            return context.recorder.privacy.inputAndOptionTextObfuscator
        }
    ) {
        self.selectionRecorder = ViewTreeRecorder(nodeRecorders: [UIViewRecorder()])
        self.labelsRecorder = ViewTreeRecorder(
            nodeRecorders: [
                UIViewRecorder(
                    semanticsOverride: { view, attributes in
                        if #available(iOS 13.0, *) {
                            if !attributes.isVisible || attributes.alpha < 1 || !CATransform3DIsIdentity(view.transform3D) {
                                // If this view has any 3D effect applied, do not enter its subtree:
                                return IgnoredElement(subtreeStrategy: .ignore)
                            }
                        }
                        // Otherwise, enter the subtree of this element, but do not consider it significant (`InvisibleElement`):
                        return InvisibleElement(subtreeStrategy: .record)
                    }
                ),
                UILabelRecorder(
                    builderOverride: { builder in
                        var builder = builder
                        builder.textAlignment = .center
                        builder.fontScalingEnabled = true
                        return builder
                    },
                    textObfuscator: textObfuscator // inherit label's obfuscation strategy from picker
                )
            ]
        )
    }

    func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) -> NodeSemantics? {
        guard let picker = view as? UIPickerView else {
            return nil
        }

        guard attributes.isVisible else {
            return InvisibleElement.constant
        }

        // For our "approximation", we render selected option text on top of selection background. However,
        // in the actual `UIPickerView's` tree their order is opposite (blending is used to make the label
        // pass through the shape). For that reason, we record both kinds of nodes separately and then reorder
        // them in returned semantics:
        let (backgroundNodes, backgroundResources) = selectionRecorder.recordNodes(for: picker, in: context)
        let (titleNodes, titleResources) = labelsRecorder.recordNodes(for: picker, in: context)

        guard attributes.hasAnyAppearance else {
            // If the root view of `UIPickerView` defines no other appearance (e.g. no custom `.background`), we can
            // safely ignore it, with only forwarding child nodes to final recording.
            return SpecificElement(
                subtreeStrategy: .ignore,
                nodes: backgroundNodes + titleNodes,
                resources: backgroundResources + titleResources
            )
        }

        // Otherwise, we build dedicated wireframes to describe extra appearance coming from picker's root `UIView`:
        let builder = UIPickerViewWireframesBuilder(
            wireframeRect: attributes.frame,
            attributes: attributes,
            backgroundWireframeID: context.ids.nodeID(view: picker, nodeRecorder: self)
        )
        let node = Node(viewAttributes: attributes, wireframesBuilder: builder)
        return SpecificElement(
            subtreeStrategy: .ignore, nodes: [node] + backgroundNodes + titleNodes,
            resources: backgroundResources + titleResources
        )
    }
}

internal struct UIPickerViewWireframesBuilder: NodeWireframesBuilder {
    var wireframeRect: CGRect
    let attributes: ViewAttributes
    let backgroundWireframeID: WireframeID

    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] {
        return [
            builder.createShapeWireframe(id: backgroundWireframeID, frame: wireframeRect, attributes: attributes)
        ]
    }
}
#endif
