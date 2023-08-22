/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit

internal struct UIDatePickerRecorder: NodeRecorder {
    private let wheelsStyleRecorder = WheelsStyleDatePickerRecorder()
    private let compactStyleRecorder = CompactStyleDatePickerRecorder()
    private let inlineStyleRecorder = InlineStyleDatePickerRecorder()

    func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) -> NodeSemantics? {
        guard let datePicker = view as? UIDatePicker else {
            return nil
        }

        guard attributes.isVisible else {
            return InvisibleElement.constant
        }

        var nodes: [Node] = []

        if #available(iOS 13.4, *) {
            switch datePicker.datePickerStyle {
            case .wheels:
                nodes = wheelsStyleRecorder.recordNodes(of: datePicker, with: attributes, in: context)
            case .compact:
                nodes = compactStyleRecorder.recordNodes(of: datePicker, with: attributes, in: context)
            case .inline:
                nodes = inlineStyleRecorder.recordNodes(of: datePicker, with: attributes, in: context)
            case .automatic:
                // According to `datePicker.datePickerStyle` documentation:
                // > "This property always returns a concrete style, never `UIDatePickerStyle.automatic`."
                break
            @unknown default:
                nodes = wheelsStyleRecorder.recordNodes(of: datePicker, with: attributes, in: context)
            }
        } else {
            // Observation: older OS versions use the "wheels" style
            nodes = wheelsStyleRecorder.recordNodes(of: datePicker, with: attributes, in: context)
        }

        let isDisplayedInPopover: Bool = {
            if let superview = view.superview {
                // This gets effective on iOS 15.0+ which is the earliest version that displays
                // date pickers in popover views:
                return "\(type(of: superview))" == "_UIVisualEffectContentView"
            }
            return false
        }()

        let builder = UIDatePickerWireframesBuilder(
            wireframeRect: attributes.frame,
            attributes: attributes,
            backgroundWireframeID: context.ids.nodeID(for: datePicker),
            isDisplayedInPopover: isDisplayedInPopover
        )
        let backgroundNode = Node(
            viewAttributes: attributes,
            wireframesBuilder: builder
        )
        return SpecificElement(
            subtreeStrategy: .ignore,
            nodes: [backgroundNode] + nodes
        )
    }
}

private struct WheelsStyleDatePickerRecorder {
    let pickerTreeRecorder = ViewTreeRecorder(
        nodeRecorders: [
            UIPickerViewRecorder(
                textObfuscator: { context in
                    return context.recorder.privacy.staticTextObfuscator
                }
            )
        ]
    )

    func recordNodes(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) -> [Node] {
        return pickerTreeRecorder.recordNodes(for: view, in: context)
    }
}

private struct InlineStyleDatePickerRecorder {
    let viewRecorder: UIViewRecorder
    let labelRecorder: UILabelRecorder
    let subtreeRecorder: ViewTreeRecorder

    init() {
        self.viewRecorder = UIViewRecorder()
        self.labelRecorder = UILabelRecorder(
            textObfuscator: { context in
                return context.recorder.privacy.staticTextObfuscator
            }
        )
        self.subtreeRecorder = ViewTreeRecorder(
            nodeRecorders: [
                viewRecorder,
                labelRecorder,
                UIImageViewRecorder(),
                UISegmentRecorder(), // iOS 14.x uses `UISegmentedControl` for "AM | PM"
            ]
        )
    }

    func recordNodes(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) -> [Node] {
        viewRecorder.semanticsOverride = { _, viewAttributes in
            if context.recorder.privacy.shouldMaskInputElements {
                let isSquare = viewAttributes.frame.width == viewAttributes.frame.height
                let isCircle = isSquare && viewAttributes.layerCornerRadius == viewAttributes.frame.width * 0.5
                if isCircle {
                    return IgnoredElement(subtreeStrategy: .ignore)
                }
            }
            return nil
        }

        if context.recorder.privacy.shouldMaskInputElements {
            labelRecorder.builderOverride = { builder in
                var builder = builder
                builder.textColor = SystemColors.label
                return builder
            }
        }

        return subtreeRecorder.recordNodes(for: view, in: context)
    }
}

private struct CompactStyleDatePickerRecorder {
    let subtreeRecorder = ViewTreeRecorder(
        nodeRecorders: [
            UIViewRecorder(),
            UILabelRecorder(
                textObfuscator: { context in
                    return context.recorder.privacy.staticTextObfuscator
                }
            )
        ]
    )

    func recordNodes(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) -> [Node] {
        return subtreeRecorder.recordNodes(for: view, in: context)
    }
}

internal struct UIDatePickerWireframesBuilder: NodeWireframesBuilder {
    var wireframeRect: CGRect
    let attributes: ViewAttributes
    let backgroundWireframeID: WireframeID
    /// If date picker is displayed in popover view (possible only in iOS 15.0+).
    let isDisplayedInPopover: Bool

    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] {
        return [
            builder.createShapeWireframe(
                id: backgroundWireframeID,
                frame: wireframeRect,
                clip: nil,
                borderColor: isDisplayedInPopover ? SystemColors.secondarySystemFill : nil,
                borderWidth: isDisplayedInPopover ? 1 : 0,
                backgroundColor: isDisplayedInPopover ? SystemColors.secondarySystemGroupedBackground : SystemColors.systemBackground,
                cornerRadius: 10,
                opacity: attributes.alpha
            )
        ]
    }
}
#endif
