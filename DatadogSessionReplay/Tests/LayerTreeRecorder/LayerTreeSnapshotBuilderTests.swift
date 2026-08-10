/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
@_spi(Internal)
import DatadogInternal
import QuartzCore
import TestUtilities
import Testing
import WebKit

@testable import DatadogSessionReplay

@Suite(.datadogTesting)
@MainActor
struct LayerTreeSnapshotBuilderTests {
    @available(iOS 13.0, tvOS 13.0, *)
    enum Fixtures {
        struct NOPTelemetry: Telemetry {
            func send(telemetry: TelemetryMessage) {}
        }

        static func context(
            textAndInputPrivacy: TextAndInputPrivacyLevel = .maskSensitiveInputs,
            imagePrivacy: ImagePrivacyLevel = .maskNone,
            touchPrivacy: TouchPrivacyLevel = .show,
            viewServerTimeOffset: TimeInterval? = 2,
            date: Date = Date(timeIntervalSince1970: 10)
        ) -> LayerRecordingContext {
            LayerRecordingContext(
                textAndInputPrivacy: textAndInputPrivacy,
                imagePrivacy: imagePrivacy,
                touchPrivacy: touchPrivacy,
                applicationID: "app-id",
                sessionID: "session-id",
                viewID: "view-id",
                viewServerTimeOffset: viewServerTimeOffset,
                viewPath: "/view",
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
    @Test("Returns nil when root layer is unavailable")
    func returnsNilWhenRootLayerIsUnavailable() {
        // Given
        let builder = LayerTreeSnapshotBuilder(layerProvider: TestLayerProvider(rootLayer: nil))

        // When
        let snapshot = builder.takeSnapshot(context: Fixtures.context())

        // Then
        #expect(snapshot == nil)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Captures snapshot with recording context")
    func capturesSnapshotWithRecordingContext() throws {
        // Given
        let rootLayer = CALayer()
        rootLayer.bounds = CGRect(x: 0, y: 0, width: 320, height: 640)

        let childLayer = CALayer()
        childLayer.frame = CGRect(x: 10, y: 20, width: 30, height: 40)
        rootLayer.addSublayer(childLayer)

        let context = Fixtures.context(
            textAndInputPrivacy: .maskAll,
            imagePrivacy: .maskAll,
            viewServerTimeOffset: 3,
            date: Date(timeIntervalSince1970: 12)
        )
        let builder = LayerTreeSnapshotBuilder(layerProvider: TestLayerProvider(rootLayer: rootLayer))

        // When
        let snapshot = try #require(builder.takeSnapshot(context: context))

        // Then
        #expect(snapshot.date == Date(timeIntervalSince1970: 15))
        #expect(snapshot.context.applicationID == "app-id")
        #expect(snapshot.context.sessionID == "session-id")
        #expect(snapshot.context.viewID == "view-id")
        #expect(snapshot.context.viewPath == "/view")
        #expect(snapshot.viewportSize == rootLayer.bounds.size)
        #expect(snapshot.root.layer.matches(rootLayer))
        #expect(snapshot.root.textAndInputPrivacyLevel == .maskAll)
        #expect(snapshot.root.imagePrivacyLevel == .maskAll)
        #expect(snapshot.root.sublayers.first?.layer.matches(childLayer) == true)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Captures web view slot IDs from layer tree")
    func capturesWebViewSlotIDsFromLayerTree() throws {
        // Given
        let rootLayer = CALayer()
        rootLayer.bounds = CGRect(x: 0, y: 0, width: 320, height: 640)

        let webView = WKWebView()
        rootLayer.addSublayer(webView.layer)

        let builder = LayerTreeSnapshotBuilder(layerProvider: TestLayerProvider(rootLayer: rootLayer))

        // When
        let snapshot = try #require(builder.takeSnapshot(context: Fixtures.context()))

        // Then
        #expect(snapshot.webViewSlotIDs == Set([webView.hash]))
        #expect(snapshot.root.sublayers.count == 1)
        let webViewSnapshot = snapshot.root.sublayers[0]
        #expect(
            webViewSnapshot.observation == .init(
                semantics: .webView(.init(slotID: webView.hash, slotFrame: webViewSnapshot.absoluteFrame)),
                ignoresSublayers: true
            )
        )
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Keeps detached web view slot while web view is alive")
    func keepsDetachedWebViewSlotWhileWebViewIsAlive() throws {
        // Given
        let rootLayer = CALayer()
        rootLayer.bounds = CGRect(x: 0, y: 0, width: 320, height: 640)

        let webView = WKWebView()
        rootLayer.addSublayer(webView.layer)

        let builder = LayerTreeSnapshotBuilder(layerProvider: TestLayerProvider(rootLayer: rootLayer))
        let expectedSlots = Set([webView.hash])

        // When
        _ = builder.takeSnapshot(context: Fixtures.context())
        webView.layer.removeFromSuperlayer()
        let snapshot = try #require(builder.takeSnapshot(context: Fixtures.context()))

        // Then
        #expect(snapshot.root.sublayers.isEmpty)
        #expect(snapshot.webViewSlotIDs == expectedSlots)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Captures embedded content as a leaf and keeps its slot while detached")
    func capturesEmbeddedContentAsLeafAndKeepsItsSlotWhileDetached() throws {
        // Given
        let rootView = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        let embeddedContentView = UILabel(frame: CGRect(x: 10, y: 20, width: 100, height: 80))
        embeddedContentView.text = "Native label"
        embeddedContentView.dd.setSessionReplaySlotID("embedded-slot")
        embeddedContentView.addSubview(UIView(frame: embeddedContentView.bounds))
        rootView.addSubview(embeddedContentView)

        let builder = LayerTreeSnapshotBuilder(
            layerProvider: TestLayerProvider(rootLayer: rootView.layer)
        )

        // When
        let initialSnapshot = try #require(builder.takeSnapshot(context: Fixtures.context()))
        embeddedContentView.removeFromSuperview()
        let detachedSnapshot = try #require(builder.takeSnapshot(context: Fixtures.context()))

        // Then
        let embeddedContentSnapshot = try #require(initialSnapshot.root.sublayers.first)
        #expect(
            embeddedContentSnapshot.observation == .init(
                semantics: .embeddedContent(.init(slotID: "embedded-slot")),
                ignoresSublayers: true
            )
        )
        #expect(embeddedContentSnapshot.sublayers.isEmpty)
        #expect(initialSnapshot.embeddedContentSlots == [embeddedContentView.layer.replayID: "embedded-slot"])
        #expect(detachedSnapshot.root.sublayers.isEmpty)
        #expect(detachedSnapshot.embeddedContentSlots == initialSnapshot.embeddedContentSlots)
        withExtendedLifetime(embeddedContentView) {}
    }
}
#endif
