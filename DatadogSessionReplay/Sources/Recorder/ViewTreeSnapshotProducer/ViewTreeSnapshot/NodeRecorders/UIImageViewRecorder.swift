/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit

internal struct UIImageViewRecorder: NodeRecorder {
    internal let identifier = UUID()

    private let tintColorProvider: (UIImageView) -> UIColor?
    private let shouldRecordImagePredicate: (UIImageView) -> Bool
    /// An option for overriding default semantics from parent recorder.
    var semanticsOverride: (UIImageView, ViewAttributes) -> NodeSemantics? = { imageView, _ in
        return imageView.isSystemShadow ? IgnoredElement(subtreeStrategy: .ignore) : nil
    }

    internal init(
        tintColorProvider: @escaping (UIImageView) -> UIColor? = { imageView in
            if #available(iOS 13.0, *), let image = imageView.image {
                return image.isTinted ? imageView.tintColor : nil
            } else {
                return nil
            }
        },
        shouldRecordImagePredicate: @escaping (UIImageView) -> Bool = { imageView in
            if #available(iOS 13.0, *), let image = imageView.image {
                return image.isContextual || imageView.isSystemControlBackground
            } else {
                return false
            }
        }
    ) {
        self.tintColorProvider = tintColorProvider
        self.shouldRecordImagePredicate = shouldRecordImagePredicate
    }

    func semantics(
        of view: UIView,
        with attributes: ViewAttributes,
        in context: ViewTreeRecordingContext
    ) -> NodeSemantics? {
        guard let imageView = view as? UIImageView else {
            return nil
        }
        if let semantics = semanticsOverride(imageView, attributes) {
            return semantics
        }
        guard attributes.hasAnyAppearance || imageView.image != nil else {
            return InvisibleElement.constant
        }

        let ids = context.ids.nodeIDs(2, view: imageView, nodeRecorder: self)
        let contentFrame: CGRect?
        if let image = imageView.image {
            contentFrame = attributes.frame.contentFrame(
                for: image.size,
                using: imageView.contentMode
            )
        } else {
            contentFrame = nil
        }
        let builder = UIImageViewWireframesBuilder(
            wireframeID: ids[0],
            imageWireframeID: ids[1],
            attributes: attributes,
            contentFrame: contentFrame,
            clipsToBounds: imageView.clipsToBounds,
            image: imageView.image,
            imageDataProvider: context.imageDataProvider,
            tintColor: tintColorProvider(imageView),
            shouldRecordImage: shouldRecordImagePredicate(imageView)
        )
        let node = Node(viewAttributes: attributes, wireframesBuilder: builder)
        return SpecificElement(
            subtreeStrategy: .record,
            nodes: [node],
            resources: [imageView.image].compactMap { $0 }
        )
    }
}

internal struct UIImageViewWireframesBuilder: NodeWireframesBuilder {
    let wireframeID: WireframeID

    var wireframeRect: CGRect {
        attributes.frame
    }

    let imageWireframeID: WireframeID

    let attributes: ViewAttributes

    let contentFrame: CGRect?

    let clipsToBounds: Bool

    let image: UIImage?

    let imageDataProvider: ImageDataProviding

    let tintColor: UIColor?

    let shouldRecordImage: Bool

    private var clip: SRContentClip? {
        guard let contentFrame = contentFrame else {
            return nil
        }
        let top = max(relativeIntersectedRect.origin.y - contentFrame.origin.y, 0)
        let left = max(relativeIntersectedRect.origin.x - contentFrame.origin.x, 0)
        let bottom = max(contentFrame.height - (relativeIntersectedRect.height + top), 0)
        let right = max(contentFrame.width - (relativeIntersectedRect.width + left), 0)
        return SRContentClip(
            bottom: Int64(withNoOverflow: bottom),
            left: Int64(withNoOverflow: left),
            right: Int64(withNoOverflow: right),
            top: Int64(withNoOverflow: top)
        )
    }

    private var relativeIntersectedRect: CGRect {
        guard let contentFrame = contentFrame else {
            return .zero
        }
        return attributes.frame.intersection(contentFrame)
    }

    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] {
        var wireframes = [
            builder.createShapeWireframe(
                id: wireframeID,
                frame: attributes.frame,
                borderColor: attributes.layerBorderColor,
                borderWidth: attributes.layerBorderWidth,
                backgroundColor: attributes.backgroundColor,
                cornerRadius: attributes.layerCornerRadius,
                opacity: attributes.alpha
            )
        ]
        var imageResource: ImageResource?
        if shouldRecordImage {
            imageResource = imageDataProvider.contentBase64String(
                of: image,
                tintColor: tintColor
            )
        }
        if let contentFrame = contentFrame {
            if let imageResource = imageResource {
                wireframes.append(
                    builder.createImageWireframe(
                        imageResource: imageResource,
                        id: imageWireframeID,
                        frame: contentFrame,
                        clip: clipsToBounds ? clip : nil
                    )
                )
            } else {
                wireframes.append(
                    builder.createPlaceholderWireframe(
                        id: imageWireframeID,
                        frame: clipsToBounds ? relativeIntersectedRect : contentFrame,
                        label: "Content Image"
                    )
                )
            }
        }
        return wireframes
    }
}

fileprivate extension UIImage {
    @available(iOS 13.0, *)
    var isContextual: Bool {
        return isSymbolImage || isBundled || isAlwaysTemplate
    }

    @available(iOS 13.0, *)
    var isTinted: Bool {
        return isSymbolImage || isAlwaysTemplate
    }

    private var isBundled: Bool {
        return description.contains("named(")
    }

    private var isAlwaysTemplate: Bool {
        return renderingMode == .alwaysTemplate
    }
}

fileprivate extension UIImageView {
    var isSystemControlBackground: Bool {
        return isButtonBackground || isBarBackground
    }

    var isSystemShadow: Bool {
        let className = "\(type(of: self))"
        // This gets effective on iOS 15.0+ which is the earliest version that displays some elements in popover views.
        // Here we explicitly ignore the "shadow" effect applied to popover.
        return className == "_UICutoutShadowView"
    }

    var isButtonBackground: Bool {
        if let button = superview as? UIButton, button.buttonType == .custom {
            return button.backgroundImage(for: button.state) == image
        }
        return false
    }

    var isBarBackground: Bool {
        guard let superview = superview else {
            return false
        }
        let superViewType = "\(type(of: superview))"
        return superViewType == "_UIBarBackground"
    }
}
#endif
