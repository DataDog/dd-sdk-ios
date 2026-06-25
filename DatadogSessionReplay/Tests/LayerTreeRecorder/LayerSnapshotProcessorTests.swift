/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import CoreGraphics
@_spi(Internal)
import DatadogInternal
import QuartzCore
import Testing
@_spi(Internal)
import TestUtilities
import UIKit
@_spi(Internal)
@testable import DatadogSessionReplay

struct LayerSnapshotProcessorTests {
    @available(iOS 13.0, tvOS 13.0, *)
    @Test("First layer tree snapshot starts a segment and processes resources")
    func firstLayerTreeSnapshotStartsSegmentAndProcessesResources() throws {
        // Given
        let fixture = Fixture()
        let leaf = CALayerSnapshot.mockWith(
            replayID: 2,
            absoluteFrame: CGRect(x: 10, y: 20, width: 30, height: 40)
        )
        let snapshot = LayerTreeSnapshot.mockWith(root: .mockRoot(sublayers: [leaf]))
        let imageSnapshot = ImageSnapshot.mockAny(
            image: .mockWith(color: .red),
            frame: leaf.absoluteFrame,
            hasLayerSemantics: false,
            imagePrivacyLevel: .maskNone
        )

        // When
        fixture.processor.process(
            layerTreeSnapshot: snapshot,
            imageSnapshotResults: [2: .success(imageSnapshot)],
            touchSnapshot: nil
        )

        // Then
        let enrichedRecord = try #require(fixture.recordWriter.records.first)
        #expect(fixture.recordWriter.records.count == 1)
        #expect(enrichedRecord.records.map(\.type) == [.meta, .focus, .fullSnapshot])
        #expect(enrichedRecord.records[2].fullSnapshot?.data.wireframes.count == 1)

        #expect(fixture.resourceProcessor.processedResources.count == 1)
        #expect(fixture.resourceProcessor.resources.count == 1)
        #expect(fixture.resourceProcessor.processedResources.first?.context.application.id == "app-id")
        #expect(fixture.core.recordsCountByViewID == ["view-id": 3])
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Same context writes wireframe, composition tree, viewport, and touch records in order")
    func sameContextWritesMutationViewportAndTouchRecordsInOrder() throws {
        // Given
        let fixture = Fixture()
        let firstSnapshot = LayerTreeSnapshot.mockWith(
            date: Date(timeIntervalSince1970: 1),
            viewportSize: CGSize(width: 100, height: 200),
            root: .mockRoot(sublayers: [
                .mockWith(
                    replayID: 2,
                    absoluteFrame: CGRect(x: 0, y: 0, width: 10, height: 10),
                    backgroundColor: UIColor.red.cgColor
                )
            ])
        )
        let secondSnapshot = LayerTreeSnapshot.mockWith(
            date: Date(timeIntervalSince1970: 2),
            viewportSize: CGSize(width: 200, height: 100),
            root: .mockRoot(
                absoluteFrame: CGRect(x: 0, y: 0, width: 200, height: 100),
                sublayers: [
                    .mockWith(
                        replayID: 2,
                        absoluteFrame: CGRect(x: 0, y: 0, width: 20, height: 10),
                        backgroundColor: UIColor.red.cgColor
                    ),
                    .mockWith(
                        replayID: 3,
                        absoluteFrame: CGRect(x: 20, y: 0, width: 10, height: 10),
                        backgroundColor: UIColor.blue.cgColor
                    )
                ]
            )
        )
        let touchSnapshot = TouchSnapshot(
            date: Date(timeIntervalSince1970: 2),
            touches: [
                .init(id: 42, phase: .down, date: Date(), position: CGPoint(x: 12, y: 34), touchOverride: nil)
            ]
        )

        // When
        fixture.processor.process(layerTreeSnapshot: firstSnapshot, imageSnapshotResults: [:], touchSnapshot: nil)
        fixture.processor.process(layerTreeSnapshot: secondSnapshot, imageSnapshotResults: [:], touchSnapshot: touchSnapshot)

        // Then
        let enrichedRecord = try #require(fixture.recordWriter.records.last)
        #expect(enrichedRecord.records.map(\.type) == [
            .incrementalSnapshot,
            .incrementalSnapshot,
            .incrementalSnapshot,
            .incrementalSnapshot
        ])

