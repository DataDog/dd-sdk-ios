/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit
import DatadogInternal

extension CGSize: DatadogExtended {}

internal extension DatadogExtension where ExtendedType == CGSize {
    var aspectRatio: CGFloat {
        type.width > 0 ? type.height / type.width : 0
    }

    func scaleAspectFillRect(for contentSize: CGSize) -> CGRect {
        let scale = max(type.width / contentSize.width, type.height / contentSize.height)
        let size = CGSize(width: contentSize.width * scale, height: contentSize.height * scale)
        return CGRect(
            x: (type.width - size.width) / 2,
            y: (type.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    func scaleAspectFitRect(for contentSize: CGSize) -> CGRect {
        let imageAspectRatio = contentSize.height / contentSize.width
        var x, y, width, height: CGFloat
        if imageAspectRatio > aspectRatio {
            height = type.height
            width = height / imageAspectRatio
            x = (type.width / 2) - (width / 2)
            y = 0
        } else {
            width = type.width
            height = width * imageAspectRatio
            x = 0
            y = (type.height / 2) - (height / 2)
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

#endif
