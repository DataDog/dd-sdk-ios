/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import QuartzCore

/// Weak identity wrapper for a `CALayer`.
///
/// Use it to compare layer identity without keeping the layer alive.
/// Call `resolve()` on the main actor when the live layer is needed.
internal struct CALayerReference: @unchecked Sendable {
    var identifier: ObjectIdentifier? {
        layer.map(ObjectIdentifier.init)
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
