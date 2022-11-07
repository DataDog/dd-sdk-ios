/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// A type turning succeeding `ViewTreeSnapshots` into sequence of Mobile Session Replay records.
///
/// This is the actual brain of Session Replay. Based on the sequence of snapshots it receives, it computes the sequence
/// of records that will to be send to SR BE. It implements the logic of reducing snapshots into Full or Incremental
/// mutation records.
internal protocol Processing {
    /// Accepts next `ViewTreeSnapshot`
    /// - Parameter snapshot: the `ViewTreeSnapshot`
    func process(snapshot: ViewTreeSnapshot)
}

/// The brain of the Session Replay.
///
/// It receives `ViewTreeSnapshots` (VTS) from `Recorder` and turns them
/// into format understood by SR BE, so it can be replayed in the player.
///
/// VTSs processing is following:
/// - the VTS is broke apart into individual view snapshots, mapped into array of SR wireframes (see `WireframesBuilder`);
/// - the array of wireframes is attached to SR record (see `RecordsBuidler`);
/// - succeeding records are stored;
/// - once enough records are gathered, they are attached to SR segment (see `SegmentBuilder`);
/// - SR segment can be uploaded to SR BE.
///
/// **WIP**: TODO: RUMM-2272 Make  `Processor` configurable and testable
internal class Processor: Processing {
    /// The background queue for executing all logic.
    private let queue = DispatchQueue(label: "com.datadoghq.session-replay.processor", qos: .utility)
    /// Flattens VTS received from `Recorder` by transforming its tree-structure into flat array of nodes and removing invisible nodes.
    private let nodesFlattener = NodesFlattener()
    /// Builds SR wireframes to describe UI elements.
    private let wireframesBuilder = WireframesBuilder()
    /// Builds SR records to transport SR wireframes.
    private let recordsBuilder = RecordsBuilder()
    /// Writes records to `DatadogCore`.
    private let writer: Writing

    /// Last processed snapshot.
    private var lastSnapshot: ViewTreeSnapshot? = nil
    /// Wireframes from last "full snapshot" or "incremental snapshot" record.
    private var lastWireframes: [SRWireframe]? = nil

    init(writer: Writing) {
        self.writer = writer
    }

    // MARK: - Processing

    func process(snapshot: ViewTreeSnapshot) {
        queue.async { self.processSync(snapshot: snapshot) }
    }

    private func processSync(snapshot: ViewTreeSnapshot) {
        let flattenedNodes = nodesFlattener.flattenNodes(in: snapshot)
        let wireframes: [SRWireframe] = flattenedNodes
            .compactMap { node in node.semantics.wireframesBuilder }
            .flatMap { nodeBuilder in nodeBuilder.buildWireframes(with: wireframesBuilder) }

        var records: [SRRecord] = []

        if snapshot.rumContext != lastSnapshot?.rumContext {
            // If RUM context has changed, new segment should be started.
            // Segment must always start with "meta" → "focus" → "full snapshot" records.
            records.append(recordsBuilder.createMetaRecord(from: snapshot))
            records.append(recordsBuilder.createFocusRecord(from: snapshot))
            records.append(recordsBuilder.createFullSnapshotRecord(from: snapshot, wireframes: wireframes))
        } else {
            // No change to RUM context means we're recording new records within the same RUM view.
            // Such can be added to current segment.
            // Prefer creating "incremental snapshot" records but fallback to "full snapshot" (unexpected):
            if let lastWireframes = lastWireframes {
                let record = recordsBuilder.createIncrementalSnapshotRecord(from: snapshot, with: wireframes, lastWireframes: lastWireframes)
                record.flatMap { records.append($0) }
            } else {
                // unexpected, TODO: RUMM-2410 Use `DD.logger` and / or `DD.telemetry`
                records.append(recordsBuilder.createFullSnapshotRecord(from: snapshot, wireframes: wireframes))
            }
        }

        if !records.isEmpty {
            // Transform `[SRRecord]` to `EnrichedRecord` so we can write it to `DatadogCore` and
            // later read it back (as `EnrichedRecordJSON`) for preparing upload request(s):
            let enrichedRecord = EnrichedRecord(rumContext: snapshot.rumContext, records: records)
            writer.write(nextRecord: enrichedRecord)
        }

        // Track state:
        lastSnapshot = snapshot
        lastWireframes = wireframes
    }
}
