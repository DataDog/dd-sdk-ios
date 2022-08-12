/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

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
internal class Processor: ViewTreeSnapshotProcessor {
    /// The background queue for executing all logic.
    private let queue = DispatchQueue(label: "com.datadoghq.session-replay.processor", qos: .utility)
    /// Builds SR wireframes to describe UI elements.
    private let wireframesBuilder = WireframesBuilder()
    /// Builds SR records to transport SR wireframes.
    private let recordsBuilder = RecordsBuilder()
    /// Builds SR segments to transport SR records.
    private let segmentsBuilder = SegmentBuilder()

    func process(snapshot: ViewTreeSnapshot) {
        queue.async { self.processSync(snapshot: snapshot) }
    }

    private func processSync(snapshot: ViewTreeSnapshot) {
        // 🚧 WIP: following code does cut a lot of corners. This is to export JSON
        // that can be previewed in the replay.
        if self.records.isEmpty {
            records.append(
                recordsBuilder.createMetaRecord(from: snapshot)
            )
            records.append(
                recordsBuilder.createFocusRecord(from: snapshot)
            )
        }

        let wireframes = flatten(viewTreeSnapshot: snapshot)
            .map { viewSnapshot in wireframesBuilder.createShapeWireframe(from: viewSnapshot) }

        records.append(
            recordsBuilder.createFullSnapshotRecord(from: snapshot, with: wireframes)
        )

        if records.count == 60 { // after decent number of records, export the JSON
            do {
                let segment = try segmentsBuilder.createSegment(with: records)
                printToConsole(segment: segment)
            } catch {
                print("Failed to process snapshot: \(error)") // TODO: RUMM-2410 Use `DD.logger` and / or `DD.telemetry`
            }
        }
    }

    // MARK: - 🚧 Work In Progress: things will change in RUMM-2429

    private var records: [SRMobileSegment.Records] = []

    private func flatten(viewTreeSnapshot: ViewTreeSnapshot) -> [Snapshot] {
        func accumulate(next viewSnapshot: Snapshot, in array: inout [Snapshot]) {
            array.append(viewSnapshot)
            viewSnapshot.children.forEach { childViewSnapshot in accumulate(next: childViewSnapshot, in: &array) }
        }

        var flattened: [Snapshot] = []
        accumulate(next: viewTreeSnapshot.root, in: &flattened)
        return flattened
    }

    private func printToConsole(segment: SRMobileSegment) {
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = .prettyPrinted

        guard let data = try? jsonEncoder.encode(segment) else {
            fatalError()
        }
        guard let string = String(data: data, encoding: .utf8) else {
            fatalError()
        }

        print("""
        ⚡️ >>>>>>>>> SR Segment >>>>>>>>>
        \(string)
        🔌 <<<<<<<<< SR Segment <<<<<<<<<
        """)
    }
}
