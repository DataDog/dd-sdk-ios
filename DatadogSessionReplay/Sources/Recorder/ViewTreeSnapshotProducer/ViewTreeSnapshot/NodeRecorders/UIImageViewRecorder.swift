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

    /// For animated images only
    private let fixedFPS: Double = 66
    /// Cache for storing last update timestamp and current frame index per image view
    private static var cache: [String: (timestamp: DispatchTime, frameIndex: Int)] = [:]

    internal init(
        tintColorProvider: @escaping (UIImageView) -> UIColor? = { imageView in
            let image = imageView.image ?? imageView.animationImages?.first
            if #available(iOS 13.0, *), let image {
                return image.isTinted ? imageView.tintColor : nil
            } else {
                return nil
            }
        },
        shouldRecordImagePredicate: @escaping (UIImageView) -> Bool = { imageView in
            //return true
            let image = imageView.image ?? imageView.animationImages?.first
            if #available(iOS 13.0, *), let image {
                print("isContextual:", image.isContextual)
                print("isSystemControlBackground:", imageView.isSystemControlBackground)
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

        let image = imageView.image ?? imageView.animationImages?.first
        guard attributes.hasAnyAppearance || image != nil else {
            return InvisibleElement.constant
        }

        let ids = context.ids.nodeIDs(2, view: imageView, nodeRecorder: self)

        var contentFrame = image.map {
            attributes.frame.contentFrame(
                for: $0.size,
                using: imageView.contentMode
            )
        }

        let shouldRecordImage = shouldRecordImagePredicate(imageView)
        let imageResource = shouldRecordImage ? getImageResource(from: imageView) : nil
        let animatedImage = imageView.animationImages != nil

        let builder = UIImageViewWireframesBuilder(
            wireframeID: ids[0],
            imageWireframeID: ids[1],
            attributes: attributes,
            contentFrame: contentFrame,
            clipsToBounds: imageView.clipsToBounds,
            imageResource: imageResource,
            animatedImage: animatedImage
        )
        if animatedImage {
            print("animatedImage...")
            print("wireframeID:", ids[0])
            print("imageWireframeID:", ids[1])
            print("imageResource ID:", imageResource?.image.dd.srIdentifier ?? "n")
            print("contentFrame:", contentFrame)
        }

        let node = Node(viewAttributes: attributes, wireframesBuilder: builder)
        return SpecificElement(
           subtreeStrategy: .record,
           nodes: [node]
       )
    }

    private func getImageResource(from imageView: UIImageView) -> UIImageResource? {
        if imageView.animationImages != nil {
            let staticImage = imageView.image
            //print("animated iv static image:", staticImage)
        }

        guard let animationImages = imageView.animationImages else {
            return imageView.image.map { image in
                UIImageResource(image: image, tintColor: tintColorProvider(imageView))
            }
        }

        // Picking random image for testing purposes;
        // will use getAnimatedImageResource method below after.
        let randomNumber = Int.random(in: 0..<animationImages.count)
        let imageResource = UIImageResource(image: animationImages[randomNumber], tintColor: tintColorProvider(imageView))
        print("imageResource SR ID:", imageResource.image.dd.srIdentifier)
        return imageResource
    }

    private func getAnimatedImageResource(imageView: UIImageView, animationImages: [UIImage]) -> UIImageResource {
        let animationDuration = imageView.animationDuration
        let numberOfFrames = animationImages.count

        // Calculate the original time per frame and time per snapshot
        let originalTimePerFrame = animationDuration / Double(numberOfFrames)
        let timePerSnapshot = 1.0 / fixedFPS
        // 0.1   // Scheduler interval in seconds, which equals 10 FPS
        // 1.0 / fixedFPS

        // Calculate total frames to display based on the fixed FPS
        let totalFramesToDisplay = Int(animationDuration / timePerSnapshot)
        // Int(fixedFPS * animationDuration)

        let currentTime = DispatchTime.now()
        let imageViewID = imageView.srIdentifier

        // Retrieve value from cache for this image view
        var cachedValues: (timestamp: DispatchTime, frameIndex: Int) = (currentTime, 0)
        if let values = UIImageViewRecorder.cache[imageViewID] {
            cachedValues = values
        } else {
            UIImageViewRecorder.cache[imageViewID] = (currentTime, 0)
        }

        let lastUpdateTimestamp = cachedValues.timestamp
        var currentFrameIndex = cachedValues.frameIndex

        // Calculate time elapsed since last snapshot
        let elapsedTime = currentTime.uptimeNanoseconds - lastUpdateTimestamp.uptimeNanoseconds
        let elapsedTimeInSeconds = Double(elapsedTime) / 1_000_000_000

        // Update the current frame index based on elapsed time and fixed FPS
        if elapsedTimeInSeconds >= timePerSnapshot {
            let framesToSkip = Int(elapsedTimeInSeconds / timePerSnapshot)
            currentFrameIndex = (currentFrameIndex + framesToSkip) % totalFramesToDisplay
            // Update cache with new values
            UIImageViewRecorder.cache[imageViewID] = (currentTime, currentFrameIndex)
        }

        // Calculate the frame index in the original images
        let frameIndex = min((currentFrameIndex * numberOfFrames) / totalFramesToDisplay, numberOfFrames - 1)
        print("frameIndex:", frameIndex)
        let selectedImage = animationImages[frameIndex]

        return UIImageResource(image: selectedImage, tintColor: tintColorProvider(imageView))
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

    let imageResource: UIImageResource?

    let animatedImage: Bool

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

        if animatedImage {
            print("animatedImage!")
        }

        guard let contentFrame else {
            return wireframes
        }

        if let imageResource {
            wireframes.append(
                builder.createImageWireframe(
                    id: imageWireframeID,
                    resource: imageResource,
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

private var srIdentifierKey: UInt8 = 11

fileprivate extension UIImageView {
    var srIdentifier: String {
        if let identifier = objc_getAssociatedObject(self, &srIdentifierKey) as? String {
            return identifier
        } else {
            let identifier = UUID().uuidString
            objc_setAssociatedObject(self, &srIdentifierKey, identifier, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return identifier
        }
    }
}

#endif
