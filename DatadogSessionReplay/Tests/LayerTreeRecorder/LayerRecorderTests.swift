/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import DatadogInternal
import QuartzCore
import Testing

@_spi(Internal)
import TestUtilities
@testable import DatadogSessionReplay

@MainActor
struct LayerRecorderTests {
    @available(iOS 13.0, tvOS 13.0, *)
    typealias Fixtures = LayerTreeRecorderFixtures

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func forwardsTouchSnapshotToLayerSnapshotProcessor() async throws {
        // given
        let touchSnapshot = TouchSnapshot(
            date: Date(timeIntervalSince1970: 10),
            touches: [
                .init(
                    id: 42,
                    phase: .down,
                    date: Date(timeIntervalSince1970: 10),
                    position: CGPoint(x: 10, y: 20),
                    touchOverride: nil
                )
            ]
        )
        let snapshotBuilder = LayerTreeSnapshotBuilderSpy(
            nextSnapshot: makeLayerTreeSnapshot()
        )
        let imageRenderer = LayerImageRendererStub()
        let touchSnapshotProducer = TouchSnapshotProducerSpy(nextSnapshot: touchSnapshot)
        let snapshotProcessor = LayerSnapshotProcessorSpy()
        let recorder = LayerRecorder(
            snapshotBuilder: snapshotBuilder,
            layerImageRenderer: imageRenderer,
            uiApplicationSwizzler: .mockAny(),
            touchSnapshotProducer: touchSnapshotProducer,
            layerSnapshotProcessor: snapshotProcessor,
            timeoutInterval: 0.09,
            timeSource: .constant(0)
        )

        // when
        await recorder.scheduleRecording(.init(), context: makeContext(touchPrivacy: .show))
        let isProcessed = await waitUntil {
            snapshotProcessor.inputsCount == 1
        }

        // then
        #expect(isProcessed)
        let input = try #require(snapshotProcessor.inputs.first)
        #expect(input.touchSnapshot?.touches.count == 1)
        #expect(input.touchSnapshot?.touches.first?.id == 42)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func forwardsNilTouchSnapshotWhenProducerHasNoTouches() async throws {
        // given
        let snapshotBuilder = LayerTreeSnapshotBuilderSpy(
            nextSnapshot: makeLayerTreeSnapshot()
        )
        let imageRenderer = LayerImageRendererStub()
        let touchSnapshotProducer = TouchSnapshotProducerSpy(nextSnapshot: nil)
        let snapshotProcessor = LayerSnapshotProcessorSpy()
        let recorder = LayerRecorder(
            snapshotBuilder: snapshotBuilder,
            layerImageRenderer: imageRenderer,
            uiApplicationSwizzler: .mockAny(),
            touchSnapshotProducer: touchSnapshotProducer,
            layerSnapshotProcessor: snapshotProcessor,
            timeoutInterval: 0.09,
            timeSource: .constant(0)
        )

        // when
        await recorder.scheduleRecording(.init(), context: makeContext(touchPrivacy: .hide))
        let isProcessed = await waitUntil {
            snapshotProcessor.inputsCount == 1
        }

        // then
        #expect(isProcessed)
        let input = try #require(snapshotProcessor.inputs.first)
        #expect(input.touchSnapshot == nil)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func passesTouchPrivacyAndServerOffsetToTouchSnapshotProducer() async {
        // given
        let snapshotBuilder = LayerTreeSnapshotBuilderSpy(
            nextSnapshot: makeLayerTreeSnapshot()
        )
        let imageRenderer = LayerImageRendererStub()
        let touchSnapshotProducer = TouchSnapshotProducerSpy(nextSnapshot: nil)
        let snapshotProcessor = LayerSnapshotProcessorSpy()
        let recorder = LayerRecorder(
            snapshotBuilder: snapshotBuilder,
            layerImageRenderer: imageRenderer,
            uiApplicationSwizzler: .mockAny(),
            touchSnapshotProducer: touchSnapshotProducer,
            layerSnapshotProcessor: snapshotProcessor,
            timeoutInterval: 0.09,
            timeSource: .constant(0)
        )
        let context = makeContext(
            touchPrivacy: .hide,
            viewServerTimeOffset: 1_234
        )

        // when
        await recorder.scheduleRecording(.init(), context: context)
        _ = await waitUntil {
            snapshotProcessor.inputsCount == 1
        }

        // then
        #expect(touchSnapshotProducer.contexts.count == 1)
        #expect(touchSnapshotProducer.contexts[0].touchPrivacy == .hide)
        #expect(touchSnapshotProducer.contexts[0].viewServerTimeOffset == 1_234)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func dropsFrameWhenLayerTreeSnapshotIsUnavailable() async {
        // given
        let snapshotBuilder = LayerTreeSnapshotBuilderSpy(nextSnapshot: nil)
        let imageRenderer = LayerImageRendererStub()
        let touchSnapshotProducer = TouchSnapshotProducerSpy(nextSnapshot: nil)
        let snapshotProcessor = LayerSnapshotProcessorSpy()
        let recorder = LayerRecorder(
            snapshotBuilder: snapshotBuilder,
            layerImageRenderer: imageRenderer,
            uiApplicationSwizzler: .mockAny(),
            touchSnapshotProducer: touchSnapshotProducer,
            layerSnapshotProcessor: snapshotProcessor,
            timeoutInterval: 0.09,
            timeSource: .constant(0)
        )

        // when
        await recorder.scheduleRecording(.init(), context: makeContext())
        for _ in 0..<25 {
            await Task.yield()
        }

        // then
        #expect(snapshotProcessor.inputs.isEmpty)
    }
}

