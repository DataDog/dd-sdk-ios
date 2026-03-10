/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import DatadogInternal
import Testing
import UIKit

@_spi(Internal)
import TestUtilities
@_spi(Internal)
@testable import DatadogSessionReplay

@MainActor
struct LayerSnapshotProcessorTests {
    @available(iOS 13.0, tvOS 13.0, *)
    typealias Fixtures = LayerTreeRecorderFixtures

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func firstSnapshotStartsSegmentWithMetaFocusAndFullSnapshot() async throws {
        // given
        let date = Date(timeIntervalSince1970: 1)
        let core = PassthroughCoreMock()
        let recordWriter = RecordWriterSpy()
        let resourceProcessor = LayerResourceProcessorSpy()
        let processor = makeProcessor(
            recordWriter: recordWriter,
            resourceProcessor: resourceProcessor,
            core: core
        )

        let input = makeInput(
            date: date,
            targetSnapshots: [
                Fixtures.snapshot(
                    replayID: 1,
                    frame: CGRect(x: 10, y: 20, width: 80, height: 40),
                    clipRect: CGRect(x: 0, y: 0, width: 100, height: 200),
                    backgroundColor: UIColor.red.cgColor
                )
            ]
        )

        // when
        await processor.process(input)

        // then
        let enrichedRecord = try #require(recordWriter.records.first)
        #expect(recordWriter.records.count == 1)
        #expect(enrichedRecord.records.count == 3)
        #expect(enrichedRecord.records[0].isMetaRecord)
        #expect(enrichedRecord.records[1].isFocusRecord)
        #expect(enrichedRecord.records[2].isFullSnapshotRecord)
        #expect(core.recordsCountByViewID == ["view-id": 3])
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func sameContextProducesIncrementalSnapshot() async throws {
        // given
        let date = Date(timeIntervalSince1970: 1)
        let core = PassthroughCoreMock()
        let recordWriter = RecordWriterSpy()
        let resourceProcessor = LayerResourceProcessorSpy()
        let processor = makeProcessor(
            recordWriter: recordWriter,
            resourceProcessor: resourceProcessor,
            core: core
        )

        let firstInput = makeInput(
            date: date,
            targetSnapshots: [
                Fixtures.snapshot(
                    replayID: 1,
                    frame: CGRect(x: 10, y: 20, width: 80, height: 40),
                    clipRect: CGRect(x: 0, y: 0, width: 100, height: 200),
                    backgroundColor: UIColor.red.cgColor
                )
            ]
        )
        let secondInput = makeInput(
            date: date.addingTimeInterval(1),
            targetSnapshots: [
                Fixtures.snapshot(
                    replayID: 1,
                    frame: CGRect(x: 20, y: 20, width: 80, height: 40),
                    clipRect: CGRect(x: 0, y: 0, width: 100, height: 200),
                    backgroundColor: UIColor.red.cgColor
                )
            ]
        )

        // when
        await processor.process(firstInput)
        await processor.process(secondInput)

        // then
        let secondEnrichedRecord = try #require(recordWriter.records.last)
        #expect(recordWriter.records.count == 2)
        #expect(secondEnrichedRecord.records.count == 1)
        #expect(secondEnrichedRecord.records[0].isIncrementalSnapshotRecord)
        #expect(core.recordsCountByViewID == ["view-id": 4])
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func orientationChangeProducesViewportResizeRecord() async throws {
        // given
        let date = Date(timeIntervalSince1970: 1)
        let core = PassthroughCoreMock()
        let recordWriter = RecordWriterSpy()
        let resourceProcessor = LayerResourceProcessorSpy()
        let processor = makeProcessor(
            recordWriter: recordWriter,
            resourceProcessor: resourceProcessor,
            core: core
        )

        let targetSnapshot = Fixtures.snapshot(
            replayID: 1,
            frame: CGRect(x: 10, y: 20, width: 80, height: 40),
            clipRect: CGRect(x: 0, y: 0, width: 100, height: 200),
            backgroundColor: UIColor.red.cgColor
        )

        let firstInput = makeInput(
            date: date,
            targetSnapshots: [targetSnapshot],
            viewportSize: CGSize(width: 100, height: 200)
        )
        let secondInput = makeInput(
            date: date.addingTimeInterval(1),
            targetSnapshots: [targetSnapshot],
            viewportSize: CGSize(width: 200, height: 100)
        )

        // when
        await processor.process(firstInput)
        await processor.process(secondInput)

        // then
        let secondEnrichedRecord = try #require(recordWriter.records.last)
        let viewportResize = try #require(secondEnrichedRecord.records[0].incrementalSnapshot?.viewportResizeData)

        #expect(recordWriter.records.count == 2)
        #expect(secondEnrichedRecord.records.count == 1)
        #expect(viewportResize.width == 200)
        #expect(viewportResize.height == 100)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func touchSnapshotAppendsPointerInteractionRecords() async throws {
        // given
        let date = Date(timeIntervalSince1970: 1)
        let core = PassthroughCoreMock()
        let recordWriter = RecordWriterSpy()
        let resourceProcessor = LayerResourceProcessorSpy()
        let processor = makeProcessor(
            recordWriter: recordWriter,
            resourceProcessor: resourceProcessor,
            core: core
        )

        let touchSnapshot = TouchSnapshot(
            date: date,
            touches: [
                .init(
                    id: 1,
                    phase: .down,
                    date: date,
                    position: CGPoint(x: 10, y: 20),
                    touchOverride: nil
                )
            ]
        )
        let input = makeInput(
            date: date,
            targetSnapshots: [
                Fixtures.snapshot(
                    replayID: 1,
                    frame: CGRect(x: 10, y: 20, width: 80, height: 40),
                    clipRect: CGRect(x: 0, y: 0, width: 100, height: 200),
                    backgroundColor: UIColor.red.cgColor
                )
            ],
            touchSnapshot: touchSnapshot
        )

        // when
        await processor.process(input)

        // then
        let enrichedRecord = try #require(recordWriter.records.first)
        let pointerInteraction = try #require(enrichedRecord.records.last?.incrementalSnapshot?.pointerInteractionData)

        #expect(enrichedRecord.records.count == 4)
        #expect(pointerInteraction.pointerType == .touch)
        #expect(pointerInteraction.pointerEventType == .down)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func producedResourcesAreForwardedWithApplicationContext() async {
        // given
        let date = Date(timeIntervalSince1970: 1)
        let core = PassthroughCoreMock()
        let recordWriter = RecordWriterSpy()
        let resourceProcessor = LayerResourceProcessorSpy()
        let processor = makeProcessor(
            recordWriter: recordWriter,
            resourceProcessor: resourceProcessor,
            core: core
        )

        let snapshot = Fixtures.snapshot(
            replayID: 42,
            frame: CGRect(x: 10, y: 20, width: 80, height: 40),
            clipRect: CGRect(x: 0, y: 0, width: 100, height: 200)
        )
        let image = UIImage(cgImage: Fixtures.anyImage)
        let layerImage = LayerImage(
            resource: .init(image: image, tintColor: nil),
            frame: snapshot.frame
        )
        let input = makeInput(
            date: date,
            targetSnapshots: [snapshot],
            layerImages: [snapshot.replayID: .success(layerImage)]
        )

        // when
        await processor.process(input)

        // then
        #expect(resourceProcessor.inputs.count == 1)
        #expect(resourceProcessor.inputs[0].resources.count == 1)
        #expect(resourceProcessor.inputs[0].context.application.id == "app-id")
    }
}

@available(iOS 13.0, tvOS 13.0, *)
private extension LayerSnapshotProcessorTests {
    func makeProcessor(
        recordWriter: any RecordWriting,
        resourceProcessor: any LayerResourceProcessing,
        core: DatadogCoreProtocol
    ) -> LayerSnapshotProcessor {
        LayerSnapshotProcessor(
            recordWriter: recordWriter,
            contextPublisher: SRContextPublisher(core: core),
            resourceProcessor: resourceProcessor,
            telemetry: TelemetryMock()
        )
    }

    func makeInput(
        date: Date,
        targetSnapshots: [LayerSnapshot],
        layerImages: [Int64: LayerImageRenderer.Result] = [:],
        touchSnapshot: TouchSnapshot? = nil,
        viewportSize: CGSize = CGSize(width: 100, height: 200),
        applicationID: String = "app-id",
        sessionID: String = "session-id",
        viewID: String = "view-id"
    ) -> LayerSnapshotProcessor.Input {
        let context = LayerRecordingContext(
            textAndInputPrivacy: .maskAll,
            imagePrivacy: .maskAll,
            touchPrivacy: .hide,
            applicationID: applicationID,
            sessionID: sessionID,
            viewID: viewID,
            viewServerTimeOffset: nil,
            date: date,
            telemetry: TelemetryMock()
        )
        let root = Fixtures.snapshot(
            replayID: 0,
            frame: CGRect(origin: .zero, size: viewportSize),
            clipRect: CGRect(origin: .zero, size: viewportSize)
        )
        let layerTreeSnapshot = LayerTreeSnapshot(
            date: date,
            context: context,
            viewportSize: viewportSize,
            root: root,
            webViewSlotIDs: []
        )

        return .init(
            layerTreeSnapshot: layerTreeSnapshot,
            targetSnapshots: targetSnapshots,
            layerImages: layerImages,
            touchSnapshot: touchSnapshot
        )
    }
}

@available(iOS 13.0, tvOS 13.0, *)
private final class RecordWriterSpy: RecordWriting {
    var records: [EnrichedRecord] = []

    func write(nextRecord: EnrichedRecord) {
        records.append(nextRecord)
    }
}

@available(iOS 13.0, tvOS 13.0, *)
private final class LayerResourceProcessorSpy: LayerResourceProcessing {
    var inputs: [ResourceProcessor.Input] = []

    func process(_ input: ResourceProcessor.Input) async {
        inputs.append(input)
    }
}

fileprivate extension PassthroughCoreMock {
    var recordsCountByViewID: [String: Int64]? {
        self.context.additionalContext(
            ofType: SessionReplayCoreContext.RecordsCount.self
        )?.value
    }
}
#endif
