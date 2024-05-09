/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import HTTPServerMock
import TestUtilities
import XCTest

private extension ExampleApplication {
    func tapNextButton() {
        buttons["NEXT"].safeTap(within: 5)
    }

    func wait(seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }
}

class SRMultipleViewsRecordingScenarioTests: IntegrationTests, RUMCommonAsserts, SRCommonAsserts {
    /// Number of events expected by this test.
    ///
    /// These are **"minimum"** values, computed from a baseline run. Exact values may cause flakiness as number of SR records
    /// will highly depend on the performance of app, Simulator and CI.
    private struct Baseline {
        /// Number of all SR segments to pass the test.
        static let totalSegmentsCount = 15
        /// Number of all SR records to pass the test.
        static let totalRecordsCount = 35
        /// Number of all "full snapshot" records to pass the test.
        static let fullSnapshotRecordsCount = 6
        /// Number of all "incremental snapshot" records to pass the test.
        static let incrementalSnapshotRecordsCount = 17
        /// Number of all "meta" records to pass the test.
        static let metaRecordsCount = 6
        /// Number of all "focus" records to pass the test.
        static let focusRecordsCount = 6

        /// Total number of wireframes in all "full snapshot" records.
        static let totalWireframesInFullSnapshots = 150
        /// Minimal number of wireframes in each "full snapshot" record.
        static let minWireframesInFullSnapshot = 5

        /// Total number of "incremental snapshot" records that send "wireframe mutation" data.
        static let totalWireframeMutationRecords = 5
        /// Total number of "incremental snapshot" records that send "pointer interaction" data.
        static let totalTouchDataRecords = 10
    }

    func testSRMultipleViewsRecordingScenario() throws {
        // RUM endpoint in `HTTPServerMock`
        let rumEndpoint = server.obtainUniqueRecordingSession()
        // SR endpoint in `HTTPServerMock`
        let srEndpoint = server.obtainUniqueRecordingSession()
        
        // Play scenario:
        let app = ExampleApplication()
        app.launchWith(
            testScenarioClassName: "SRMultipleViewsRecordingScenario",
            serverConfiguration: HTTPServerMockConfiguration(
                rumEndpoint: rumEndpoint.recordingURL,
                srEndpoint: srEndpoint.recordingURL
            )
        )
        for _ in (0..<7) {
            app.wait(seconds: 1)
            app.tapNextButton()
        }
        try app.endRUMSession() // show "end view"
        
        // Get RUM and SR raw requests from mock server:
        // - pull RUM data until the "end view" event is fetched
        // - pull SR data until receiving expected count of segments
        let rawRUMRequests = try rumEndpoint.pullRecordedRequests(timeout: dataDeliveryTimeout, until: {
            try RUMSessionMatcher.singleSession(from: $0)?.hasEnded() ?? false
        })

        let rawSRRequests = try srEndpoint.pullRecordedRequests(timeout: dataDeliveryTimeout, until: {
            let segmentsCount = try SRSegmentMatcher.segmentsCount(from: $0)
            sendCIAppLog("Pulled \(segmentsCount) segments")
            return segmentsCount >= Baseline.totalSegmentsCount
        })

        assertRUM(requests: rawRUMRequests)
        assertSR(requests: rawSRRequests)
        
        // Map raw requests into RUM Session and SR request matchers:
        let rumSession = try XCTUnwrap(RUMSessionMatcher.singleSession(from: rawRUMRequests))
        let srRequests = try SRRequestMatcher.from(requests: rawSRRequests)

        XCTAssertFalse(rumSession.views.isEmpty, "There should be some RUM session")
        XCTAssertFalse(srRequests.isEmpty, "There should be some SR requests")
        sendCIAppLog(rumSession)
        
        // Validate if RUM session links to SR replay through `has_replay` flag in RUM events.
        // - We can't (yet) reliably sync the begining of the replay with the begining of RUM session, hence some initial
        // RUM events will not have `has_replay: true`. For that reason, we only do broad assertion on "most" events.
        let rumEventsWithReplay = try rumSession.allEvents.filter { try $0.sessionHasReplay() == true }
        XCTAssertGreaterThan(Double(rumEventsWithReplay.count) / Double(rumSession.allEvents.count), 0.5, "Most RUM events must have `has_replay` flag set to `true`")

        // Read and validate SR segments from SR requests.
        let segments: [SRSegmentMatcher] = try srRequests.reduce([]) { segments, request in

            // Read the metadata from request blob file
            let blob = try request.blob { data in
                // Resource request will have non-array blob file
                let array = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]]
                let matcher = JSONArrrayMatcher(array: array ?? [])
                return try matcher.values().map(SRSegmentMatcher.init(object:))
            }

