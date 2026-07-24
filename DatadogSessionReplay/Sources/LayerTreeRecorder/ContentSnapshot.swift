/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import UIKit

@preconcurrency import DatadogInternal

/// Rendered content for one layer snapshot.
@available(iOS 13.0, tvOS 13.0, *)
internal final class ContentSnapshot: Sendable {
    let image: UIImage

    /// The image frame in the root layer coordinate space.
    let frame: CGRect

    let layerClass: AnyClass
    let delegateClass: AnyClass?
    let hasLayerSemantics: Bool

    let textAndInputPrivacyLevel: TextAndInputPrivacyLevel
    let imagePrivacyLevel: ImagePrivacyLevel

    init(
        image: UIImage,
        frame: CGRect,
        layerClass: AnyClass,
        delegateClass: AnyClass?,
        hasLayerSemantics: Bool,
        textAndInputPrivacyLevel: TextAndInputPrivacyLevel,
        imagePrivacyLevel: ImagePrivacyLevel
    ) {
        self.image = image
        self.frame = frame
        self.layerClass = layerClass
        self.delegateClass = delegateClass
        self.hasLayerSemantics = hasLayerSemantics
        self.textAndInputPrivacyLevel = textAndInputPrivacyLevel
        self.imagePrivacyLevel = imagePrivacyLevel
    }
}

/// A content snapshot and the geometry used to render it.
@available(iOS 13.0, tvOS 13.0, *)
internal struct ContentSnapshotData: Sendable {
    let snapshot: ContentSnapshot

    /// The rendered rect in the source layer coordinate space.
    let localRect: CGRect

    /// The full rect selected for rendering in the source layer coordinate space.
    let renderBounds: CGRect

    /// The source layer bounds captured when the image was rendered.
    let bounds: CGRect

    /// Layer dependencies captured when the image was rendered.
    let dependencies: [CALayerReference]
}

/// Failure reason for a layer image snapshot.
@available(iOS 13.0, tvOS 13.0, *)
internal enum ImageSnapshotError: Error, Equatable {
    /// The recorder exhausted its time budget before rendering this image.
    case timedOut

    /// The image could not be rendered and should be ignored for this frame.
    case discarded
}

/// Result of rendering one layer image snapshot.
@available(iOS 13.0, tvOS 13.0, *)
internal typealias ContentSnapshotResult = Result<ContentSnapshot, ImageSnapshotError>
#endif
