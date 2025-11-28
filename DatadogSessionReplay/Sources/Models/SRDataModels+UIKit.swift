/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit

extension SRTextPosition.Alignment {
    /// Custom initializer that allows transforming UIKit's `NSTextAlignment` into `SRTextPosition.Alignment`.
    @_spi(Internal)
    public init(
        systemTextAlignment: NSTextAlignment,
        vertical: SRTextPosition.Alignment.Vertical = .center
    ) {
        self.vertical = vertical
        switch systemTextAlignment {
        case .left:
            self.horizontal = .left
        case .center:
            self.horizontal = .center
        case .right:
            self.horizontal = .right
        case .justified:
            self.horizontal = .left
        case .natural:
            self.horizontal = .left
        @unknown default:
            self.horizontal = .left
        }
    }
}

extension SRTextStyle.TruncationMode {
    /// Creates a truncation mode from `NSLineBreakMode`.
    /// Returns `nil` for wrapping modes (`byWordWrapping`, `byCharWrapping`)
    internal init?(_ lineBreakMode: NSLineBreakMode) {
        switch lineBreakMode {
        case .byClipping:
            self = .clip
        case .byTruncatingHead:
            self = .head
        case .byTruncatingTail:
            self = .tail
        case .byTruncatingMiddle:
            self = .middle
        case .byWordWrapping, .byCharWrapping:
            return nil
        @unknown default:
            return nil
        }
    }
}
#endif
