/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import CoreGraphics
@_spi(Internal)
import DatadogInternal
import Foundation
import QuartzCore

@testable import DatadogSessionReplay

@available(iOS 13.0, tvOS 13.0, *)
extension LayerTreeSnapshot {
    static func mockWith(
        date: Date = Date(timeIntervalSince1970: 42),
        applicationID: String = "app-id",
        sessionID: String = "session-id",
        viewID: String = "view-id",
        viewportSize: CGSize = CGSize(width: 320, height: 640),
        root: CALayerSnapshot = .mockRoot(),
        webViewSlotIDs: Set<Int> = []
    ) -> LayerTreeSnapshot {
        return LayerTreeSnapshot(
            date: date,
            context: LayerRecordingContext(
                textAndInputPrivacy: .maskSensitiveInputs,
                imagePrivacy: .maskNone,
                touchPrivacy: .show,
                applicationID: applicationID,
                sessionID: sessionID,
                viewID: viewID,
                viewServerTimeOffset: 0,
                viewPath: "/view",
                date: date,
                telemetry: NOPTelemetry()
            ),
            viewportSize: viewportSize,
            root: root,
            webViewSlotIDs: webViewSlotIDs
        )
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot {
    static func mockRoot(
        absoluteFrame: CGRect = CGRect(x: 0, y: 0, width: 100, height: 200),
        sublayers: [CALayerSnapshot] = []
    ) -> CALayerSnapshot {
        return mockWith(
            replayID: 1,
            absoluteFrame: absoluteFrame,
            backgroundColor: nil,
            sublayers: sublayers
        )
    }

    static func mockWith(
        replayID: Int64 = 1,
        absoluteFrame: CGRect = .zero,
        observation: CALayerSnapshot.SemanticObservation = .init(semantics: .layer),
        backgroundColor: CGColor? = nil,
        isPrivate: Bool = false,
        sublayers: [CALayerSnapshot] = []
    ) -> CALayerSnapshot {
        let layer = CALayer()
        return CALayerSnapshot(
            layer: CALayerReference(layer),
            replayID: replayID,
            observation: observation,
            layerClass: CALayer.self,
            delegateClass: nil,
            contentsClass: nil,
            textAndInputPrivacyLevel: .maskSensitiveInputs,
            imagePrivacyLevel: .maskNone,
            isPrivate: isPrivate,
            bounds: CGRect(origin: .zero, size: absoluteFrame.size),
            position: absoluteFrame.origin,
            zPosition: 0,
            transform: CATransform3DIdentity,
            absoluteFrame: absoluteFrame,
            sublayers: sublayers,
            dependencies: [],
            sublayerTransform: CATransform3DIdentity,
            mask: nil,
            masksToBounds: false,
            isOpaque: false,
            backgroundColor: backgroundColor,
            cornerRadii: .zero,
            cornerCurve: .circular,
            borderWidth: 0,
            borderColor: nil,
            opacity: 1,
            allowsGroupOpacity: true,
            compositingFilter: nil,
            filters: [],
            shadowColor: nil,
            shadowOpacity: 0,
            shadowOffset: .zero,
            shadowRadius: 0,
            shadowPath: nil
        )
    }
}

private struct NOPTelemetry: Telemetry {
    func send(telemetry: TelemetryMessage) {}
}
#endif
