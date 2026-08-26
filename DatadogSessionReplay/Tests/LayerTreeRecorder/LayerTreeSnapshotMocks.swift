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
        webViewSlotIDs: Set<Int> = [],
        embeddedContentSlots: [Int64: String] = [:]
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
            webViewSlotIDs: webViewSlotIDs,
            embeddedContentSlots: embeddedContentSlots
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
        bounds: CGRect? = nil,
        contentGeometry: ContentGeometry? = nil,
        transform: CATransform3D = CATransform3DIdentity,
        backgroundColor: CGColor? = nil,
        cornerRadii: CALayerSnapshot.CornerRadii = .zero,
        filters: [CALayerSnapshot.Filter] = [],
        isPrivate: Bool = false,
        isOpaque: Bool = false,
        masksToBounds: Bool = false,
        opacity: Float = 1,
        sublayers: [CALayerSnapshot] = []
    ) -> CALayerSnapshot {
        let layer = CALayer()
        let bounds = bounds ?? CGRect(origin: .zero, size: absoluteFrame.size)
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
            bounds: bounds,
            position: absoluteFrame.origin,
            zPosition: 0,
            transform: transform,
            absoluteFrame: absoluteFrame,
            contentGeometry: contentGeometry ?? .init(
                renderBounds: bounds,
                localRect: bounds,
                frame: absoluteFrame
            ),
            sublayers: sublayers,
            dependencies: [],
            sublayerTransform: CATransform3DIdentity,
            mask: nil,
            masksToBounds: masksToBounds,
            isOpaque: isOpaque,
            backgroundColor: backgroundColor,
            cornerRadii: cornerRadii,
            cornerCurve: .circular,
            borderWidth: 0,
            borderColor: nil,
            opacity: opacity,
            allowsGroupOpacity: true,
            compositingFilter: nil,
            filters: filters,
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
