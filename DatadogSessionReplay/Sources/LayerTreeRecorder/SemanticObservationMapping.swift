/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import QuartzCore

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot {
    struct SemanticObservationMapping {
        let observe: @MainActor (
            _ layer: CALayer,
            _ absoluteFrame: CGRect,
            _ context: CALayerSnapshot.Context
        ) -> SemanticObservation?
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.SemanticObservationMapping: CaseIterable {
    static let allCases: [Self] = [
        .embeddedContent,
        .gradient,
        .activityIndicator,
        .label,
        .imageView,
        .textView,
        .textField,
        .webView,
        .control,
        .progressView,
        .barBackground,
        // visual effects
        .signedDistanceField,
        .destinationOutView,
        .portal,
        .automaticCapsule,
        .glassGroup,
        .scrollPocket,
        .captureOnlyBackdrop,
        .visualEffectBackdrop,
        .visualEffectBackground,
        .liquidLens
    ]
}
#endif
