/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2023-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
import UIKit

@_spi(Internal) public enum SessionReplayElement {
    case specificElement (subtreeStrategy: SessionReplayNodeSubtreeStrategy, attributes: SessionReplayViewAttributes, builder: GenericTextWireframesBuilder)
    case invisibleElement
}

@_spi(Internal) open class CustomNodeRecorder: NodeRecorder {
    public let identifier = UUID()
    
    public init () {}

    internal func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) -> NodeSemantics? {
        let element = getSessionReplayElement(view: view, attributes: attributes, context: context)
        switch element {
        case .invisibleElement:
            return InvisibleElement.constant
        case .none:
            return nil
        case .specificElement(let subtreeStrategy, let attributes, let builder):
            let nodes = [
                Node(viewAttributes: attributes, wireframesBuilder: builder)
            ]
            return SpecificElement(subtreeStrategy: subtreeStrategy, nodes: nodes)
        }
    }

    // will be overriden with actual implementation
    open func getSessionReplayElement(
        view: UIView,
        attributes: SessionReplayViewAttributes,
        context: SessionReplayViewTreeRecordingContext
    ) -> SessionReplayElement? {
        return nil
    }
}

@_spi(Internal) public struct GenericTextWireframesBuilder: NodeWireframesBuilder {
    public let id: NodeIDGenerator
    public let frame: CGRect
    public let text: String
    public let textAlignment: TextAlignment
    public let clip: SessionReplayContentClip
    public let textColor: CGColor?
    public let font: UIFont
    public let fontScalingEnabled: Bool
    public let borderColor: CGColor?
    public let borderWidth: CGFloat?
    public let backgroundColor: CGColor?
    public let cornerRadius: CGFloat?
    public let opacity: CGFloat?
    public let view: UIView
    public let nodeRecorder: CustomNodeRecorder
    
    public let wireframeRect: CGRect
    
    public init(id: NodeIDGenerator, frame: CGRect, text: String, textAlignment: TextAlignment, clip: SessionReplayContentClip, textColor: CGColor?, font: UIFont, fontScalingEnabled: Bool, borderColor: CGColor?, borderWidth: CGFloat?, backgroundColor: CGColor?, cornerRadius: CGFloat?, opacity: CGFloat?, view: UIView, nodeRecorder: CustomNodeRecorder, wireframeRect: CGRect) {
        self.id = id
        self.frame = frame
        self.text = text
        self.textAlignment = textAlignment
        self.clip = clip
        self.textColor = textColor
        self.font = font
        self.fontScalingEnabled = fontScalingEnabled
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.backgroundColor = backgroundColor
        self.cornerRadius = cornerRadius
        self.opacity = opacity
        self.view = view
        self.nodeRecorder = nodeRecorder
        self.wireframeRect = wireframeRect
    }

    internal func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] {
        return [
            builder.createTextWireframe(
                id: id.nodeID(view: view, nodeRecorder: nodeRecorder),
                frame: frame,
                text: text,
                textAlignment: textAlignment.toSRAlignment(),
                clip: .init(bottom: clip.bottom, left: clip.left, right: clip.right, top: clip.top),
                textColor: textColor,
                font: font,
                borderColor: borderColor,
                borderWidth: borderWidth,
                backgroundColor: backgroundColor,
                cornerRadius: cornerRadius,
                opacity: opacity
            )
        ]
    }

    public struct SessionReplayContentClip {
        /// The amount of space in pixels that needs to be clipped (masked) at the bottom of the wireframe.
        public let bottom: Int64?
        
        /// The amount of space in pixels that needs to be clipped (masked) at the left of the wireframe.
        public let left: Int64?
        
        /// The amount of space in pixels that needs to be clipped (masked) at the right of the wireframe.
        public let right: Int64?
        
        /// The amount of space in pixels that needs to be clipped (masked) at the top of the wireframe.
        public let top: Int64?
        
        public init(bottom: Int64?, left: Int64?, right: Int64?, top: Int64?) {
            self.bottom = bottom
            self.left = left
            self.right = right
            self.top = top
        }
    }

    public struct TextAlignment {
        public enum VerticalTextAlignment: String {
            case top = "top"
            case bottom = "bottom"
            case center = "center"
        }
        
        public let textAlignment: NSTextAlignment
        public let verticalTextAlignment: VerticalTextAlignment
        
        public init(textAlignment: NSTextAlignment, verticalTextAlignment: VerticalTextAlignment) {
            self.textAlignment = textAlignment
            self.verticalTextAlignment = verticalTextAlignment
        }
        
        internal func toSRAlignment() -> SRTextPosition.Alignment {
            switch verticalTextAlignment {
            case .top:
                return .init(systemTextAlignment: textAlignment, vertical: .top)
            case .bottom:
                return .init(systemTextAlignment: textAlignment, vertical: .bottom)
            case .center:
                return .init(systemTextAlignment: textAlignment, vertical: .center)
            }
        }
    }
}


