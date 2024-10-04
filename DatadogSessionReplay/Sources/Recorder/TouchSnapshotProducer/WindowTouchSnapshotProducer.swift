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

    init(windowObserver: AppWindowObserver) {
        self.windowObserver = windowObserver
    }

    func takeSnapshot(context: Recorder.Context) -> TouchSnapshot? {
        if let offset = context.viewServerTimeOffset {
            buffer = buffer.compactMap {
                var touch = $0
                touch.date.addTimeInterval(offset)
                return touch
            }
        }
        guard let firstTouch = buffer.first else {
            return nil
        }
        defer { buffer = [] }

        return TouchSnapshot(date: firstTouch.date, touches: buffer)
    }

    // MARK: - UIEventHandler

    /// Delegate of `UIApplicationSwizzler` - called each time when `UIApplication` receives an `UIEvent`.
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

            buffer.append(
                TouchSnapshot.Touch(
                    id: idsGenerator.touchIdentifier(for: touch),
                    phase: phase,
                    date: Date(),
                    position: touch.location(in: window)
                )
            )
        }
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
