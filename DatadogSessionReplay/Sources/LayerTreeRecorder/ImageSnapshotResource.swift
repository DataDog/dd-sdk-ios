/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit

internal struct ImageSnapshotResource: Resource {
    enum Format: String {
        case png
        case webP = "webp"
    }

    let image: UIImage
    let format: Format

    init(image: UIImage, format: Format) {
        self.image = image
        self.format = format
    }

    var mimeType: String {
        "image/\(format.rawValue)"
    }

    func calculateIdentifier() -> String {
        guard
            let hash = image.contentHash,
            let size = image.encodingPixelSize()
        else {
            return ""
        }

        return "\(hash)-\(size.width)x\(size.height).\(format.rawValue)"
    }

    func calculateData() -> Data {
        switch format {
        case .png:
            return image.resizedPNGData() ?? Data()
        case .webP:
            return image.resizedWebPData() ?? Data()
        }
    }
}
#endif
