/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

// MARK: - Overview
//
// Represents a change observed on a `CALayer`.
//
// Captures which aspects changed (display, draw, layout) for downstream processing
// and correlation. Designed to be a lightweight signal between observation and
// reporting components.

#if os(iOS)
import QuartzCore

internal struct CALayerChange: Sendable, Equatable {
    enum Aspect: Int8, CaseIterable {
        case display
        case draw
        case layout

        struct Set: OptionSet {
            let rawValue: Int8

            init(rawValue: Int8) {
                self.rawValue = rawValue
            }

            static let display = Self(rawValue: 1 << Aspect.display.rawValue)
            static let draw = Self(rawValue: 1 << Aspect.draw.rawValue)
            static let layout = Self(rawValue: 1 << Aspect.layout.rawValue)
        }
    }

    var layer: CALayerReference
    var aspects: Aspect.Set
}
#endif
