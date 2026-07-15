/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import DatadogInternal

@available(iOS 13.0, tvOS 13.0, *)
internal struct LayerRecordBuilder {
    func metaRecord(from snapshot: LayerTreeSnapshot) -> SRRecord {
        let record = SRMetaRecord(
            data: .init(
                height: Int64.ddWithNoOverflow(snapshot.viewportSize.height),
                href: nil,
                width: Int64.ddWithNoOverflow(snapshot.viewportSize.width)
            ),
            slotId: nil,
            timestamp: snapshot.date.timeIntervalSince1970.dd.toInt64Milliseconds
        )
        return .metaRecord(value: record)
    }

    func focusRecord(from snapshot: LayerTreeSnapshot) -> SRRecord {
        let record = SRFocusRecord(
            data: .init(hasFocus: true),
            slotId: nil,
            timestamp: snapshot.date.timeIntervalSince1970.dd.toInt64Milliseconds
        )
        return .focusRecord(value: record)
    }

    func fullSnapshotRecord(
        from snapshot: LayerTreeSnapshot,
        compositionTree: SRCompositionTree,
        wireframes: [SRWireframe]
    ) -> SRRecord {
        let record = SRFullSnapshotRecord(
            data: .init(
                compositionTree: compositionTree,
                wireframes: wireframes
            ),
            timestamp: snapshot.date.timeIntervalSince1970.dd.toInt64Milliseconds
        )
        return .fullSnapshotRecord(value: record)
    }

    func wireframeMutationRecord(
        from snapshot: LayerTreeSnapshot,
        wireframes: [SRWireframe],
        previousWireframes: [SRWireframe]
    ) throws -> SRRecord? {
        let diff = try computeDiff(oldArray: previousWireframes, newArray: wireframes)

        guard !diff.isEmpty else {
            return nil
        }

        let record = SRIncrementalSnapshotRecord(
            data: .mutationData(
                value: .init(
                    adds: diff.adds.map { addition in
                        .init(previousId: addition.previousID, wireframe: addition.new)
                    },
                    removes: diff.removes.map { removal in
                        .init(id: removal.id)
                    },
                    updates: try diff.updates.map { update in
                        try update.to.mutations(from: update.from)
                    }
                )
            ),
            timestamp: snapshot.date.timeIntervalSince1970.dd.toInt64Milliseconds
        )

        return .incrementalSnapshotRecord(value: record)
    }

    func compositionTreeMutationRecord(
        from snapshot: LayerTreeSnapshot,
        compositionTree: SRCompositionTree,
        previousCompositionTree: SRCompositionTree
    ) throws -> SRRecord? {
        guard let mutation = try compositionTree.mutations(from: previousCompositionTree) else {
            return nil
        }

        let record = SRIncrementalSnapshotRecord(
            data: .compositionTreeMutationData(value: mutation),
            timestamp: snapshot.date.timeIntervalSince1970.dd.toInt64Milliseconds
        )

        return .incrementalSnapshotRecord(value: record)
    }

    func touchRecords(from snapshot: TouchSnapshot) -> [SRRecord] {
        return snapshot.touches.map { touch in
            let record = SRIncrementalSnapshotRecord(
                data: .pointerInteractionData(
                    value: .init(
                        pointerEventType: {
                            switch touch.phase {
                            case .down: return .down
                            case .move: return .move
                            case .up: return .up
                            }
                        }(),
                        pointerId: touch.id,
                        pointerType: .touch,
                        x: round(touch.position.x),
                        y: round(touch.position.y)
                    )
                ),
                timestamp: snapshot.date.timeIntervalSince1970.dd.toInt64Milliseconds
            )
            return .incrementalSnapshotRecord(value: record)
        }
    }

    func viewportRecord(
        from snapshot: LayerTreeSnapshot,
        previousSnapshot: LayerTreeSnapshot
    ) -> SRRecord? {
        guard previousSnapshot.viewportSize.dd.aspectRatio != snapshot.viewportSize.dd.aspectRatio else {
            return nil
        }

        let record = SRIncrementalSnapshotRecord(
            data: .viewportResizeData(
                value: .init(
                    height: Int64.ddWithNoOverflow(snapshot.viewportSize.height),
                    width: Int64.ddWithNoOverflow(snapshot.viewportSize.width)
                )
            ),
            timestamp: snapshot.date.timeIntervalSince1970.dd.toInt64Milliseconds
        )

        return .incrementalSnapshotRecord(value: record)
    }
}
#endif
