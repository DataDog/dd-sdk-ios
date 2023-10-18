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
        static let totalWireframeMutationRecords = 7
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
        // - pull SR dat aright after - we know it is delivered faster than RUM so we don't need to await any longer
        let rumSessionHasEndedCondition: ([Request]) throws -> Bool = { try RUMSessionMatcher.singleSession(from: $0)?.hasEnded() ?? false }
        let rawRUMRequests = try rumEndpoint.pullRecordedRequests(timeout: dataDeliveryTimeout, until: rumSessionHasEndedCondition)
        let rawSRRequests = try srEndpoint.getRecordedRequests()
        
        assertRUM(requests: rawRUMRequests)
        assertSR(requests: rawSRRequests)
        
        // Map raw requests into RUM Session and SR request matchers:
        let rumSession = try XCTUnwrap(RUMSessionMatcher.singleSession(from: rawRUMRequests))
        let srRequests = try SRRequestMatcher.from(requests: rawSRRequests)
        
        // Read SR segments from SR requests (one request = one segment):
        let segments = try srRequests.map { try SRSegmentMatcher.fromJSONData($0.segmentJSONData()) }
        
        XCTAssertFalse(rumSession.viewVisits.isEmpty, "There should be some RUM session")
        XCTAssertFalse(srRequests.isEmpty, "There should be some SR requests")
        XCTAssertFalse(segments.isEmpty, "There should be some SR segments")
        sendCIAppLog(rumSession)
        
        // Validate if RUM session links to SR replay through `has_replay` flag in RUM events.
        // - We can't (yet) reliably sync the begining of the replay with the begining of RUM session, hence some initial
        // RUM events will not have `has_replay: true`. For that reason, we only do broad assertion on "most" events.
        let rumEventsWithReplay = try rumSession.allEvents.filter { try $0.sessionHasReplay() == true }
        XCTAssertGreaterThan(Double(rumEventsWithReplay.count) / Double(rumSession.allEvents.count), 0.5, "Most RUM events must have `has_replay` flag set to `true`")
        
        // Validate SR (multipart) requests.
        for request in srRequests {
            // - Each request must reference RUM session:
            XCTAssertEqual(try request.applicationID(), rumSession.applicationID, "SR request must reference RUM application")
            XCTAssertEqual(try request.sessionID(), rumSession.sessionID, "SR request must reference RUM session")
            XCTAssertTrue(rumSession.containsView(with: try request.viewID()), "SR request must reference a known view ID from RUM session")
            
            // - Other, broad checks:
            XCTAssertGreaterThan(Int(try request.recordsCount()) ?? 0, 0, "SR request must include some records")
            XCTAssertGreaterThan(Int(try request.rawSegmentSize()) ?? 0, 0, "SR request must include non-empty segment information")
            XCTAssertEqual(try request.source(), "ios")
        }
        
        // Validate SR segments.
        for segment in segments {
            // - Each segment must reference RUM session:
            XCTAssertEqual(try segment.value("application.id"), rumSession.applicationID, "Segment must be linked to RUM application")
            XCTAssertEqual(try segment.value("session.id"), rumSession.sessionID, "Segment must be linked to RUM session")
            XCTAssertTrue(rumSession.containsView(with: try segment.value("view.id")), "Segment must be linked to RUM view")
            
            // - Other, broad checks:
            XCTAssertGreaterThan(try segment.value("records_count") as Int, 0, "Segment must include some records")
            XCTAssertEqual(try segment.value("records_count") as Int, try segment.array("records").count, "Records count must be consistent")
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
