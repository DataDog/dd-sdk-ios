/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit

private var sessionReplaySlotIDKey: UInt8 = 0

extension UIView: DatadogExtended {}

@_spi(Internal)
public extension DatadogExtension where ExtendedType: UIView {
    /// Identifies this view as a host slot for embedded Session Replay content.
    ///
    /// The slot ID is supplied by the embedding SDK and is independent of the view's wireframe ID.
    var sessionReplaySlotID: String? {
        get {
            objc_getAssociatedObject(type, &sessionReplaySlotIDKey) as? String
        }
        nonmutating set {
            objc_setAssociatedObject(
                type,
                &sessionReplaySlotIDKey,
                newValue,
                .OBJC_ASSOCIATION_COPY_NONATOMIC
            )
        }
    }
}
#endif
