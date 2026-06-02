/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import UIKit

@preconcurrency import DatadogInternal

/// Rendered image for one layer snapshot.
@available(iOS 13.0, tvOS 13.0, *)
internal final class ImageSnapshot: Sendable {
    let image: UIImage
    let frame: CGRect
    let textAndInputPrivacyLevel: TextAndInputPrivacyLevel
    let imagePrivacyLevel: ImagePrivacyLevel

    init(
        image: UIImage,
        frame: CGRect,
        textAndInputPrivacyLevel: TextAndInputPrivacyLevel,
        imagePrivacyLevel: ImagePrivacyLevel
    ) {
        self.image = image
        self.frame = frame
        self.textAndInputPrivacyLevel = textAndInputPrivacyLevel
        self.imagePrivacyLevel = imagePrivacyLevel
    }
}

/// An image snapshot and the geometry used to render it.
@available(iOS 13.0, tvOS 13.0, *)
internal struct ImageSnapshotData: Sendable {
    let snapshot: ImageSnapshot
    let localRect: CGRect
    let bounds: CGRect
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
internal typealias ImageSnapshotResult = Result<ImageSnapshot, ImageSnapshotError>
#endif