        #expect(enrichedRecord.records[0].incrementalSnapshot?.mutationData != nil)
        #expect(enrichedRecord.records[1].incrementalSnapshot?.compositionTreeMutationData != nil)
        #expect(enrichedRecord.records[2].incrementalSnapshot?.viewportResizeData != nil)
        #expect(enrichedRecord.records[3].incrementalSnapshot?.pointerInteractionData != nil)
        #expect(fixture.core.recordsCountByViewID == ["view-id": 7])
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("RUM context change starts a new segment")
    func rumContextChangeStartsNewSegment() throws {
        // Given
        let fixture = Fixture()
        let firstSnapshot = LayerTreeSnapshot.mockWith(viewID: "view-1")
        let secondSnapshot = LayerTreeSnapshot.mockWith(viewID: "view-2")

        // When
        fixture.processor.process(layerTreeSnapshot: firstSnapshot, imageSnapshotResults: [:], touchSnapshot: nil)
        fixture.processor.process(layerTreeSnapshot: secondSnapshot, imageSnapshotResults: [:], touchSnapshot: nil)

        // Then
        let enrichedRecord = try #require(fixture.recordWriter.records.last)
        #expect(fixture.recordWriter.records.count == 2)
        #expect(enrichedRecord.viewID == "view-2")
        #expect(enrichedRecord.records.map(\.type) == [.meta, .focus, .fullSnapshot])
        #expect(fixture.core.recordsCountByViewID == ["view-1": 3, "view-2": 3])
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Diffing errors fall back to a full snapshot and update state")
    func diffingErrorsFallBackToFullSnapshotAndUpdateState() throws {
        // Given
        let fixture = Fixture()
        let shapeSnapshot = LayerTreeSnapshot.mockWith(root: .mockRoot(sublayers: [
            .mockWith(
                replayID: 2,
                absoluteFrame: CGRect(x: 0, y: 0, width: 10, height: 10),
                backgroundColor: UIColor.red.cgColor
            )
        ]))
        let privateSnapshot = LayerTreeSnapshot.mockWith(root: .mockRoot(sublayers: [
            .mockWith(
                replayID: 2,
                absoluteFrame: CGRect(x: 0, y: 0, width: 10, height: 10),
                isPrivate: true
            )
        ]))

        // When
        fixture.processor.process(layerTreeSnapshot: shapeSnapshot, imageSnapshotResults: [:], touchSnapshot: nil)
        fixture.processor.process(layerTreeSnapshot: privateSnapshot, imageSnapshotResults: [:], touchSnapshot: nil)
        fixture.processor.process(layerTreeSnapshot: privateSnapshot, imageSnapshotResults: [:], touchSnapshot: nil)

        // Then
        #expect(fixture.recordWriter.records.count == 2)
        #expect(fixture.recordWriter.records[1].records.map(\.type) == [.fullSnapshot])
        #expect(
            fixture.telemetry.messages.firstError()?.message.hasPrefix(
                "[SR] Failed to build layer recording mutation records"
            ) == true
        )
        #expect(fixture.core.recordsCountByViewID == ["view-id": 4])
    }
}

private extension LayerSnapshotProcessorTests {
    @available(iOS 13.0, tvOS 13.0, *)
    final class Fixture {
        let core = PassthroughCoreMock()
        let recordWriter = RecordWriterMock()
        let resourceProcessor = ResourceProcessorSpy()
        let telemetry = TelemetryMock()
        let processor: LayerSnapshotProcessor

        init() {
            processor = LayerSnapshotProcessor(
                queue: NoQueue(),
                recordWriter: recordWriter,
                resourceProcessor: resourceProcessor,
                replayContextPublisher: SRContextPublisher(core: core),
                telemetry: telemetry
            )
        }
    }
}

private final class RecordWriterMock: RecordWriting {
    var records: [EnrichedRecord] = []

    func write(nextRecord: EnrichedRecord) {
        records.append(nextRecord)
    }
}

@available(iOS 13.0, tvOS 13.0, *)
private extension LayerTreeSnapshot {
    static func mockWith(
        date: Date = Date(timeIntervalSince1970: 1),
        applicationID: String = "app-id",
        sessionID: String = "session-id",
        viewID: String = "view-id",
        viewportSize: CGSize = CGSize(width: 100, height: 200),
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
                telemetry: TelemetryMock()
            ),
            viewportSize: viewportSize,
            root: root,
            webViewSlotIDs: webViewSlotIDs
        )
    }
}

@available(iOS 13.0, tvOS 13.0, *)
private extension CALayerSnapshot {
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
        replayID: Int64,
        absoluteFrame: CGRect,
        backgroundColor: CGColor? = nil,
        isPrivate: Bool = false,
        sublayers: [CALayerSnapshot] = []
    ) -> CALayerSnapshot {
        let layer = CALayer()
        return CALayerSnapshot(
            layer: CALayerReference(layer),
            replayID: replayID,
            observation: .init(semantics: .layer),
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

private extension PassthroughCoreMock {
    var recordsCountByViewID: [String: Int64]? {
        context.additionalContext(
            ofType: SessionReplayCoreContext.RecordsCount.self
        )?.value
    }
}

private extension SRRecord {
    enum RecordType: Equatable {
        case meta
        case focus
        case fullSnapshot
        case incrementalSnapshot
        case other
    }

    var type: RecordType {
        switch self {
        case .metaRecord:
            return .meta
        case .focusRecord:
            return .focus
        case .fullSnapshotRecord:
            return .fullSnapshot
        case .incrementalSnapshotRecord:
            return .incrementalSnapshot
        case .viewEndRecord, .visualViewportRecord:
            return .other
        }
    }

    var fullSnapshot: SRFullSnapshotRecord? {
        guard case let .fullSnapshotRecord(record) = self else {
            return nil
        }
        return record
    }

    var incrementalSnapshot: SRIncrementalSnapshotRecord? {
        guard case let .incrementalSnapshotRecord(record) = self else {
            return nil
        }
        return record
    }
}

private extension SRIncrementalSnapshotRecord {
    var mutationData: SRIncrementalSnapshotRecord.Data.MutationData? {
        guard case let .mutationData(data) = self.data else {
            return nil
        }
        return data
    }

    var compositionTreeMutationData: SRCompositionTreeMutationData? {
        guard case let .compositionTreeMutationData(data) = self.data else {
            return nil
        }
        return data
    }

    var viewportResizeData: SRIncrementalSnapshotRecord.Data.ViewportResizeData? {
        guard case let .viewportResizeData(data) = self.data else {
            return nil
        }
        return data
    }

    var pointerInteractionData: SRIncrementalSnapshotRecord.Data.PointerInteractionData? {
        guard case let .pointerInteractionData(data) = self.data else {
            return nil
        }
        return data
    }
}
#endif
