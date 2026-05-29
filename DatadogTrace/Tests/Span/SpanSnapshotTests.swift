/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogTrace

class SpanSnapshotTests: XCTestCase {
    // MARK: - Snapshot Creation

    func testSnapshotCapturesBasicSpanData() throws {
        let core = PassthroughCoreMock()
        let tracer: DatadogTracer = .mockWith(core: core)

        let span = tracer.startSpan(
            operationName: "network.request",
            tags: [
                SpanTags.resource: "GET /api/users",
                SpanTags.service: "my-service"
            ]
        ) as! DDSpan

        var capturedSnapshot: SpanSnapshot?
        tracer.onSpanFinished = { snapshot in
            capturedSnapshot = snapshot
        }

        span.finish()

        let snapshot = try XCTUnwrap(capturedSnapshot)
        XCTAssertEqual(snapshot.operationName, "network.request")
        XCTAssertEqual(snapshot.resource, "GET /api/users")
        XCTAssertEqual(snapshot.service, "my-service")
    }

    func testSnapshotCapturesSpanKind() throws {
        let core = PassthroughCoreMock()
        let tracer: DatadogTracer = .mockWith(core: core)

        let span = tracer.startSpan(
            operationName: "rpc.call",
            tags: [SpanTags.kind: "client"]
        ) as! DDSpan

        var capturedSnapshot: SpanSnapshot?
        tracer.onSpanFinished = { capturedSnapshot = $0 }

        span.finish()

        let snapshot = try XCTUnwrap(capturedSnapshot)
        XCTAssertEqual(snapshot.spanKind, "client")
    }

    func testSnapshotCapturesHTTPStatusCode() throws {
        let core = PassthroughCoreMock()
        let tracer: DatadogTracer = .mockWith(core: core)

        let span = tracer.startSpan(
            operationName: "http.request",
            tags: [OTTags.httpStatusCode: 404]
        ) as! DDSpan

        var capturedSnapshot: SpanSnapshot?
        tracer.onSpanFinished = { capturedSnapshot = $0 }

        span.finish()

        let snapshot = try XCTUnwrap(capturedSnapshot)
        XCTAssertEqual(snapshot.httpStatusCode, 404)
    }

    func testSnapshotCapturesErrorFromTag() throws {
        let core = PassthroughCoreMock()
        let tracer: DatadogTracer = .mockWith(core: core)

        let span = tracer.startSpan(
            operationName: "failing.op",
            tags: [OTTags.error: true]
        ) as! DDSpan

        var capturedSnapshot: SpanSnapshot?
        tracer.onSpanFinished = { capturedSnapshot = $0 }

        span.finish()

        let snapshot = try XCTUnwrap(capturedSnapshot)
        XCTAssertTrue(snapshot.isError)
    }

    func testSnapshotCapturesErrorFromLogFields() throws {
        let core = PassthroughCoreMock()
        let tracer: DatadogTracer = .mockWith(core: core)

        let span = tracer.startSpan(operationName: "error.op") as! DDSpan
        span.log(
            fields: [
                OTLogFields.event: "error",
                OTLogFields.errorKind: "NetworkError"
            ]
        )

        var capturedSnapshot: SpanSnapshot?
        tracer.onSpanFinished = { capturedSnapshot = $0 }

        span.finish()

        let snapshot = try XCTUnwrap(capturedSnapshot)
        XCTAssertTrue(snapshot.isError)
    }

    func testSnapshotDefaultsToNoError() throws {
        let core = PassthroughCoreMock()
        let tracer: DatadogTracer = .mockWith(core: core)

        let span = tracer.startSpan(operationName: "ok.op") as! DDSpan

        var capturedSnapshot: SpanSnapshot?
        tracer.onSpanFinished = { capturedSnapshot = $0 }

        span.finish()

        let snapshot = try XCTUnwrap(capturedSnapshot)
        XCTAssertFalse(snapshot.isError)
    }

    // MARK: - Top-Level and Measured

