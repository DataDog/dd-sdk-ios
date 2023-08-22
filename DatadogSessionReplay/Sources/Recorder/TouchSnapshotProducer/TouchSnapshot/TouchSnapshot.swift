/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import CoreGraphics

/// Describes a sequence of touch information over time.
internal struct TouchSnapshot {
    /// A single touch information.
    struct Touch {
        /// An unique identifier of the touch. It persists throughout a multi-touch sequence (it is created on "touch down",
        /// continues thru "touch move" and ends in "touch up").
        let id: TouchIdentifier
        /// Phase of the touch as distinguished in session replay.
        let phase: TouchPhase
        /// A time of recording this touch
        var date: Date
        /// The position of this touch in application window.
        let position: CGPoint
    }

    enum TouchPhase {
        case down
        case move
        case up
    }

    /// The time of the earliest touch.
    let date: Date
    /// Touches recorded in this snapshot.
    let touches: [Touch]
}
#endif
