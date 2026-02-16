/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

// MARK: - Overview
//
// A weak, `Sendable` identity wrapper for `CALayer`.
//
// Use this for liveness checks and identity comparison without retaining the layer.
// No direct access is exposed; use `resolve()` on the main actor to work with the
// layer if it's still alive.

#if os(iOS)
import QuartzCore

internal struct CALayerReference: @unchecked Sendable {
    var identifier: ObjectIdentifier? {
        layer.map(ObjectIdentifier.init)
    }

    var isAlive: Bool {
        layer != nil
    }

    var `class`: AnyClass? {
        layer.map {
            type(of: $0)
        }
    }

    var delegateClass: AnyClass? {
        layer?.delegate.flatMap {
            type(of: $0)
        }
    }

    private weak var layer: CALayer?

    init(_ layer: CALayer) {
        self.layer = layer
    }

    func matches(_ other: CALayer) -> Bool {
        layer === other
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @MainActor
    func resolve() -> CALayer? {
        layer
    }
}

extension CALayerReference: Equatable {
    static func == (lhs: CALayerReference, rhs: CALayerReference) -> Bool {
        lhs.layer === rhs.layer
    }
}
#endif