    func testSnapshotIsTopLevel_whenRootSpan() throws {
        let core = PassthroughCoreMock()
        let tracer: DatadogTracer = .mockWith(core: core)

        let span = tracer.startSpan(operationName: "root.span") as! DDSpan

        var capturedSnapshot: SpanSnapshot?
        tracer.onSpanFinished = { capturedSnapshot = $0 }

        span.finish()

        let snapshot = try XCTUnwrap(capturedSnapshot)
        XCTAssertTrue(snapshot.isTopLevel)
        XCTAssertNil(snapshot.parentSpanID)
    }

    func testSnapshotIsNotTopLevel_whenChildSpan() throws {
        let core = PassthroughCoreMock()
        let tracer: DatadogTracer = .mockWith(core: core)

        let parent = tracer.startSpan(operationName: "parent")
        let child = tracer.startSpan(
            operationName: "child",
            references: [OTReference.child(of: parent.context)]
        )

        var snapshots: [SpanSnapshot] = []
        tracer.onSpanFinished = { snapshots.append($0) }

        child.finish()
        parent.finish()

        XCTAssertEqual(snapshots.count, 2)
        let childSnapshot = try XCTUnwrap(snapshots.first { $0.operationName == "child" })
        XCTAssertFalse(childSnapshot.isTopLevel)
        XCTAssertNotNil(childSnapshot.parentSpanID)
    }

    func testSnapshotIsMeasured_whenTagSet() throws {
        let core = PassthroughCoreMock()
        let tracer: DatadogTracer = .mockWith(core: core)

        let span = tracer.startSpan(
            operationName: "measured.op",
            tags: ["_dd.measured": 1]
        ) as! DDSpan

        var capturedSnapshot: SpanSnapshot?
        tracer.onSpanFinished = { capturedSnapshot = $0 }

        span.finish()

        let snapshot = try XCTUnwrap(capturedSnapshot)
        XCTAssertTrue(snapshot.isMeasured)
    }

    // MARK: - Peer Tags

    func testSnapshotCapturesPeerTags() throws {
        let core = PassthroughCoreMock()
        let tracer: DatadogTracer = .mockWith(core: core)

        let span = tracer.startSpan(
            operationName: "db.call",
            tags: [
                "peer.service": "postgres-primary",
                "db.instance": "users_db",
                "out.host": "db.internal.io",
                "unrelated.tag": "should-be-ignored"
            ]
        ) as! DDSpan

        var capturedSnapshot: SpanSnapshot?
        tracer.onSpanFinished = { capturedSnapshot = $0 }

        span.finish()

        let snapshot = try XCTUnwrap(capturedSnapshot)
        XCTAssertEqual(snapshot.peerTags["peer.service"], "postgres-primary")
        XCTAssertEqual(snapshot.peerTags["db.instance"], "users_db")
        XCTAssertEqual(snapshot.peerTags["out.host"], "db.internal.io")
        XCTAssertNil(snapshot.peerTags["unrelated.tag"])
    }

    // MARK: - Service Source

    func testSnapshotCapturesServiceSource() throws {
        let core = PassthroughCoreMock()
        let tracer: DatadogTracer = .mockWith(core: core)

        let span = tracer.startSpan(
            operationName: "op",
            tags: ["_dd.svc_src": "m"]
        ) as! DDSpan

        var capturedSnapshot: SpanSnapshot?
        tracer.onSpanFinished = { capturedSnapshot = $0 }

        span.finish()

        let snapshot = try XCTUnwrap(capturedSnapshot)
        XCTAssertEqual(snapshot.serviceSource, "m")
    }

    func testSnapshotDefaultsToEmptyServiceSource() throws {
        let core = PassthroughCoreMock()
        let tracer: DatadogTracer = .mockWith(core: core)

        let span = tracer.startSpan(operationName: "op") as! DDSpan

        var capturedSnapshot: SpanSnapshot?
        tracer.onSpanFinished = { capturedSnapshot = $0 }

        span.finish()

        let snapshot = try XCTUnwrap(capturedSnapshot)
        XCTAssertEqual(snapshot.serviceSource, "")
    }

