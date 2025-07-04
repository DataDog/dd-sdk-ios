/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import Foundation
import UIKit
import DatadogInternal

@available(iOS 13.0, *)
internal struct SwiftUIWireframesBuilder: NodeWireframesBuilder {
    internal struct Context {
        var frame: CGRect
        var clip: CGRect
        let builder: WireframesBuilder
    }

    let wireframeID: WireframeID
    let renderer: DisplayList.ViewUpdater
    /// Text obfuscator for masking text.
    let textObfuscator: TextObfuscating
    /// Flag that determines if font should be scaled.
    let fontScalingEnabled: Bool
    /// Privacy level for masking images.
    let imagePrivacyLevel: ImagePrivacyLevel
    /// The Hosting view attributes.
    let attributes: ViewAttributes

    var wireframeRect: CGRect {
        attributes.frame
    }

    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] {
        let root = builder.createShapeWireframe(id: wireframeID, attributes: attributes)
        do {
            let list = try renderer.lastList.reflect()
            let context = Context(
                frame: attributes.frame,
                clip: attributes.clip,
                builder: builder
            )

            return [root] + buildWireframes(items: list.items, context: context)
        } catch {
            return [root]
        }
    }

    private func buildWireframes(items: [DisplayList.Item], context: Context) -> [SRWireframe] {
        items.reduce([]) { wireframes, item in
            switch item.value {
            case let .effect(effect, list):
                return wireframes + effectWireframe(item: item, effect: effect, list: list, context: context)
            case .content(let content):
                return wireframes + contentWireframe(item: item, content: content, context: context)
            case .unknown:
                return wireframes
            }
        }
    }

    private func effectWireframe(item: DisplayList.Item, effect: DisplayList.Effect, list: DisplayList, context: Context) -> [SRWireframe] {
        var context = context
        context.frame = context.convert(frame: item.frame)

        switch effect {
        case let .clip(path, _):
            let clip = context.convert(frame: path.boundingRect)
            context.clip = context.clip.intersection(clip)

        case .platformGroup:
            if let viewInfo = renderer.viewCache.map[.init(id: .init(identity: item.identity))] {
                context.convert(to: viewInfo.frame)
            }

        case .identify, .unknown:
            break
        }

        return buildWireframes(items: list.items, context: context)
    }

    private func contentWireframe(item: DisplayList.Item, content: DisplayList.Content, context: Context) -> [SRWireframe] {
        contentWireframe(item: item, content: content, context: context).map { [$0] } ?? []
    }

    private func contentWireframe(item: DisplayList.Item, content: DisplayList.Content, context: Context) -> SRWireframe? {
        let viewInfo = renderer.viewCache.map[.init(id: .init(identity: item.identity))]

        var generator = XoshiroRandomNumberGenerator(seed: content.seed.value)
        let id: Int64 = .positiveRandom(using: &generator)

        switch content.value {
        case let .shape(_, paint, _):
            return paint.paint.map { paint in
                context.builder.createShapeWireframe(
                    id: id,
                    frame: context.convert(frame: item.frame),
                    clip: context.clip,
                    backgroundColor: CGColor(
                        red: CGFloat(paint.linearRed),
                        green: CGFloat(paint.linearGreen),
                        blue: CGFloat(paint.linearBlue),
                        alpha: CGFloat(paint.opacity)
                    ),
                    cornerRadius: viewInfo?.cornerRadius,
                    opacity: CGFloat(paint.opacity)
                )
            }
        case let .text(view, _):
            let storage = view.text.storage
            let style = storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
            let foregroundColor = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
            let font = storage.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
            return context.builder.createTextWireframe(
                id: id,
                frame: context.convert(frame: item.frame),
                clip: context.clip,
                text: textObfuscator.mask(text: storage.string),
                textAlignment: style.map { .init(systemTextAlignment: $0.alignment) },
                textColor: foregroundColor?.cgColor,
                font: font,
                fontScalingEnabled: fontScalingEnabled
            )
        case .color:
            return context.builder.createShapeWireframe(
                id: id,
                frame: context.convert(frame: item.frame),
                clip: context.clip,
                borderColor: viewInfo?.borderColor,
                borderWidth: viewInfo?.borderWidth,
                backgroundColor: viewInfo?.backgroundColor,
                cornerRadius: viewInfo?.cornerRadius,
                opacity: viewInfo?.alpha
            )
        case let .image(resolvedImage):
            switch resolvedImage.contents {
            case .cgImage(let cgImage):
                let shouldRecordImage = self.imagePrivacyLevel.shouldRecordGraphicsImagePredicate(resolvedImage)
                if shouldRecordImage {
                    let imageResource = UIImageResource(
                        image: UIImage(
                            cgImage: cgImage,
                            scale: resolvedImage.scale,
                            orientation: .init(resolvedImage.orientation)
                        ),
                        tintColor: nil
                    )
                    return context.builder.createImageWireframe(
                        id: id,
                        resource: imageResource,
                        frame: context.convert(frame: item.frame),
                        clip: context.clip
                    )
                } else {
                    return context.builder.createPlaceholderWireframe(
                        id: id,
                        frame: context.convert(frame: item.frame),
                        clip: context.clip,
                        label: imagePrivacyLevel == .maskNonBundledOnly ? "Content Image" : "Image"
                    )
                }
            case .unknown:
                return context.builder.createPlaceholderWireframe(
                    id: id,
                    frame: context.convert(frame: item.frame),
                    clip: context.clip,
                    label: "Unsupported image type"
                )
            }

        case .platformView:
            return nil // Should be recorder by UIKit recorder
        case let .toolbarItem(text):
            return context.builder.createTextWireframe(
                id: id,
                frame: context.convert(frame: item.frame),
                clip: context.clip,
                text: textObfuscator.mask(text: text),
                textAlignment: .init(systemTextAlignment: .center),
                textColor: SystemColors.label,
                font: .systemFont(ofSize: 17),
                fontScalingEnabled: fontScalingEnabled
            )
        case .unknown:
            return context.builder.createPlaceholderWireframe(
                id: id,
                frame: context.convert(frame: item.frame),
                clip: context.clip,
                label: "Unsupported SwiftUI component"
            )
        }
    }
}

@available(iOS 13.0, *)
internal extension SwiftUIWireframesBuilder.Context {
    func convert(frame: CGRect) -> CGRect {
        frame.offsetBy(
            dx: self.frame.minX,
            dy: self.frame.minY
        )
    }

    mutating func convert(to frame: CGRect) {
        self.frame = self.frame.offsetBy(
            dx: frame.minX,
            dy: frame.minY
        )
    }
}

@available(iOS 13.0, *)
internal extension ImagePrivacyLevel {
    var shouldRecordGraphicsImagePredicate: (_ graphicImage: GraphicsImage) -> Bool {
        switch self {
        case .maskNone: return { _ in true }
        case .maskNonBundledOnly:
            return { graphicImage in
                switch graphicImage.contents {
                case .cgImage(let cgImage):
                    return cgImage.isLikelyBundled(scale: graphicImage.scale)
                case .unknown:
                    return false
                }
            }
        case .maskAll:
            return { _ in false }
        }
    }
}

#endif
