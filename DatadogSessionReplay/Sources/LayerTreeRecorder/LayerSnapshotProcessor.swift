/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

// MARK: - Overview
//
// Builds and writes Session Replay records for the layer-tree recording strategy.
//
// For each captured frame, this processor:
// - Builds wireframes and resources from layer snapshots and rendered images
// - Produces segment records (meta/focus/full or incremental)
// - Appends touch interaction records when available
// - Writes enriched records and forwards resources for deduplicated persistence

#if os(iOS)
import Foundation
import DatadogInternal

@available(iOS 13.0, tvOS 13.0, *)
internal final class LayerSnapshotProcessor: Processor {
    /// Frame payload produced by `LayerRecorder`.
    struct Input {
        var layerTreeSnapshot: LayerTreeSnapshot
        var targetSnapshots: [LayerSnapshot]
        var layerImages: [Int64: LayerImageRenderer.Result]
        var touchSnapshot: TouchSnapshot?
    }

    // Interception callback for snapshot tests
    var interceptWireframes: (([SRWireframe]) -> Void)?

    private let recordWriter: any RecordWriting
    private let contextPublisher: SRContextPublisher
    private let recordsBuilder: RecordsBuilder
    private let resourceProcessor: any Processor<ResourceProcessor.Input>
    private let telemetry: any Telemetry

    // State used to decide segment boundaries and to generate incremental snapshots.
    private var lastSnapshot: LayerTreeSnapshot?
    private var lastWireframes: [SRWireframe]?
    private var recordsByView: [String: Int64] = [:]

    init(
        recordWriter: any RecordWriting,
        contextPublisher: SRContextPublisher,
        resourceProcessor: any Processor<ResourceProcessor.Input>,
        telemetry: any Telemetry
    ) {
        self.recordWriter = recordWriter
        self.contextPublisher = contextPublisher
        self.resourceProcessor = resourceProcessor
        self.telemetry = telemetry
        self.recordsBuilder = RecordsBuilder(telemetry: telemetry)
    }

    func process(_ input: Input) async {
        let wireframeBuilder = LayerWireframeBuilder()
        let output = wireframeBuilder.createWireframes(
            for: input.targetSnapshots,
            layerImages: input.layerImages,
            webViewSlotIDs: input.layerTreeSnapshot.webViewSlotIDs
        )
        let wireframes = output.wireframes

        interceptWireframes?(wireframes)

        var records: [SRRecord] = []

        // Create records describing the UI

        let layerTreeSnapshot = input.layerTreeSnapshot

        // A segment boundary is defined by application/session/view identity changes.
        if
            layerTreeSnapshot.context.applicationID != lastSnapshot?.context.applicationID ||
            layerTreeSnapshot.context.sessionID != lastSnapshot?.context.sessionID ||
            layerTreeSnapshot.context.viewID != lastSnapshot?.context.viewID {
            // Start a new segment when context changes
            // Segment starts with 'meta', 'focus' and 'full snapshot' records
            records.append(
                recordsBuilder.createMetaRecord(
                    date: layerTreeSnapshot.date,
                    viewportSize: layerTreeSnapshot.viewportSize
                )
            )
            records.append(recordsBuilder.createFocusRecord(date: layerTreeSnapshot.date))
            records.append(
                recordsBuilder.createFullSnapshotRecord(
                    date: layerTreeSnapshot.date,
                    wireframes: wireframes
                )
            )
        } else if let lastWireframes {
            // No context changes
            // Prefer incremental snapshot but fall back to full snapshot
            if let record = recordsBuilder.createIncrementalSnapshotRecord(
                date: layerTreeSnapshot.date,
                with: wireframes,
                lastWireframes: lastWireframes
            ) {
                records.append(record)
            }

            // Create viewport orientation change record
            if let lastSnapshot, let record = recordsBuilder.createViewport(
                date: layerTreeSnapshot.date,
                viewportSize: layerTreeSnapshot.viewportSize,
                lastViewportSize: lastSnapshot.viewportSize
            ) {
                records.append(record)
            }
        } else {
            telemetry.error("[SR] Unexpected flow in `Processor`: no previous wireframes and no previous RUM context")
            records.append(
                recordsBuilder.createFullSnapshotRecord(
                    date: layerTreeSnapshot.date,
                    wireframes: wireframes
                )
            )
        }

        // Create records for the touch interaction

        if let touchSnapshot = input.touchSnapshot {
            records.append(
                contentsOf: recordsBuilder.createIncrementalSnapshotRecords(
                    from: touchSnapshot
                )
            )
        }

        // Write records

        if !records.isEmpty {
            let enrichedRecord = EnrichedRecord(
                applicationID: layerTreeSnapshot.context.applicationID,
                sessionID: layerTreeSnapshot.context.sessionID,
                viewID: layerTreeSnapshot.context.viewID,
                records: records
            )
            trackRecord(key: enrichedRecord.viewID, value: Int64(records.count))
            recordWriter.write(nextRecord: enrichedRecord)
        }

        // Keep last state
        lastSnapshot = layerTreeSnapshot
        lastWireframes = wireframes

        // Process resources after writing records to keep record emission on the
        // critical path and resource writing offloaded.
        await resourceProcessor.process(
            .init(
                resources: output.resources,
                context: .init(layerTreeSnapshot.context.applicationID)
            )
        )
    }

    private func trackRecord(key: String, value: Int64) {
        recordsByView[key, default: 0] += value
        contextPublisher.setRecordsCountByViewID(recordsByView)
    }
}
#endif