    // MARK: - Duration and Timing

    func testSnapshotCapturesNonZeroDuration() throws {
        let startDate = Date(timeIntervalSince1970: 1_000)
        let finishDate = Date(timeIntervalSince1970: 1_000.5)

        let core = PassthroughCoreMock()
        let tracer: DatadogTracer = .mockWith(
            core: core,
            dateProvider: RelativeDateProvider(startingFrom: startDate, advancingBySeconds: 0)
        )

        let span = tracer.startSpan(operationName: "timed.op", startTime: startDate) as! DDSpan

        var capturedSnapshot: SpanSnapshot?
        tracer.onSpanFinished = { capturedSnapshot = $0 }

        span.finish(at: finishDate)

        let snapshot = try XCTUnwrap(capturedSnapshot)
        XCTAssertEqual(snapshot.duration, 500_000_000)
        XCTAssertEqual(snapshot.startTime, 1_000_000_000_000)
    }

    // MARK: - Resource Fallback

    func testSnapshotUsesOperationNameAsResourceFallback() throws {
        let core = PassthroughCoreMock()
        let tracer: DatadogTracer = .mockWith(core: core)

        let span = tracer.startSpan(operationName: "fallback.op") as! DDSpan

        var capturedSnapshot: SpanSnapshot?
        tracer.onSpanFinished = { capturedSnapshot = $0 }

        span.finish()

        let snapshot = try XCTUnwrap(capturedSnapshot)
        XCTAssertEqual(snapshot.resource, "fallback.op")
    }

    // MARK: - Callback Wiring

    func testCallbackIsNotInvoked_whenNotSet() {
        let core = PassthroughCoreMock()
        let tracer: DatadogTracer = .mockWith(core: core)

        XCTAssertNil(tracer.onSpanFinished)

        let span = tracer.startSpan(operationName: "no-callback")
        span.finish()
    }

    func testSnapshotIsCapturedEvenForSampledOutSpans() throws {
        let core = PassthroughCoreMock()
        let tracer: DatadogTracer = .mockWith(
            core: core,
            samplingProvider: TracerSamplerProviderMock.mockRejectAll()
        )

        var capturedSnapshot: SpanSnapshot?
        tracer.onSpanFinished = { capturedSnapshot = $0 }

        let span = tracer.startSpan(operationName: "sampled.out")
        span.finish()

        XCTAssertNotNil(capturedSnapshot, "Snapshot must be captured regardless of sampling decision")
    }

    // MARK: - EventMapper Consistency
    //
    // The user-configured `SpanEventMapper` mutates `resource`, `operationName`, and `tags` on the
    // `SpanEvent` immediately before upload. Because the stats `SpanSnapshot` is derived from the
    // post-mapper event, stats and trace uploads agree on every keyed dimension. Without this,
    // a mapper that rewrites resource names (e.g. to redact PII) would key stats off the
    // pre-mapper values while traces carry post-mapper values, leading to dashboard inconsistency
    // and potential cardinality explosions in the stats pipeline.

    func testSnapshotReflectsMappedResourceName() throws {
        let core = PassthroughCoreMock()
        let tracer: DatadogTracer = .mockWith(
            core: core,
            spanEventBuilder: .mockWith(eventsMapper: { event in
                var mapped = event
                mapped.resource = "REDACTED"
                return mapped
            })
        )

        var capturedSnapshot: SpanSnapshot?
        tracer.onSpanFinished = { capturedSnapshot = $0 }

        let span = tracer.startSpan(
            operationName: "network.request",
            tags: [SpanTags.resource: "GET /users/12345/profile"]
        )
        span.finish()

        let snapshot = try XCTUnwrap(capturedSnapshot)
        XCTAssertEqual(snapshot.resource, "REDACTED")
    }

