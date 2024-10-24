/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit

internal struct UIDatePickerRecorder: NodeRecorder {
    internal let identifier: UUID

    private let wheelsStyleRecorder: WheelsStyleDatePickerRecorder
    private let compactStyleRecorder: CompactStyleDatePickerRecorder
    private let inlineStyleRecorder: InlineStyleDatePickerRecorder

    init(identifier: UUID) {
        self.identifier = identifier
        self.wheelsStyleRecorder = WheelsStyleDatePickerRecorder(identifier: UUID())
        self.compactStyleRecorder = CompactStyleDatePickerRecorder(identifier: UUID())
        self.inlineStyleRecorder = InlineStyleDatePickerRecorder(identifier: UUID())
    }

    func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) -> NodeSemantics? {
        guard let datePicker = view as? UIDatePicker else {
            return nil
        }

        guard attributes.isVisible else {
            return InvisibleElement.constant
        }

        var nodes: [Node]?
        if #available(iOS 13.4, *) {
            switch datePicker.datePickerStyle {
            case .wheels:
                nodes = wheelsStyleRecorder.record(datePicker, with: attributes, in: context)
            case .compact:
                nodes = compactStyleRecorder.record(datePicker, with: attributes, in: context)
            case .inline:
                nodes = inlineStyleRecorder.record(datePicker, with: attributes, in: context)
            case .automatic:
                // According to `datePicker.datePickerStyle` documentation:
                // > "This property always returns a concrete style, never `UIDatePickerStyle.automatic`."
                break
            @unknown default:
                nodes = wheelsStyleRecorder.record(datePicker, with: attributes, in: context)
            }
        } else {
            // Observation: older OS versions use the "wheels" style
            nodes = wheelsStyleRecorder.record(datePicker, with: attributes, in: context)
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
            backgroundWireframeID: context.ids.nodeID(view: datePicker, nodeRecorder: self),
            isDisplayedInPopover: isDisplayedInPopover
        )
        let backgroundNode = Node(
            viewAttributes: attributes,
            wireframesBuilder: builder
        )
        return SpecificElement(
            subtreeStrategy: .ignore,
            nodes: [backgroundNode] + (nodes ?? [])
        )
    }
}

private struct WheelsStyleDatePickerRecorder {
    private let pickerTreeRecorder: ViewTreeRecorder

    init(identifier: UUID) {
        self.pickerTreeRecorder = ViewTreeRecorder(
            nodeRecorders: [
                UIPickerViewRecorder(
                    identifier: identifier,
                    textObfuscator: { context, viewAttributes in
                        return viewAttributes.resolveTextAndInputPrivacyLevel(in: context).staticTextObfuscator
                    }
                )
            ]
        )
    }

    func record(_ view: UIView, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) -> [Node] {
        return pickerTreeRecorder.record(view, in: context)
    }
}

private struct InlineStyleDatePickerRecorder {
    let viewRecorder: UIViewRecorder
    let labelRecorder: UILabelRecorder
    let subtreeRecorder: ViewTreeRecorder

    init(identifier: UUID) {
        self.viewRecorder = UIViewRecorder(identifier: UUID())
        self.labelRecorder = UILabelRecorder(
            identifier: UUID(),
            textObfuscator: { context, viewAttributes in
                return viewAttributes.resolveTextAndInputPrivacyLevel(in: context).staticTextObfuscator
            }
        )
        self.subtreeRecorder = ViewTreeRecorder(
            nodeRecorders: [
                viewRecorder,
                labelRecorder,
                UIImageViewRecorder(identifier: UUID()),
                UISegmentRecorder(identifier: UUID()), // iOS 14.x uses `UISegmentedControl` for "AM | PM"
            ]
        )
    }

    func record(_ view: UIView, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) -> [Node] {
        viewRecorder.semanticsOverride = { _, viewAttributes in
            if context.recorder.textAndInputPrivacy.shouldMaskInputElements {
                let isSquare = viewAttributes.frame.width == viewAttributes.frame.height
                let isCircle = isSquare && viewAttributes.layerCornerRadius == viewAttributes.frame.width * 0.5
                if isCircle {
                    return IgnoredElement(subtreeStrategy: .ignore)
                }
            }
            return nil
        }

        if context.recorder.textAndInputPrivacy.shouldMaskInputElements {
            labelRecorder.builderOverride = { builder in
                var builder = builder
                builder.textColor = SystemColors.label
                return builder
            }
        }

        return subtreeRecorder.record(view, in: context)
    }
}

private struct CompactStyleDatePickerRecorder {
    let subtreeRecorder: ViewTreeRecorder

    init(identifier: UUID) {
        self.subtreeRecorder = ViewTreeRecorder(
            nodeRecorders: [
                UIViewRecorder(identifier: UUID()),
                UILabelRecorder(
                    identifier: UUID(),
                    textObfuscator: { context, viewAttributes in
                        return viewAttributes.resolveTextAndInputPrivacyLevel(in: context).staticTextObfuscator
                    }
                )
            ]
        )
    }

    func record(_ view: UIView, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) -> [Node] {
        return subtreeRecorder.record(view, in: context)
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
                clip: attributes.clip,
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
