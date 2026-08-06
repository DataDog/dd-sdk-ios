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
public extension Notification.Name {
    /// Posted when a view's `sessionReplaySlotID` changes, with that view as the notification object.
    ///
    /// Session Replay only emits the `embedded_view` placeholder for views that already carry a slot
    /// ID at the moment a snapshot is taken, and it snapshots in response to `CALayer` activity —
    /// which assigning an associated object does not produce. Without this notification the
    /// placeholder would first appear on whatever unrelated change happened to trigger the next
    /// snapshot, so the embedding SDK's records would reach the player ahead of the slot they belong
    /// to. Session Replay observes this and treats an assignment as a screen change.
    static let ddSessionReplaySlotIDDidChange = Notification.Name("dd-session-replay-slot-id-did-change")
}

@_spi(Internal)
public extension DatadogExtension where ExtendedType: UIView {
    /// Identifies this view as a host slot for embedded Session Replay content.
    ///
    /// The slot ID is supplied by the embedding SDK and is independent of the view's wireframe ID.
    ///
    /// Setting a new value posts `Notification.Name.ddSessionReplaySlotIDDidChange`, so Session
    /// Replay can capture a snapshot that carries the placeholder for this slot.
    var sessionReplaySlotID: String? {
        get {
            objc_getAssociatedObject(type, &sessionReplaySlotIDKey) as? String
        }
        nonmutating set {
            guard newValue != sessionReplaySlotID else {
                return // no-op, and notifying would schedule a snapshot for nothing
            }

            objc_setAssociatedObject(
                type,
                &sessionReplaySlotIDKey,
                newValue,
                .OBJC_ASSOCIATION_COPY_NONATOMIC
            )

            NotificationCenter.default.post(
                name: .ddSessionReplaySlotIDDidChange,
                object: type
            )
        }
    }
}
#endif