    func testSnapshotReflectsMappedOperationName() throws {
        let core = PassthroughCoreMock()
        let tracer: DatadogTracer = .mockWith(
            core: core,
            spanEventBuilder: .mockWith(eventsMapper: { event in
                var mapped = event
                mapped.operationName = "http.request.normalized"
                return mapped
            })
        )

        var capturedSnapshot: SpanSnapshot?
        tracer.onSpanFinished = { capturedSnapshot = $0 }

        let span = tracer.startSpan(operationName: "http.request")
        span.finish()

        let snapshot = try XCTUnwrap(capturedSnapshot)
        XCTAssertEqual(snapshot.operationName, "http.request.normalized")
    }

    func testSnapshotReflectsMappedPeerTags() throws {
        let core = PassthroughCoreMock()
        let tracer: DatadogTracer = .mockWith(
            core: core,
            spanEventBuilder: .mockWith(eventsMapper: { event in
                var mapped = event
                mapped.tags["peer.service"] = "redacted-db"
                return mapped
            })
        )

        var capturedSnapshot: SpanSnapshot?
        tracer.onSpanFinished = { capturedSnapshot = $0 }

        let span = tracer.startSpan(
            operationName: "db.query",
            tags: ["peer.service": "postgres-primary"]
        )
        span.finish()

        let snapshot = try XCTUnwrap(capturedSnapshot)
        XCTAssertEqual(snapshot.peerTags["peer.service"], "redacted-db")
    }

    func testSnapshotReflectsMapperRemovingPeerTag() throws {
        let core = PassthroughCoreMock()
        let tracer: DatadogTracer = .mockWith(
            core: core,
            spanEventBuilder: .mockWith(eventsMapper: { event in
                var mapped = event
                mapped.tags.removeValue(forKey: "peer.service")
                return mapped
            })
        )

        var capturedSnapshot: SpanSnapshot?
        tracer.onSpanFinished = { capturedSnapshot = $0 }

        let span = tracer.startSpan(
            operationName: "db.query",
            tags: ["peer.service": "postgres-primary"]
        )
        span.finish()

        let snapshot = try XCTUnwrap(capturedSnapshot)
        XCTAssertNil(snapshot.peerTags["peer.service"])
    }

    func testSnapshotReflectsMappedHTTPStatusCode() throws {
        let core = PassthroughCoreMock()
        let tracer: DatadogTracer = .mockWith(
            core: core,
            spanEventBuilder: .mockWith(eventsMapper: { event in
                var mapped = event
                mapped.tags[OTTags.httpStatusCode] = "500"
                return mapped
            })
        )

        var capturedSnapshot: SpanSnapshot?
        tracer.onSpanFinished = { capturedSnapshot = $0 }

        let span = tracer.startSpan(
            operationName: "http.request",
            tags: [OTTags.httpStatusCode: 200]
        )
        span.finish()

        let snapshot = try XCTUnwrap(capturedSnapshot)
        XCTAssertEqual(snapshot.httpStatusCode, 500)
    }

    func testSnapshotMatchesUploadedSpanEvent_whenMapperRewritesResource() throws {
        // The strongest guarantee: snapshot and uploaded trace agree on resource name post-mapper.
        let core = PassthroughCoreMock()
        let tracer: DatadogTracer = .mockWith(
            core: core,
            spanEventBuilder: .mockWith(eventsMapper: { event in
                var mapped = event
                mapped.resource = "GET /users/{id}/profile"
                return mapped
            })
        )

        var capturedSnapshot: SpanSnapshot?
        tracer.onSpanFinished = { capturedSnapshot = $0 }

        let span = tracer.startSpan(
            operationName: "network.request",
            tags: [SpanTags.resource: "GET /users/12345/profile"]
        )
        span.finish()

        let snapshot = try XCTUnwrap(capturedSnapshot)
        let envelopes: [SpanEventsEnvelope] = core.events()
        let uploadedSpan = try XCTUnwrap(envelopes.first?.spans.first)

        XCTAssertEqual(snapshot.resource, uploadedSpan.resource)
        XCTAssertEqual(snapshot.operationName, uploadedSpan.operationName)
        XCTAssertEqual(snapshot.service, uploadedSpan.serviceName)
        XCTAssertEqual(snapshot.isError, uploadedSpan.isError)
    }
}