            return try segments + blob.enumerated().map { index, metadata in
                // - Each request must reference RUM session:
                XCTAssertEqual(try metadata.applicationID(), rumSession.applicationID, "SR request must reference RUM application")
                XCTAssertEqual(try metadata.sessionID(), rumSession.sessionID, "SR request must reference RUM session")
                XCTAssertTrue(rumSession.containsView(with: try metadata.viewID()), "SR request must reference a known view ID from RUM session")

                let segment = try request.segment(at: index)

                // - Each segment must reference RUM session:
                try XCTAssertTrue(rumSession.containsView(with: segment.viewID()), "Segment must be linked to RUM view")
                try XCTAssertEqual(segment.applicationID(), metadata.applicationID(), "Segment must be linked to RUM application")
                try XCTAssertEqual(segment.sessionID(), metadata.sessionID(), "Segment must be linked to RUM session")
                try XCTAssertEqual(segment.viewID(), metadata.viewID(), "Segment must be linked to RUM view")
                try XCTAssertEqual(segment.hasFullSnapshot(), metadata.hasFullSnapshot())
                try XCTAssertEqual(segment.recordsCount(), metadata.recordsCount())
                try XCTAssertEqual(segment.start(), metadata.start())
                try XCTAssertEqual(segment.end(), metadata.end())
                try XCTAssertEqual(segment.source(), metadata.source())

                // - Other, broad checks:
                XCTAssertThrowsError(try metadata.records())
                try XCTAssertGreaterThan(metadata.rawSegmentSize(), metadata.compressedSegmentSize())
                try XCTAssertGreaterThan(segment.recordsCount(), 0, "Segment must include some records")
                try XCTAssertEqual(segment.recordsCount(), segment.records().count, "Records count must be consistent")
                return segment
            }
        }
        
        // Validate SR records.
        // - Broad checks on number of records:
        let allRecords = try segments.flatMap { try $0.records() }
        let fullSnapshotRecords = try segments.flatMap { try $0.records(type: .fullSnapshotRecord) }
        let incrementalSnapshotRecords = try segments.flatMap { try $0.records(type: .incrementalSnapshotRecord) }
        let metaRecords = try segments.flatMap { try $0.records(type: .metaRecord) }
        let focusRecords = try segments.flatMap { try $0.records(type: .focusRecord) }

        XCTAssertGreaterThan(allRecords.count, Baseline.totalRecordsCount, "The number of all records must be above baseline")
        XCTAssertGreaterThan(fullSnapshotRecords.count, Baseline.fullSnapshotRecordsCount, "The number of 'full snapshot' records must be above baseline")
        XCTAssertGreaterThan(incrementalSnapshotRecords.count, Baseline.incrementalSnapshotRecordsCount, "The number of 'incremental snapshot' records must be above baseline")
        XCTAssertGreaterThan(metaRecords.count, Baseline.metaRecordsCount, "The number of 'meta' records must be above baseline")
        XCTAssertGreaterThan(focusRecords.count, Baseline.focusRecordsCount, "The number of 'focus' records must be above baseline")

        // - Broad checks on contents of "full snapshot" records:
        let fullSnapshots = try segments.flatMap { try $0.fullSnapshotRecords() }
        let wireframesInFullSnapshots = try fullSnapshots.flatMap { try $0.wireframes() }
        let minWireframesInFullSnapshot = try fullSnapshots.map({ try $0.wireframes().count }).min() ?? 0
        XCTAssertGreaterThan(
            wireframesInFullSnapshots.count,
            Baseline.totalWireframesInFullSnapshots,
            "The total number of wireframes in all 'full snapshot' records must be above baseline"
        )
        XCTAssertGreaterThan(
            minWireframesInFullSnapshot,
            Baseline.minWireframesInFullSnapshot,
            "The minimal number of wireframes in each 'full snapshot' records must be above baseline"
        )

        // - Broad checks on contents of "incremental snapshot" records:
        let incrementalSnapshots = try segments.flatMap { try $0.incrementalSnapshotRecords() }
        let incrementalWithMutationData = try incrementalSnapshots.filter { try $0.has(incrementalDataType: .mutationData) }
        let incrementalWithTouchData = try incrementalSnapshots.filter { try $0.has(incrementalDataType: .pointerInteractionData) }
        XCTAssertGreaterThan(
            incrementalWithMutationData.count,
            Baseline.totalWireframeMutationRecords,
            "The number of 'incremental snapshot' records that send 'wireframe mutation' data must be above baseline"
        )
        XCTAssertGreaterThan(
            incrementalWithTouchData.count,
            Baseline.totalTouchDataRecords,
            "The number of 'incremental snapshot' records that send 'touch data' data must be above baseline"
        )
    }
}
