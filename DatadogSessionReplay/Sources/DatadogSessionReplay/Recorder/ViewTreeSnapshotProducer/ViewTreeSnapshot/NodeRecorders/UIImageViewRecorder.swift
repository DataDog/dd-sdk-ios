/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

internal struct UIImageViewRecorder: NodeRecorder {
    let imageDataProvider = ImageDataProvider()
    func semantics(
        of view: UIView,
        with attributes: ViewAttributes,
        in context: ViewTreeSnapshotBuilder.Context
    ) -> NodeSemantics? {
        guard let imageView = view as? UIImageView else {
            return nil
        }
        guard attributes.hasAnyAppearance || imageView.image != nil else {
            return InvisibleElement.constant
        }

        let ids = context.ids.nodeID2(for: imageView)
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
            wireframeID: ids.0,
            imageWireframeID: ids.1,
            attributes: attributes,
            contentFrame: contentFrame,
            clipsToBounds: imageView.clipsToBounds,
            base64: imageDataProvider.lazyBase64String(imageView: imageView)
        )
        return SpecificElement(wireframesBuilder: builder, recordSubtree: true)
    }
}

extension UIView {

    // Using a function since `var image` might conflict with an existing variable
    // (like on `UIImageView`)
    func asImage() -> UIImage? {
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        return renderer.image { rendererContext in
            layer.render(in: rendererContext.cgContext)
        }
    }
}

class ImageDataProvider {
    enum DataLoadingStatus: Hashable {
        case loading, loaded(_ base64: String), ignored
    }

    var base64s = [String: DataLoadingStatus]()

    var emptyImageData = "R0lGODlhAQABAIAAAP7//wAAACH5BAAAAAAALAAAAAABAAEAAAICRAEAOw=="

    func lazyBase64String(imageView: UIImageView) -> String? {
        guard let image = imageView.image else {
            return emptyImageData
        }
        let tintColor = imageView.tintColor
        let hash = "\(image.hash)-\(String(describing: tintColor?.hash))"
        let dataLoadingStaus = base64s[hash]
        switch dataLoadingStaus {
        case .loaded(let base64String):
            return base64String
        case .none:
            base64s[hash] = .loading

            DispatchQueue.global(qos: .background).async { [weak self] in
                print("🏞️💾Size of Memory Cache \(Double(MemoryLayout.size(ofValue: self?.base64s))/1024) KB")
                let data: Data?
                if let tintColor = tintColor, #available(iOS 13.0, *) {
                    data = image.withTintColor(tintColor).pngData()
                } else {
                    data = image.pngData()
                }
                let sizeKB = Double(data?.count ?? 0) / 1024.0
                if let base64String = data?.base64EncodedString(), sizeKB < 128.0 { // Max image size of 128KB
                    print("🏞️✅ Loaded. Size: \(sizeKB) KB")
                    self?.base64s[hash] = .loaded(base64String)
                }
                else {
                    DispatchQueue.main.async {
                        if let snapshot = imageView.asImage()?.jpegData(compressionQuality: 0.5), Double(snapshot.count) / 1024.0 < 128.0 {
                            self?.base64s[hash] = .loaded(snapshot.base64EncodedString())
                        } else {
                            print("🏞️❌ Ignored. Size: \(sizeKB) KB")
                            self?.base64s[hash] = .ignored
                        }
                    }
                }
            }
            return nil
        case .ignored:
            return emptyImageData
        case .loading:
            return nil
        }
    }
}

internal struct UIImageViewWireframesBuilder: NodeWireframesBuilder {
    struct Defaults {
        /// Until we suppport images in SR V.x., this color is used as placeholder in SR V.0.:
        static let placeholderColor: CGColor = UIColor.systemGray.cgColor
    }

    let wireframeID: WireframeID

    var wireframeRect: CGRect {
        attributes.frame
    }

    let imageWireframeID: WireframeID

    let attributes: ViewAttributes

    let contentFrame: CGRect?

    let clipsToBounds: Bool

    let base64: String?

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
        if let contentFrame = contentFrame {
            wireframes.append(
                builder.createImageWireframe(
                    base64: base64,
                    id: imageWireframeID,
                    frame: contentFrame,
                    clip: clipsToBounds ? clip : nil
                )
            )
        }
        return wireframes
    }
}
