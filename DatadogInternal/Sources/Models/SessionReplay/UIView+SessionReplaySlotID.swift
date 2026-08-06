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
            guard newValue != sessionReplaySlotID else {
                return
            }

            objc_setAssociatedObject(
                type,
                &sessionReplaySlotIDKey,
                newValue,
                .OBJC_ASSOCIATION_COPY_NONATOMIC
            )

            // The view's contents are unchanged, but its representation in the wireframe tree is not.
            // Marking it as needing layout makes Session Replay observe `CALayer.layoutSublayers` and
            // record a new snapshot, so the slot is published without waiting for an unrelated
            // screen change — the embedding host may not draw anything on its own.
            runOnMainThreadSync { type.setNeedsLayout() }
        }
    }
}
#endif
