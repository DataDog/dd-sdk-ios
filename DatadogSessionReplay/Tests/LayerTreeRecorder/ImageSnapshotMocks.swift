/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import DatadogInternal
import UIKit

@testable import DatadogSessionReplay

@available(iOS 13.0, tvOS 13.0, *)
extension ImageSnapshot {
    static func mockAny(
        image: UIImage = UIImage(),
        frame: CGRect = .zero,
        layerClass: AnyClass = CALayer.self,
        delegateClass: AnyClass? = nil,
        hasLayerSemantics: Bool = true,
        textAndInputPrivacyLevel: TextAndInputPrivacyLevel = .maskAll,
        imagePrivacyLevel: ImagePrivacyLevel = .maskAll
    ) -> ImageSnapshot {
        ImageSnapshot(
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
extension ImageSnapshotData {
    static func mockAny(
        snapshot: ImageSnapshot = .mockAny(),
        localRect: CGRect = .zero,
        bounds: CGRect = .zero,
        dependencies: [CALayerReference] = []
    ) -> ImageSnapshotData {
        ImageSnapshotData(snapshot: snapshot, localRect: localRect, bounds: bounds, dependencies: dependencies)
    }
}
#endif
