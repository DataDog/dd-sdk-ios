/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit
import DatadogInternal

extension CGRect: DatadogExtended {}

internal extension DatadogExtension where ExtendedType == CGRect {
    func contentFrame(
        for contentSize: CGSize,
        using contentMode: UIView.ContentMode
    ) -> CGRect {
        guard type.width > 0 && type.height > 0 && contentSize.width > 0 && contentSize.height > 0 else {
            return .zero
        }
        switch contentMode {
        case .scaleAspectFit:
            let actualContentRect = type.size.dd.scaleAspectFitRect(for: contentSize)
            return CGRect(
                x: type.origin.x + actualContentRect.origin.x,
                y: type.origin.y + actualContentRect.origin.y,
                width: actualContentRect.size.width,
                height: actualContentRect.size.height
            )

        case .scaleAspectFill:
            let actualContentRect = type.size.dd.scaleAspectFillRect(for: contentSize)
            return CGRect(
                x: type.origin.x + actualContentRect.origin.x,
                y: type.origin.y + actualContentRect.origin.y,
                width: actualContentRect.size.width,
                height: actualContentRect.size.height
            )
        case .redraw, .center:
            return CGRect(
                x: type.origin.x + (type.width - contentSize.width) / 2,
                y: type.origin.y + (type.height - contentSize.height) / 2,
                width: contentSize.width,
                height: contentSize.height
            )
        case .scaleToFill:
            return type

        case .topLeft:
            return CGRect(
                x: type.origin.x,
                y: type.origin.y,
                width: contentSize.width,
                height: contentSize.height
            )
        case .topRight:
            return CGRect(
                x: type.origin.x + (type.width - contentSize.width),
                y: type.origin.y,
                width: contentSize.width,
                height: contentSize.height
            )
        case .bottomLeft:
            return CGRect(
                x: type.origin.x,
                y: type.origin.y + (type.height - contentSize.height),
                width: contentSize.width,
                height: contentSize.height
            )
        case .bottomRight:
            return CGRect(
                x: type.origin.x + (type.width - contentSize.width),
                y: type.origin.y + (type.height - contentSize.height),
                width: contentSize.width,
                height: contentSize.height
            )
        case .top:
            return CGRect(
                x: type.origin.x + (type.width - contentSize.width) / 2,
                y: type.origin.y,
                width: contentSize.width,
                height: contentSize.height
            )
        case .bottom:
            return CGRect(
                x: type.origin.x + (type.width - contentSize.width) / 2,
                y: type.origin.y + (type.height - contentSize.height),
                width: contentSize.width,
                height: contentSize.height
            )
        case .left:
            return CGRect(
                x: type.origin.x,
                y: type.origin.y + (type.height - contentSize.height) / 2,
                width: contentSize.width,
                height: contentSize.height
            )
        case .right:
            return CGRect(
                x: type.origin.x + (type.width - contentSize.width),
                y: type.origin.y + (type.height - contentSize.height) / 2,
                width: contentSize.width,
                height: contentSize.height
            )

        @unknown default:
            return type
        }
    }
}

#endif
