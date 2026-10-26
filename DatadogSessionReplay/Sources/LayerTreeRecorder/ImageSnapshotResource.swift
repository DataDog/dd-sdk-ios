/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit

internal struct ImageSnapshotResource: Resource {
    let image: UIImage

    var mimeType: String {
        "image/webp"
    }

    func calculateIdentifier() -> String {
        guard
            let hash = image.contentHash,
            let size = image.webPPixelSize()
        else {
            return ""
        }

        return "\(hash)-\(size.width)x\(size.height).webp"
    }

    func calculateData() -> Data {
        image.webPData() ?? Data()
    }
}
#endif
