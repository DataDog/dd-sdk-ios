/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A type turning succeeding view-tree and touch snapshots into sequence of Mobile Session Replay records.
///
/// This is the actual brain of Session Replay. Based on the sequence of snapshots it receives, it computes the sequence
/// of records that will to be send to SR BE. It implements the logic of reducing snapshots into Full or Incremental
/// mutation records.
internal protocol Processing {
    /// Accepts next view-tree and touch snapshots.
    /// - Parameter viewTreeSnapshot: the snapshot of a next view tree
    /// - Parameter touchSnapshot: the snapshot of next touch interactions (or `nil` if no interactions happened)
    func process(viewTreeSnapshot: ViewTreeSnapshot, touchSnapshot: TouchSnapshot?)
}

/// The brain of the Session Replay.
///
/// It receives `ViewTreeSnapshots` (VTS) from `Recorder` and turns them
/// into format understood by SR BE, so it can be replayed in the player.
///
/// VTSs processing is following:
/// - the VTS is broke apart into individual view snapshots, mapped into array of SR wireframes (see `WireframesBuilder`);
/// - the array of wireframes is attached to SR record (see `RecordsBuidler`);
/// - succeeding records are enriched with their RUM context and written to `DatadogCore`;
/// - when `DatadogCore` triggers an upload, batched records are deserialized, grouped into SR segments and then uploaded.
internal class Processor: Processing {
    /// Flattens VTS received from `Recorder` by removing invisible nodes.
    private let nodesFlattener = NodesFlattener()
    /// Builds SR wireframes to describe UI elements.
    private let wireframesBuilder = WireframesBuilder()
    /// Builds SR records to transport SR wireframes.
    private let recordsBuilder = RecordsBuilder()

    /// The background queue for executing all logic.
    private let queue: Queue
    /// Writes records to `DatadogCore`.
    private let writer: Writing

    /// Last processed snapshot.
    private var lastSnapshot: ViewTreeSnapshot? = nil
    /// Wireframes from last "full snapshot" or "incremental snapshot" record.
    private var lastWireframes: [SRWireframe]? = nil

    #if DEBUG
    /// Interception callback for snapshot tests.
    /// Only available in Debug configuration, solely made for testing purpose.
    var interceptWireframes: (([SRWireframe]) -> Void)? = nil
    #endif

    init(queue: Queue, writer: Writing) {
        self.queue = queue
        self.writer = writer
    }

    // MARK: - Processing

    func process(viewTreeSnapshot: ViewTreeSnapshot, touchSnapshot: TouchSnapshot?) {
        queue.run { self.processSync(viewTreeSnapshot: viewTreeSnapshot, touchSnapshot: touchSnapshot) }
    }

    private func processSync(viewTreeSnapshot: ViewTreeSnapshot, touchSnapshot: TouchSnapshot?) {
        let flattenedNodes = nodesFlattener.flattenNodes(in: viewTreeSnapshot)
        let wireframes: [SRWireframe] = flattenedNodes
            .map { node in node.wireframesBuilder }
            .flatMap { nodeBuilder in nodeBuilder.buildWireframes(with: wireframesBuilder) }

        #if DEBUG
        interceptWireframes?(wireframes)
        #endif

        var records: [SRRecord] = []
        // Create records for describing UI:
        if viewTreeSnapshot.rumContext != lastSnapshot?.rumContext {
            // If RUM context has changed, new segment should be started.
            // Segment must always start with "meta" → "focus" → "full snapshot" records.
            records.append(recordsBuilder.createMetaRecord(from: viewTreeSnapshot))
            records.append(recordsBuilder.createFocusRecord(from: viewTreeSnapshot))
            records.append(recordsBuilder.createFullSnapshotRecord(from: viewTreeSnapshot, wireframes: wireframes))
        } else if let lastWireframes = lastWireframes {
            // No change to RUM context means we're recording new records within the same RUM view.
            // Such can be added to current segment.
            // Prefer creating "incremental snapshot" records but fallback to "full snapshot" (unexpected):
            let record = recordsBuilder.createIncrementalSnapshotRecord(from: viewTreeSnapshot, with: wireframes, lastWireframes: lastWireframes)
            record.flatMap { records.append($0) }

            // Create viewport orientation change record
            if let lastSnapshot = lastSnapshot {
                recordsBuilder.createViewport(
                    from: viewTreeSnapshot,
                    lastSnapshot: lastSnapshot
                )
                .flatMap { records.append($0) }
            }
        } else {
            // unexpected, TODO: RUMM-2410 Use `DD.logger` and / or `DD.telemetry`
            records.append(recordsBuilder.createFullSnapshotRecord(from: viewTreeSnapshot, wireframes: wireframes))
        }

        // Create records for denoting touch interaction:
        if let touchSnapshot = touchSnapshot {
            records.append(
                contentsOf: recordsBuilder.createIncrementalSnapshotRecords(from: touchSnapshot)
            )
        }

        if !records.isEmpty {
            // Transform `[SRRecord]` to `EnrichedRecord` so we can write it to `DatadogCore` and
            // later read it back (as `EnrichedRecordJSON`) for preparing upload request(s):
            let enrichedRecord = EnrichedRecord(rumContext: viewTreeSnapshot.rumContext, records: records)
            writer.write(nextRecord: enrichedRecord)
        }

        // Track state:
        lastSnapshot = viewTreeSnapshot
        lastWireframes = wireframes
    }
}
