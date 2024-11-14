/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import UIKit

/// Produces `TouchSnapshots` of the key window in current application.
internal class WindowTouchSnapshotProducer: TouchSnapshotProducer, UIEventHandler {
    /// Finds the right window to capture touches in.
    private let windowObserver: AppWindowObserver
    /// Generates persisted IDs for `UITouch` objects.
    private let idsGenerator = TouchIdentifierGenerator()

    /// Touches recorded since last call to `takeSnapshot()`
    private var buffer: [TouchSnapshot.Touch] = []

    init(
        windowObserver: AppWindowObserver
    ) {
        self.windowObserver = windowObserver
    }

    func takeSnapshot(context: Recorder.Context) -> TouchSnapshot? {
        buffer = buffer.compactMap { touch in
            var updatedTouch = touch
            if let offset = context.viewServerTimeOffset {
                updatedTouch.date.addTimeInterval(offset)
            }

            // Filter the buffer to only include touches that should be recorded
            let shouldRecord = shouldRecordTouch(updatedTouch, in: context)
            return shouldRecord ? updatedTouch : nil
        }

        guard let firstTouch = buffer.first else {
            return nil
        }
        defer { buffer = [] }

        return TouchSnapshot(date: firstTouch.date, touches: buffer)
    }

    // MARK: - UIEventHandler

    /// Delegate of `UIApplicationSwizzler`.
    /// This method is triggered whenever `UIApplication` receives an `UIEvent`.
    /// It captures `UITouch` events, determines if the touch should be recorded
    /// based on the view hierarchy's touch privacy settings, and appends valid
    /// touches to a buffer for later snapshot creation. Touches are only recorded
    /// if they are not excluded by any `touchPrivacy` override set on the view or its ancestors.
    func notify_sendEvent(application: UIApplication, event: UIEvent) {
        guard event.type == .touches,
            let window = windowObserver.relevantWindow,
            let touches = event.touches(for: window)
        else {
            return
        }

        for touch in touches {
            guard let phase = touch.phase.dd else {
                continue
            }

            let touchId = idsGenerator.touchIdentifier(for: touch)

            // Capture the touch privacy override when the touch begins
            if phase == .down, let privacyOverride = resolveTouchOverride(for: touch) {
                touch.touchPrivacyOverride = privacyOverride
            }

            buffer.append(
                TouchSnapshot.Touch(
                    id: touchId,
                    phase: phase,
                    date: Date(),
                    position: touch.location(in: window),
                    touchOverride: touch.touchPrivacyOverride
                )
            )
        }
    }

    /// Determines whether the touch event should be recorded based on its privacy override and the global privacy settings.
    /// If the touch has a specific privacy override, that override is used.
    /// Otherwise, the global touch privacy setting is applied.
    /// - Parameter touchId: The unique identifier for the touch event.
    /// - Returns: `true` if the touch should be recorded, `false` otherwise.
    internal func shouldRecordTouch(_ touch: TouchSnapshot.Touch, in context: Recorder.Context
    ) -> Bool {
        let privacy: TouchPrivacyLevel = touch.touchOverride ?? context.touchPrivacy
        return privacy == .show
    }

    /// Resolves the touch privacy override for the given touch by traversing the view hierarchy.
    /// It checks the `dd.sessionReplayPrivacyOverrides.touchPrivacy` property for the view where the touch occurred
    /// and its ancestors, if needed. The first non-nil override encountered is returned.
    /// - Parameter touch: The touch event to check.
    /// - Returns: The `TouchPrivacyLevel` for the view, or `nil` if no override is found.
    internal func resolveTouchOverride(for touch: UITouch) -> TouchPrivacyLevel? {
        guard let initialView = touch.view else {
            return nil
        }

        var view: UIView? = initialView
        while view != nil {
            if let touchPrivacy = view?.dd.sessionReplayPrivacyOverrides.touchPrivacy {
                return touchPrivacy
            }
            view = view?.superview
        }
        return nil
   }
}

internal extension UITouch.Phase {
    /// Converts `UITouch.Phase` to touch phases distinguished in session replay.
    var dd: TouchSnapshot.TouchPhase? {
        switch self {
        case .began, .regionEntered: return .down
        case .moved, .regionMoved, .stationary: return .move
        case .ended, .cancelled, .regionExited: return .up
        @unknown default: return nil
        }
    }
}
#endif
