/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit

internal struct UISegmentRecorder: NodeRecorder {
    let identifier = UUID()
    var textObfuscator: (ViewTreeRecordingContext) -> TextObfuscating = { context in
        return context.recorder.privacy.inputAndOptionTextObfuscator
    }

    func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) -> NodeSemantics? {
        guard let segment = view as? UISegmentedControl else {
            return nil
        }

        guard attributes.isVisible else {
            return InvisibleElement.constant
        }

        let ids = context.ids.nodeIDs(1 + segment.numberOfSegments, view: segment, nodeRecorder: self)

        let builder = UISegmentWireframesBuilder(
            wireframeRect: attributes.frame,
            attributes: attributes,
            textObfuscator: textObfuscator(context),
            backgroundWireframeID: ids[0],
            segmentWireframeIDs: Array(ids[1..<ids.count]),
            segmentTitles: (0..<segment.numberOfSegments).map { segment.titleForSegment(at: $0) },
            selectedSegmentIndex: context.recorder.privacy.shouldMaskInputElements ? nil : segment.selectedSegmentIndex,
            selectedSegmentTintColor: {
                if #available(iOS 13.0, *) {
                    return segment.selectedSegmentTintColor
                } else {
                    return nil
                }
            }()
        )
        let node = Node(viewAttributes: attributes, wireframesBuilder: builder)
        return SpecificElement(subtreeStrategy: .ignore, nodes: [node])
    }
}

internal struct UISegmentWireframesBuilder: NodeWireframesBuilder {
    private enum Defaults {
        static let segmentFont: UIFont = .systemFont(ofSize: 14)
    }

    var wireframeRect: CGRect
    let attributes: ViewAttributes
    let textObfuscator: TextObfuscating

    let backgroundWireframeID: WireframeID
    let segmentWireframeIDs: [WireframeID]
    let segmentTitles: [String?]
    /// The index of selected segment or `nil` if privacy masking is applied.
    let selectedSegmentIndex: Int?
    let selectedSegmentTintColor: UIColor?

    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] {
        let numberOfSegments = segmentWireframeIDs.count
        guard numberOfSegments > 0, segmentTitles.count == numberOfSegments, (selectedSegmentIndex ?? 0) < numberOfSegments else {
            return [] // illegal, should not happen
        }

        // Create background wireframe:
        let background = builder.createShapeWireframe(
            id: backgroundWireframeID,
            frame: wireframeRect,
            borderColor: nil,
            borderWidth: nil,
            backgroundColor: attributes.backgroundColor ?? SystemColors.tertiarySystemFill,
            cornerRadius: 8,
            opacity: attributes.alpha
        )

        // Create segment wireframes:
        let segmentSize = CGSize(
            width: wireframeRect.width / CGFloat(numberOfSegments),
            height: wireframeRect.height * 0.96
        )

        var segmentRects: [CGRect] = [] // rects for succeeding segments
        var dividedRect = wireframeRect
        for _ in (0..<numberOfSegments) {
            let division = dividedRect.divided(atDistance: segmentSize.width, from: .minXEdge)
            let segmentRect = division.slice.insetBy(dx: 2, dy: 2)
            dividedRect = division.remainder

            segmentRects.append(segmentRect)
        }

        let segments: [SRWireframe] = (0..<numberOfSegments).map { idx in
            let isSelected = idx == selectedSegmentIndex
            return builder.createTextWireframe(
                id: segmentWireframeIDs[idx],
                frame: segmentRects[idx],
                text: textObfuscator.mask(text: segmentTitles[idx] ?? ""),
                textFrame: segmentRects[idx],
                textAlignment: .init(horizontal: .center, vertical: .center),
                textColor: SystemColors.label,
                font: Defaults.segmentFont,
                borderColor: isSelected ? SystemColors.secondarySystemFill : SystemColors.clear,
                borderWidth: 1,
                backgroundColor: isSelected ? (selectedSegmentTintColor?.cgColor ?? SystemColors.tertiarySystemBackground) : SystemColors.clear,
                cornerRadius: 8,
                opacity: attributes.alpha
            )
        }

        return [background] + segments
    }
}
#endif
