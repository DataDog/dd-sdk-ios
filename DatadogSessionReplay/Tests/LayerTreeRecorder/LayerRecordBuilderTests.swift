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
import Testing
@_spi(Internal)
import TestUtilities
@_spi(Internal)
@testable import DatadogSessionReplay

@Suite(.datadogTesting)
struct LayerRecordBuilderTests {
    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Meta record uses layer snapshot viewport and timestamp")
    func metaRecordUsesLayerSnapshotViewportAndTimestamp() throws {
        // Given
        let builder = LayerRecordBuilder()
        let snapshot = LayerTreeSnapshot.mockWith(
            date: Date(timeIntervalSince1970: 42),
            viewportSize: CGSize(width: 320, height: 640)
        )

        // When
        let record = builder.metaRecord(from: snapshot)

        // Then
        let metaRecord = try #require(record.metaRecord)
        #expect(metaRecord.timestamp == 42_000)
        #expect(metaRecord.data.width == 320)
        #expect(metaRecord.data.height == 640)
        #expect(metaRecord.slotId == nil)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Focus record marks the mobile view as focused")
    func focusRecordMarksMobileViewAsFocused() throws {
        // Given
        let builder = LayerRecordBuilder()
        let snapshot = LayerTreeSnapshot.mockWith(date: Date(timeIntervalSince1970: 43))

        // When
        let record = builder.focusRecord(from: snapshot)

        // Then
        let focusRecord = try #require(record.focusRecord)
        #expect(focusRecord.timestamp == 43_000)
        #expect(focusRecord.data.hasFocus)
        #expect(focusRecord.slotId == nil)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Full snapshot record includes composition tree and wireframes")
    func fullSnapshotRecordIncludesCompositionTreeAndWireframes() throws {
        // Given
        let builder = LayerRecordBuilder()
        let snapshot = LayerTreeSnapshot.mockWith(date: Date(timeIntervalSince1970: 44))
        let compositionTree = SRCompositionTree(
            layers: [.mockWith(id: 2, children: [.init(id: 42, type: .wireframe)])],
            root: .mockWith(id: 1, children: [.init(id: 2, type: .layer)])
        )
        let wireframes: [SRWireframe] = [
            .shapeWireframe(value: .mockWith(id: 42))
        ]

        // When
        let record = builder.fullSnapshotRecord(
            from: snapshot,
            compositionTree: compositionTree,
            wireframes: wireframes
        )

        // Then
        let fullSnapshotRecord = try #require(record.fullSnapshot)
        #expect(fullSnapshotRecord.timestamp == 44_000)
        #expect(fullSnapshotRecord.data.compositionTree?.root.id == 1)
        #expect(fullSnapshotRecord.data.compositionTree?.layers?.first?.id == 2)
        #expect(fullSnapshotRecord.data.wireframes.map { $0.id } == [42])
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Wireframe mutation record is nil when wireframes are unchanged")
    func wireframeMutationRecordIsNilWhenWireframesAreUnchanged() throws {
        // Given
        let builder = LayerRecordBuilder()
        let snapshot = LayerTreeSnapshot.mockWith()
        let wireframes: [SRWireframe] = [.shapeWireframe(value: .mockWith(id: 1))]

        // When
        let record = try builder.wireframeMutationRecord(
            from: snapshot,
            wireframes: wireframes,
            previousWireframes: wireframes
        )

        // Then
        #expect(record == nil)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Wireframe mutation record includes additions, removals, and updates")
    func wireframeMutationRecordIncludesAdditionsRemovalsAndUpdates() throws {
        // Given
        let builder = LayerRecordBuilder()
        let snapshot = LayerTreeSnapshot.mockWith(date: Date(timeIntervalSince1970: 45))
        let previousWireframes: [SRWireframe] = [
            .shapeWireframe(value: .mockWith(height: 100, id: 1, width: 200)),
            .shapeWireframe(value: .mockWith(id: 2))
        ]
        let wireframes: [SRWireframe] = [
            .shapeWireframe(value: .mockWith(height: 120, id: 1, width: 200)),
            .shapeWireframe(value: .mockWith(id: 3))
        ]

        // When
        let record = try #require(try builder.wireframeMutationRecord(
            from: snapshot,
            wireframes: wireframes,
            previousWireframes: previousWireframes
        ))

        // Then
        let incrementalRecord = try #require(record.incrementalSnapshot)
        let mutationData = try #require(incrementalRecord.mutationData)

        #expect(incrementalRecord.timestamp == 45_000)
        #expect(mutationData.adds.count == 1)
        #expect(mutationData.adds.first?.previousId == 1)
        #expect(mutationData.adds.first?.wireframe.id == 3)
        #expect(mutationData.removes.map { $0.id } == [2])

        let update = try #require(mutationData.updates.first)
        guard case let .shapeWireframeUpdate(shapeUpdate) = update else {
            Issue.record("Expected a shape wireframe update.")
            return
        }
        #expect(shapeUpdate.id == 1)
        #expect(shapeUpdate.height == 120)
        #expect(shapeUpdate.width == nil)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Composition tree mutation record is nil when the composition tree is unchanged")
    func compositionTreeMutationRecordIsNilWhenCompositionTreeIsUnchanged() throws {
        // Given
        let builder = LayerRecordBuilder()
        let snapshot = LayerTreeSnapshot.mockWith()
        let compositionTree = SRCompositionTree(
            root: .mockWith(id: 1, children: [])
        )

        // When
        let record = try builder.compositionTreeMutationRecord(
            from: snapshot,
            compositionTree: compositionTree,
            previousCompositionTree: compositionTree
        )

        // Then
        #expect(record == nil)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Composition tree mutation record includes composition tree mutation data")
    func compositionTreeMutationRecordIncludesCompositionTreeMutationData() throws {
        // Given
        let builder = LayerRecordBuilder()
        let snapshot = LayerTreeSnapshot.mockWith(date: Date(timeIntervalSince1970: 46))
        let previousCompositionTree = SRCompositionTree(
            layers: [.mockWith(id: 2, children: [])],
            root: .mockWith(id: 1, children: [.init(id: 2, type: .layer)])
        )
        let addedLayer = SRCompositionLayer.mockWith(id: 3, children: [])
        let compositionTree = SRCompositionTree(
            layers: [
                .mockWith(id: 2, children: [.init(id: 42, type: .wireframe)]),
                addedLayer
            ],
            root: .mockWith(id: 1, children: [
                .init(id: 2, type: .layer),
                .init(id: 3, type: .layer)
            ])
        )

        // When
        let record = try #require(try builder.compositionTreeMutationRecord(
            from: snapshot,
            compositionTree: compositionTree,
            previousCompositionTree: previousCompositionTree
        ))

        // Then
        let incrementalRecord = try #require(record.incrementalSnapshot)
        let mutationData = try #require(incrementalRecord.compositionTreeMutationData)

        #expect(incrementalRecord.timestamp == 46_000)
        #expect(mutationData.root?.children.map { $0.id } == [2, 3])
        #expect(mutationData.adds?.map { $0.id } == [3])
        #expect(mutationData.removes == nil)
        #expect(mutationData.updates?.count == 1)
        #expect(mutationData.updates?.first?.id == 2)
        #expect(mutationData.updates?.first?.children?.map { $0.id } == [42])
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Touch records map touches to pointer interaction records")
    func touchRecordsMapTouchesToPointerInteractionRecords() throws {
        // Given
        let builder = LayerRecordBuilder()
        let snapshot = TouchSnapshot(
            date: Date(timeIntervalSince1970: 47),
            touches: [
                .init(id: 1, phase: .down, date: Date(), position: CGPoint(x: 10.2, y: 20.6), touchOverride: nil),
                .init(id: 2, phase: .move, date: Date(), position: CGPoint(x: 30.5, y: 40.4), touchOverride: nil),
                .init(id: 3, phase: .up, date: Date(), position: CGPoint(x: 50.1, y: 60.9), touchOverride: nil)
            ]
        )

        // When
        let records = builder.touchRecords(from: snapshot)

        // Then
        let pointerData: [SRIncrementalSnapshotRecord.Data.PointerInteractionData] = try records.map {
            try #require($0.incrementalSnapshot?.pointerInteractionData)
        }

        #expect(records.map { $0.timestamp } == [47_000, 47_000, 47_000])
        #expect(pointerData.map { $0.pointerId } == [1, 2, 3])
        #expect(pointerData.map { $0.pointerEventType } == [
            SRIncrementalSnapshotRecord.Data.PointerInteractionData.PointerEventType.down,
            .move,
            .up
        ])
        #expect(pointerData.map { $0.pointerType } == [
            SRIncrementalSnapshotRecord.Data.PointerInteractionData.PointerType.touch,
            .touch,
            .touch
        ])
        #expect(pointerData.map { $0.x } == [10, 31, 50])
        #expect(pointerData.map { $0.y } == [21, 40, 61])
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Viewport record follows aspect ratio changes")
    func viewportRecordFollowsAspectRatioChanges() throws {
        // Given
        let builder = LayerRecordBuilder()
        let previousSnapshot = LayerTreeSnapshot.mockWith(
            viewportSize: CGSize(width: 100, height: 200)
        )
        let sameAspectRatioSnapshot = LayerTreeSnapshot.mockWith(
            viewportSize: CGSize(width: 150, height: 300)
        )
        let changedAspectRatioSnapshot = LayerTreeSnapshot.mockWith(
            date: Date(timeIntervalSince1970: 48),
            viewportSize: CGSize(width: 300, height: 200)
        )

        // When
        let unchangedRecord = builder.viewportRecord(
            from: sameAspectRatioSnapshot,
            previousSnapshot: previousSnapshot
        )
        let changedRecord = builder.viewportRecord(
            from: changedAspectRatioSnapshot,
            previousSnapshot: previousSnapshot
        )

        // Then
        #expect(unchangedRecord == nil)

        let viewportRecord = try #require(changedRecord?.incrementalSnapshot)
        let viewportData = try #require(viewportRecord.viewportResizeData)
        #expect(viewportRecord.timestamp == 48_000)
        #expect(viewportData.width == 300)
        #expect(viewportData.height == 200)
    }
}

@available(iOS 13.0, tvOS 13.0, *)
private extension SRCompositionLayer {
    static func mockWith(
        id: Int64,
        children: [SRCompositionLayerChild]
    ) -> SRCompositionLayer {
        return SRCompositionLayer(
            children: children,
            height: 100,
            id: id,
            width: 200,
            x: 10,
            y: 20
        )
    }
}

private extension SRRecord {
    var metaRecord: SRMetaRecord? {
        guard case let .metaRecord(record) = self else {
            return nil
        }
        return record
    }

    var focusRecord: SRFocusRecord? {
        guard case let .focusRecord(record) = self else {
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
}

#endif
