/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import QuartzCore

@testable import DatadogSessionReplay

final class CALayerObserverMock: CALayerObserver {
    var layerDidDisplayCalls: [CALayer] = []
    var layerDidDrawCalls: [(layer: CALayer, context: CGContext)] = []
    var layerDidLayoutSublayersCalls: [CALayer] = []

    func layerDidDisplay(_ layer: CALayer) {
        layerDidDisplayCalls.append(layer)
    }

    func layerDidDraw(_ layer: CALayer, in context: CGContext) {
        layerDidDrawCalls.append((layer, context))
    }

    func layerDidLayoutSublayers(_ layer: CALayer) {
        layerDidLayoutSublayersCalls.append(layer)
    }
}
#endif
