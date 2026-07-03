/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import UIKit

/// Rendered mask for one layer snapshot.
@available(iOS 13.0, tvOS 13.0, *)
internal final class MaskSnapshot: Sendable {
    let image: UIImage

    init(image: UIImage) {
        self.image = image
    }
}

/// A mask snapshot and the layer state used to render it.
@available(iOS 13.0, tvOS 13.0, *)
internal struct MaskSnapshotData: Sendable {
    let snapshot: MaskSnapshot

    /// The source layer bounds captured when the mask was rendered.
    let bounds: CGRect

    /// The mask layer frame captured when the mask was rendered.
    let frame: CGRect

    /// Mask layers captured when the image was rendered.
    let dependencies: [CALayerReference]
}

/// Result of rendering one layer mask snapshot.
@available(iOS 13.0, tvOS 13.0, *)
internal typealias MaskSnapshotResult = Result<MaskSnapshot, ImageSnapshotError>
#endif
