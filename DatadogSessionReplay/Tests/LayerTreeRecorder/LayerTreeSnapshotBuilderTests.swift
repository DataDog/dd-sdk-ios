/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import DatadogInternal
import QuartzCore
import Testing
import WebKit

@testable import DatadogSessionReplay

@MainActor
struct LayerTreeSnapshotBuilderTests {
    @available(iOS 13.0, tvOS 13.0, *)
    enum Fixtures {
        private struct NOPTelemetry: Telemetry {
            func send(telemetry: TelemetryMessage) {}
        }

        static func context(
            date: Date = Date(timeIntervalSince1970: 10),
            viewServerTimeOffset: TimeInterval? = 2
        ) -> LayerRecordingContext {
            LayerRecordingContext(
                textAndInputPrivacy: .maskSensitiveInputs,
                imagePrivacy: .maskNone,
                touchPrivacy: .show,
                applicationID: "app-id",
                sessionID: "session-id",
                viewID: "view-id",
                viewServerTimeOffset: viewServerTimeOffset,
                date: date,
                telemetry: NOPTelemetry()
            )
        }
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @MainActor
    private final class TestLayerProvider: LayerProvider {
        var rootLayer: CALayer?

        init(rootLayer: CALayer?) {
            self.rootLayer = rootLayer
        }
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func capturesWebViewSlotsFromLayerTree() {
        // given
        let rootLayer = CALayer()
        rootLayer.bounds = CGRect(x: 0, y: 0, width: 320, height: 640)
        let webView = WKWebView()
        rootLayer.addSublayer(webView.layer)

        let context = Fixtures.context()
        let builder = LayerTreeSnapshotBuilder(layerProvider: TestLayerProvider(rootLayer: rootLayer))

        // when
        let snapshot = builder.createSnapshot(context: context)

        // then
        #expect(snapshot?.date == context.date.addingTimeInterval(2))
        #expect(snapshot?.viewportSize == rootLayer.bounds.size)
        #expect(snapshot?.webViewSlotIDs == Set([webView.hash]))
        #expect(snapshot?.root.children.count == 1)
        #expect(snapshot?.root.children[0].semantics == .webView(slotID: webView.hash))
        #expect(snapshot?.root.children[0].children.isEmpty == true)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func keepsDetachedWebViewSlotWhileWebViewIsAlive() {
        // given
        let rootLayer = CALayer()
        rootLayer.bounds = CGRect(x: 0, y: 0, width: 320, height: 640)
        let webView = WKWebView()
        rootLayer.addSublayer(webView.layer)

        let context = Fixtures.context()
        let builder = LayerTreeSnapshotBuilder(layerProvider: TestLayerProvider(rootLayer: rootLayer))
        let expectedSlots = Set([webView.hash])

        // when
        _ = builder.createSnapshot(context: context)
        webView.layer.removeFromSuperlayer()
        let snapshot = builder.createSnapshot(context: context)

        // then
        #expect(snapshot?.root.children.isEmpty == true)
        #expect(snapshot?.webViewSlotIDs == expectedSlots)
    }
}
#endif