@available(iOS 13.0, tvOS 13.0, *)
private extension LayerRecorderTests {
    func makeContext(
        touchPrivacy: TouchPrivacyLevel = .show,
        viewServerTimeOffset: TimeInterval? = nil
    ) -> LayerRecordingContext {
        LayerRecordingContext(
            textAndInputPrivacy: .maskAll,
            imagePrivacy: .maskAll,
            touchPrivacy: touchPrivacy,
            applicationID: "app-id",
            sessionID: "session-id",
            viewID: "view-id",
            viewServerTimeOffset: viewServerTimeOffset,
            date: Date(timeIntervalSince1970: 1),
            telemetry: TelemetryMock()
        )
    }

    func makeLayerTreeSnapshot() -> LayerTreeSnapshot {
        let rootLayer = CALayer()
        rootLayer.bounds = CGRect(x: 0, y: 0, width: 100, height: 200)
        let root = Fixtures.snapshot(
            layer: rootLayer,
            replayID: 1,
            frame: rootLayer.bounds,
            clipRect: rootLayer.bounds,
            hasContents: true
        )

        return LayerTreeSnapshot(
            date: Date(timeIntervalSince1970: 1),
            context: makeContext(),
            viewportSize: rootLayer.bounds.size,
            root: root,
            webViewSlotIDs: []
        )
    }

    func waitUntil(
        attempts: Int = 100,
        _ condition: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        for _ in 0..<attempts {
            if await condition() {
                return true
            }
            await Task.yield()
        }
        return await condition()
    }
}

@available(iOS 13.0, tvOS 13.0, *)
@MainActor
private final class LayerTreeSnapshotBuilderSpy: LayerTreeSnapshotBuilding {
    var nextSnapshot: LayerTreeSnapshot?

    init(nextSnapshot: LayerTreeSnapshot?) {
        self.nextSnapshot = nextSnapshot
    }

    func createSnapshot(context _: LayerRecordingContext) -> LayerTreeSnapshot? {
        nextSnapshot
    }
}

@available(iOS 13.0, tvOS 13.0, *)
private final class LayerImageRendererStub: LayerImageRendering {
    var results: [Int64: LayerImageRenderer.Result] = [:]

    func renderImages(
        for _: [LayerSnapshot],
        changes _: CALayerChangeset,
        rootLayer _: CALayerReference,
        timeoutInterval _: TimeInterval
    ) async -> [Int64: LayerImageRenderer.Result] {
        results
    }
}

@available(iOS 13.0, tvOS 13.0, *)
private final class TouchSnapshotProducerSpy: TouchSnapshotProducer {
    var contexts: [TouchSnapshotContext] = []
    var nextSnapshot: TouchSnapshot?

    init(nextSnapshot: TouchSnapshot?) {
        self.nextSnapshot = nextSnapshot
    }

    func takeSnapshot(context: TouchSnapshotContext) -> TouchSnapshot? {
        contexts.append(context)
        return nextSnapshot
    }
}

@available(iOS 13.0, tvOS 13.0, *)
private final class LayerSnapshotProcessorSpy: LayerSnapshotProcessing {
    var inputs: [LayerSnapshotProcessor.Input] = []

    var inputsCount: Int {
        inputs.count
    }

    func process(_ input: LayerSnapshotProcessor.Input) async {
        inputs.append(input)
    }
}
#endif
