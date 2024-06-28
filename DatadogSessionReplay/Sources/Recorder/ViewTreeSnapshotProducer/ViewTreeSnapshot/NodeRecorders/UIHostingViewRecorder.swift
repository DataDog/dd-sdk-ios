/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import Foundation
import UIKit

internal class UIHostingViewRecorder: NodeRecorder {
    let identifier = UUID()

    let _UIGraphicsViewClass: AnyClass? = NSClassFromString("SwiftUI._UIGraphicsView")

    init() { }

    func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) -> NodeSemantics? {
        // SwiftUI was introduced in iOS 13
        guard #available(iOS 13, *) else {
            return nil
        }

        let viewType = type(of: view)

        // `_UIGraphicsView` draw `SwiftUI` content from the display list,
        // these content will be recorded from the `_UIHostingView` instead
        if let cls = _UIGraphicsViewClass, viewType.isSubclass(of: cls) {
            return IgnoredElement(subtreeStrategy: .ignore)
        }

        // Quickly check for the `renderer` property in the view.
        // By doing so, we both validate the view type and we avoid
        // reflecting the view itself
        guard
            let ivar = class_getInstanceVariable(viewType, "renderer"),
            let value = object_getIvar(view, ivar)
        else {
            return nil
        }

        guard attributes.isVisible else {
            return InvisibleElement.constant
        }

        do {
            let renderer = try DisplayList.ViewRenderer(reflecting: value)

            let builder = UIHostingWireframesBuilder(
                hostID: context.ids.nodeID(view: view, nodeRecorder: self),
                attributes: attributes,
                renderer: renderer.renderer,
                textObfuscator: context.recorder.privacy.staticTextObfuscator
            )

            let node = Node(viewAttributes: attributes, wireframesBuilder: builder)
            return SpecificElement(subtreeStrategy: .record, nodes: [node])
        } catch {
            print(error) // TODO: RUM-5092 report telemetry

            let builder = UnsupportedViewWireframesBuilder(
                wireframeRect: view.frame,
                wireframeID: context.ids.nodeID(view: view, nodeRecorder: self),
                unsupportedClassName: "SwiftUI",
                attributes: attributes
            )
            let node = Node(viewAttributes: attributes, wireframesBuilder: builder)
            return SpecificElement(subtreeStrategy: .ignore, nodes: [node])
        }
    }
}

@available(iOS 13.0, *)
internal struct UIHostingWireframesBuilder: NodeWireframesBuilder {
    internal struct Referential {
        let frame: CGRect
    }

    /// ID of the `_UIHostingView`.
    let hostID: WireframeID
    /// Attributes of the `_UIHostingView`.
    let hostAttributes: ViewAttributes
    /// The SwiftUI reflected renderer
    let renderer: DisplayList.ViewUpdater
    /// Text obfuscator for masking text.
    let textObfuscator: TextObfuscating

    var wireframeRect: CGRect { hostAttributes.frame }

    init(
        hostID: WireframeID,
        attributes: ViewAttributes,
        renderer: DisplayList.ViewUpdater,
        textObfuscator: TextObfuscating
    ) {
        self.hostID = hostID
        self.hostAttributes = attributes
        self.renderer = renderer
        self.textObfuscator = textObfuscator
    }

    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] {
        let host = builder.createShapeWireframe(
            id: hostID,
            frame: wireframeRect,
            attributes: hostAttributes
        )

        guard let items = renderer.lastList.lazy?.items else {
            return [host]
        }

        // Traverse the SwiftUI tree and build wireframes
        return [host] + buildWireframes(
            items: items,
            referential: Referential(hostAttributes.frame),
            builder: builder
        )
    }

    private func buildWireframes(items: [DisplayList.Item], referential: Referential, builder: WireframesBuilder) -> [SRWireframe] {
        items.reduce([]) { wireframes, item in
            switch item.value {
            case let .effect(effect, list):
                return wireframes + effectWireframe(item: item, effect: effect, list: list, referential: referential, builder: builder)
            case .content(let content):
                return wireframes + contentWireframe(item: item, content: content, referential: referential, builder: builder)
            case .unknown:
                return wireframes
            }
        }
    }

    private func contentWireframe(item: DisplayList.Item, content: DisplayList.Content, referential: Referential, builder: WireframesBuilder) -> SRWireframe? {
        let info = renderer.viewCache.map[DisplayList.ViewUpdater.ViewCache.Key(id: DisplayList.Index.ID(identity: item.identity))]

        switch content.value {
        case let .text(view, _):
            let storage = view.text.storage
            let style = storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
            let foregroundColor = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
            let font = storage.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
            return builder.createTextWireframe(
                id: Int64(content.seed.value),
                frame: referential.convert(frame: item.frame),
                text: textObfuscator.mask(text: storage.string),
                textAlignment: style.map { .init(systemTextAlignment: $0.alignment) },
                textColor: foregroundColor?.cgColor,
                font: font,
                fontScalingEnabled: false
            )
        case let .shape(_, paint, _):
            // temporary solution to differentiate a border shape
            // from a content shape (icon):
            // - A border shape is linked to a view-info to draw borders
            // - A content shape draw a path on the hosting view layer directly
            return info.map { info in
                builder.createShapeWireframe(
                    id: Int64(content.seed.value),
                    frame: referential.convert(frame: item.frame),
                    borderColor: info.borderColor,
                    borderWidth: info.borderWidth,
                    backgroundColor: info.backgroundColor,
                    cornerRadius: info.cornerRadius,
                    opacity: info.alpha
                )
            } ?? builder.createShapeWireframe(
                id: Int64(content.seed.value),
                frame: referential.convert(frame: item.frame),
                backgroundColor: CGColor(
                    red: CGFloat(paint.paint.linearRed),
                    green: CGFloat(paint.paint.linearGreen),
                    blue: CGFloat(paint.paint.linearBlue),
                    alpha: CGFloat(paint.paint.opacity)
                ),
                opacity: CGFloat(paint.paint.opacity)
            )
        case .color:
            return builder.createShapeWireframe(
                id: Int64(content.seed.value),
                frame: referential.convert(frame: item.frame),
                borderColor: info?.borderColor,
                borderWidth: info?.borderWidth,
                backgroundColor: info?.backgroundColor,
                cornerRadius: info?.cornerRadius,
                opacity: info?.alpha
            )
        case .platformView:
            return nil // Should be recorded by UIKit recorder
        case .unknown:
            return nil // Need a placeholder
        }
    }

    private func contentWireframe(item: DisplayList.Item, content: DisplayList.Content, referential: Referential, builder: WireframesBuilder) -> [SRWireframe] {
        contentWireframe(item: item, content: content, referential: referential, builder: builder).map { [$0] } ?? []
    }

    private func effectWireframe(item: DisplayList.Item, effect: DisplayList.Effect, list: DisplayList, referential: Referential, builder: WireframesBuilder) -> [SRWireframe] {
        buildWireframes(
            items: list.items,
            referential: Referential(convert: item.frame, to: referential),
            builder: builder
        )
    }
}

@available(iOS 13.0, *)
extension UIHostingWireframesBuilder.Referential {
    init(_ frame: CGRect) {
        self.frame = frame
    }

    init(convert frame: CGRect, to referential: Self) {
        self.frame = referential.convert(frame: frame)
    }

    func convert(frame: CGRect) -> CGRect {
        frame.offsetBy(
            dx: self.frame.origin.x,
            dy: self.frame.origin.y
        )
    }
}

#endif
