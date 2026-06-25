/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import DatadogInternal
import Foundation

/// Turns layer tree, image, and touch snapshots into Session Replay records.
@available(iOS 13.0, tvOS 13.0, *)
internal protocol LayerSnapshotProcessing {
    func process(
        layerTreeSnapshot: LayerTreeSnapshot,
        imageSnapshotResults: [Int64: ImageSnapshotResult],
        touchSnapshot: TouchSnapshot?
    )
}

/// Builds and writes Session Replay records for the Core Animation recording pipeline.
@available(iOS 13.0, tvOS 13.0, *)
internal final class LayerSnapshotProcessor: LayerSnapshotProcessing {
    private let queue: Queue
    private let recordWriter: RecordWriting
    private let resourceProcessor: ResourceProcessing
    private let replayContextPublisher: SRContextPublisher
    private let telemetry: Telemetry
    private let recordBuilder = LayerRecordBuilder()

    private var lastSnapshot: LayerTreeSnapshot?
    private var lastCompositionTree: SRCompositionTree?
    private var lastWireframes: [SRWireframe]?
    private var recordsCountByViewID: [String: Int64] = [:]

    init(
        queue: Queue,
        recordWriter: RecordWriting,
        resourceProcessor: ResourceProcessing,
        replayContextPublisher: SRContextPublisher,
        telemetry: Telemetry
    ) {
        self.queue = queue
        self.recordWriter = recordWriter
        self.resourceProcessor = resourceProcessor
        self.replayContextPublisher = replayContextPublisher
        self.telemetry = telemetry
    }

    func process(
        layerTreeSnapshot: LayerTreeSnapshot,
        imageSnapshotResults: [Int64: ImageSnapshotResult],
        touchSnapshot: TouchSnapshot?
    ) {
        queue.run { [weak self] in
            self?.processSync(
                layerTreeSnapshot: layerTreeSnapshot,
                imageSnapshotResults: imageSnapshotResults,
                touchSnapshot: touchSnapshot
            )
        }
    }

    private func processSync(
        layerTreeSnapshot: LayerTreeSnapshot,
        imageSnapshotResults: [Int64: ImageSnapshotResult],
        touchSnapshot: TouchSnapshot?
    ) {
        let output = CompositionTreeBuilder(
            root: layerTreeSnapshot.root,
            webViewSlotIDs: layerTreeSnapshot.webViewSlotIDs,
            imageSnapshotResults: imageSnapshotResults
        ).build()

        var records = records(
            from: layerTreeSnapshot,
            compositionTree: output.compositionTree,
            wireframes: output.wireframes
        )

        if let touchSnapshot {
            records.append(contentsOf: recordBuilder.touchRecords(from: touchSnapshot))
        }

        if !records.isEmpty {
            let enrichedRecord = EnrichedRecord(context: layerTreeSnapshot.context, records: records)
            trackRecord(key: enrichedRecord.viewID, value: Int64(records.count))
            recordWriter.write(nextRecord: enrichedRecord)
        }

        lastSnapshot = layerTreeSnapshot
        lastCompositionTree = output.compositionTree
        lastWireframes = output.wireframes

        resourceProcessor.process(
            resources: output.resources,
            context: .init(layerTreeSnapshot.context.applicationID)
        )
    }

    private func records(
        from snapshot: LayerTreeSnapshot,
        compositionTree: SRCompositionTree,
        wireframes: [SRWireframe]
    ) -> [SRRecord] {
        guard !snapshot.shouldStartNewSegment(after: lastSnapshot) else {
            return [
                recordBuilder.metaRecord(from: snapshot),
                recordBuilder.focusRecord(from: snapshot),
                recordBuilder.fullSnapshotRecord(
                    from: snapshot,
                    compositionTree: compositionTree,
                    wireframes: wireframes
                )
            ]
        }

        guard
            let lastSnapshot,
            let lastCompositionTree,
            let lastWireframes
        else {
            telemetry.error("[SR] Unexpected flow in `LayerSnapshotProcessor`: missing previous layer recording state")
            return [
                recordBuilder.fullSnapshotRecord(
                    from: snapshot,
                    compositionTree: compositionTree,
                    wireframes: wireframes
                )
            ]
        }

        do {
            var records: [SRRecord] = []

            if let record = try recordBuilder.wireframeMutationRecord(
                from: snapshot,
                wireframes: wireframes,
                previousWireframes: lastWireframes
            ) {
                records.append(record)
            }

            if let record = try recordBuilder.compositionTreeMutationRecord(
                from: snapshot,
                compositionTree: compositionTree,
                previousCompositionTree: lastCompositionTree
            ) {
                records.append(record)
            }

            if let record = recordBuilder.viewportRecord(
                from: snapshot,
                previousSnapshot: lastSnapshot
            ) {
                records.append(record)
            }

            return records
        } catch {
            telemetry.error("[SR] Failed to build layer recording mutation records", error: error)
            return [
                recordBuilder.fullSnapshotRecord(
                    from: snapshot,
                    compositionTree: compositionTree,
                    wireframes: wireframes
                )
            ]
        }
    }

    private func trackRecord(key: String, value: Int64) {
        recordsCountByViewID[key, default: 0] += value
        replayContextPublisher.setRecordsCountByViewID(recordsCountByViewID)
    }
}

@available(iOS 13.0, tvOS 13.0, *)
private extension LayerTreeSnapshot {
    func shouldStartNewSegment(after previousSnapshot: LayerTreeSnapshot?) -> Bool {
        return context.applicationID != previousSnapshot?.context.applicationID ||
            context.sessionID != previousSnapshot?.context.sessionID ||
            context.viewID != previousSnapshot?.context.viewID
    }
}

@available(iOS 13.0, tvOS 13.0, *)
private extension EnrichedRecord {
    init(context: LayerRecordingContext, records: [SRRecord]) {
        self.applicationID = context.applicationID
        self.sessionID = context.sessionID
        self.viewID = context.viewID
        self.records = records
    }
}
#endif
