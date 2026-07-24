/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import DatadogInternal
import QuartzCore
import UIKit

@testable import DatadogSessionReplay

@available(iOS 13.0, tvOS 13.0, *)
extension ContentSnapshot {
    static func mockAny(
        image: UIImage = UIImage(),
        frame: CGRect = .zero,
        layerClass: AnyClass = CALayer.self,
        delegateClass: AnyClass? = nil,
        hasLayerSemantics: Bool = true,
        textAndInputPrivacyLevel: TextAndInputPrivacyLevel = .maskAll,
        imagePrivacyLevel: ImagePrivacyLevel = .maskAll
    ) -> ContentSnapshot {
        ContentSnapshot(
            image: image,
            frame: frame,
            layerClass: layerClass,
            delegateClass: delegateClass,
            hasLayerSemantics: hasLayerSemantics,
            textAndInputPrivacyLevel: textAndInputPrivacyLevel,
            imagePrivacyLevel: imagePrivacyLevel
        )
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension ContentSnapshotData {
    static func mockAny(
        snapshot: ContentSnapshot = .mockAny(),
        localRect: CGRect = .zero,
        bounds: CGRect = .zero,
        renderBounds: CGRect? = nil,
        dependencies: [CALayerReference] = []
    ) -> ContentSnapshotData {
        ContentSnapshotData(
            snapshot: snapshot,
            localRect: localRect,
            renderBounds: renderBounds ?? bounds,
            bounds: bounds,
            dependencies: dependencies
        )
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension MaskSnapshot {
    static func mockAny(image: UIImage = UIImage()) -> MaskSnapshot {
        MaskSnapshot(image: image)
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension MaskSnapshotData {
    static func mockAny(
        snapshot: MaskSnapshot = .mockAny(),
        bounds: CGRect = .zero,
        frame: CGRect = .zero,
        dependencies: [CALayerReference] = []
    ) -> MaskSnapshotData {
        MaskSnapshotData(snapshot: snapshot, bounds: bounds, frame: frame, dependencies: dependencies)
    }
}

extension UIImage {
    static func mockWith(color: UIColor) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10))
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
    }
}
#endif
