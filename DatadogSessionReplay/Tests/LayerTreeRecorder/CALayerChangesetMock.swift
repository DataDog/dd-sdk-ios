/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import QuartzCore

@testable import DatadogSessionReplay

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerChangeset {
    static func mockChange(for layer: CALayer, aspects: CALayerChange.Aspect.Set) -> CALayerChangeset {
        CALayerChangeset(
            [ObjectIdentifier(layer): CALayerChange(layer: .init(layer), aspects: aspects)]
        )
    }
}
#endif
