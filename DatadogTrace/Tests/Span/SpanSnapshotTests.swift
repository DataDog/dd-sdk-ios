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
        let capture = SpanSnapshotCapture()
        let tracer: DatadogTracer = .mockWith(core: core, onSpanFinished: capture.capture)

        let span = tracer.startSpan(
            operationName: "network.request",
            tags: [
                SpanTags.resource: "GET /api/users",
                SpanTags.service: "my-service"
            ]
        ) as! DDSpan

        span.finish()

        let snapshot = try XCTUnwrap(capture.snapshot)
        XCTAssertEqual(snapshot.operationName, "network.request")
        XCTAssertEqual(snapshot.resource, "GET /api/users")
        XCTAssertEqual(snapshot.service, "my-service")
    }

    func testSnapshotCapturesSpanKind() throws {
        let core = PassthroughCoreMock()
        let capture = SpanSnapshotCapture()
        let tracer: DatadogTracer = .mockWith(core: core, onSpanFinished: capture.capture)

        let span = tracer.startSpan(
            operationName: "rpc.call",
            tags: [SpanTags.kind: "client"]
        ) as! DDSpan

        span.finish()

        let snapshot = try XCTUnwrap(capture.snapshot)
        XCTAssertEqual(snapshot.spanKind, "client")
    }

    func testSnapshotCapturesHTTPStatusCode() throws {
        let core = PassthroughCoreMock()
        let capture = SpanSnapshotCapture()
        let tracer: DatadogTracer = .mockWith(core: core, onSpanFinished: capture.capture)

        let span = tracer.startSpan(
            operationName: "http.request",
            tags: [OTTags.httpStatusCode: 404]
        ) as! DDSpan

        span.finish()

        let snapshot = try XCTUnwrap(capture.snapshot)
        XCTAssertEqual(snapshot.httpStatusCode, 404)
    }

    func testSnapshotCapturesErrorFromTag() throws {
        let core = PassthroughCoreMock()
        let capture = SpanSnapshotCapture()
        let tracer: DatadogTracer = .mockWith(core: core, onSpanFinished: capture.capture)

        let span = tracer.startSpan(
            operationName: "failing.op",
            tags: [OTTags.error: true]
        ) as! DDSpan

        span.finish()

        let snapshot = try XCTUnwrap(capture.snapshot)
        XCTAssertTrue(snapshot.isError)
    }

    func testSnapshotCapturesErrorFromLogFields() throws {
        let core = PassthroughCoreMock()
        let capture = SpanSnapshotCapture()
        let tracer: DatadogTracer = .mockWith(core: core, onSpanFinished: capture.capture)

        let span = tracer.startSpan(operationName: "error.op") as! DDSpan
        span.log(
            fields: [
                OTLogFields.event: "error",
                OTLogFields.errorKind: "NetworkError"
            ]
        )

        span.finish()

        let snapshot = try XCTUnwrap(capture.snapshot)
        XCTAssertTrue(snapshot.isError)
    }

    func testSnapshotDefaultsToNoError() throws {
        let core = PassthroughCoreMock()
        let capture = SpanSnapshotCapture()
        let tracer: DatadogTracer = .mockWith(core: core, onSpanFinished: capture.capture)

        let span = tracer.startSpan(operationName: "ok.op") as! DDSpan

        span.finish()

        let snapshot = try XCTUnwrap(capture.snapshot)
        XCTAssertFalse(snapshot.isError)
    }

    // MARK: - Top-Level and Measured

    func testSnapshotIsTopLevel_whenRootSpan() throws {
        let core = PassthroughCoreMock()
        let capture = SpanSnapshotCapture()
        let tracer: DatadogTracer = .mockWith(core: core, onSpanFinished: capture.capture)

        let span = tracer.startSpan(operationName: "root.span") as! DDSpan

        span.finish()

        let snapshot = try XCTUnwrap(capture.snapshot)
        XCTAssertTrue(snapshot.isTopLevel)
        XCTAssertNil(snapshot.parentSpanID)
    }

    func testSnapshotIsNotTopLevel_whenChildSpan() throws {
        let core = PassthroughCoreMock()
        let capture = SpanSnapshotCapture()
        let tracer: DatadogTracer = .mockWith(core: core, onSpanFinished: capture.capture)

        let parent = tracer.startSpan(operationName: "parent")
        let child = tracer.startSpan(
            operationName: "child",
            references: [OTReference.child(of: parent.context)]
        )

        child.finish()
        parent.finish()

        XCTAssertEqual(capture.snapshots.count, 2)
        let childSnapshot = try XCTUnwrap(capture.snapshots.first { $0.operationName == "child" })
        XCTAssertFalse(childSnapshot.isTopLevel)
        XCTAssertNotNil(childSnapshot.parentSpanID)
    }

    func testSnapshotIsMeasured_whenTagSet() throws {
        let core = PassthroughCoreMock()
        let capture = SpanSnapshotCapture()
        let tracer: DatadogTracer = .mockWith(core: core, onSpanFinished: capture.capture)

        let span = tracer.startSpan(
            operationName: "measured.op",
            tags: ["_dd.measured": 1]
        ) as! DDSpan

        span.finish()

        let snapshot = try XCTUnwrap(capture.snapshot)
        XCTAssertTrue(snapshot.isMeasured)
    }

    // MARK: - Peer Tags

    func testSnapshotCapturesPeerTags() throws {
        let core = PassthroughCoreMock()
        let capture = SpanSnapshotCapture()
        let tracer: DatadogTracer = .mockWith(core: core, onSpanFinished: capture.capture)

        let span = tracer.startSpan(
            operationName: "db.call",
            tags: [
                "peer.service": "postgres-primary",
                "db.instance": "users_db",
                "out.host": "db.internal.io",
                "unrelated.tag": "should-be-ignored"
            ]
        ) as! DDSpan

        span.finish()

        let snapshot = try XCTUnwrap(capture.snapshot)
        XCTAssertEqual(snapshot.peerTags["peer.service"], "postgres-primary")
        XCTAssertEqual(snapshot.peerTags["db.instance"], "users_db")
        XCTAssertEqual(snapshot.peerTags["out.host"], "db.internal.io")
        XCTAssertNil(snapshot.peerTags["unrelated.tag"])
    }

    // MARK: - Service Source

    func testSnapshotCapturesServiceSource() throws {
        let core = PassthroughCoreMock()
        let capture = SpanSnapshotCapture()
        let tracer: DatadogTracer = .mockWith(core: core, onSpanFinished: capture.capture)

        let span = tracer.startSpan(
            operationName: "op",
            tags: ["_dd.svc_src": "m"]
        ) as! DDSpan

        span.finish()

        let snapshot = try XCTUnwrap(capture.snapshot)
        XCTAssertEqual(snapshot.serviceSource, "m")
    }

    func testSnapshotDefaultsToEmptyServiceSource() throws {
        let core = PassthroughCoreMock()
        let capture = SpanSnapshotCapture()
        let tracer: DatadogTracer = .mockWith(core: core, onSpanFinished: capture.capture)

        let span = tracer.startSpan(operationName: "op") as! DDSpan

        span.finish()

        let snapshot = try XCTUnwrap(capture.snapshot)
        XCTAssertEqual(snapshot.serviceSource, "")
    }

    // MARK: - Duration and Timing

    func testSnapshotCapturesNonZeroDuration() throws {
        let startDate = Date(timeIntervalSince1970: 1_000)
        let finishDate = Date(timeIntervalSince1970: 1_000.5)

        let core = PassthroughCoreMock()
        let capture = SpanSnapshotCapture()
        let tracer: DatadogTracer = .mockWith(
            core: core,
            dateProvider: RelativeDateProvider(startingFrom: startDate, advancingBySeconds: 0),
            onSpanFinished: capture.capture
        )

        let span = tracer.startSpan(operationName: "timed.op", startTime: startDate) as! DDSpan

        span.finish(at: finishDate)

        let snapshot = try XCTUnwrap(capture.snapshot)
        XCTAssertEqual(snapshot.duration, 500_000_000)
        XCTAssertEqual(snapshot.startTime, 1_000_000_000_000)
    }

    // MARK: - Resource Fallback

    func testSnapshotUsesOperationNameAsResourceFallback() throws {
        let core = PassthroughCoreMock()
        let capture = SpanSnapshotCapture()
        let tracer: DatadogTracer = .mockWith(core: core, onSpanFinished: capture.capture)

        let span = tracer.startSpan(operationName: "fallback.op") as! DDSpan

        span.finish()

        let snapshot = try XCTUnwrap(capture.snapshot)
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
        let capture = SpanSnapshotCapture()
        let tracer: DatadogTracer = .mockWith(
            core: core,
            samplingProvider: TracerSamplerProviderMock.mockRejectAll(),
            onSpanFinished: capture.capture
        )

        let span = tracer.startSpan(operationName: "sampled.out")
        span.finish()

        XCTAssertNotNil(capture.snapshot, "Snapshot must be captured regardless of sampling decision")
    }

    // MARK: - Sanitization Consistency
    //
    // The uploaded `SpanEvent` is sanitized at encode time (attribute-key normalization and the
    // 256-attribute limit). The stats `SpanSnapshot` is derived from the same sanitized
    // representation, so client-side stats never emit a peer dimension the uploaded span dropped or
    // renamed, a divergence the backend cannot reconcile because `_dd.compute_stats=0` suppresses
    // its own recomputation.

    func testSnapshotPeerTagsMatchSanitizedUploadedSpan() throws {
        let core = PassthroughCoreMock()
        let tracer: DatadogTracer = .mockWith(
            core: core,
            samplingProvider: TracerSamplerProviderMock.mockKeepAll()
        )

        var capturedSnapshot: SpanSnapshot?
        tracer.onSpanFinished = { capturedSnapshot = $0 }

        // A span carrying more tags than the sanitizer's attribute limit, including peer tags: the
        // limit drops some tags, and the snapshot must reflect exactly what the upload keeps.
        var tags: [String: Encodable] = [
            "peer.service": "downstream-svc",
            "out.host": "db.example.com",
            SpanTags.kind: "client"
        ]
        for i in 0..<(AttributesSanitizer.Constraints.maxNumberOfAttributes + 16) {
            tags["extra.tag.\(i)"] = "v"
        }

        let span = tracer.startSpan(operationName: "network.request", tags: tags)
        span.finish()

        let snapshot = try XCTUnwrap(capturedSnapshot)
        let uploaded = try XCTUnwrap(core.events(ofType: SpanEventsEnvelope.self).first)
        let uploadedSpan = try XCTUnwrap(uploaded.spans.first)

        // Each peer key must be present in the snapshot exactly when the sanitized upload keeps it,
        // with an identical value, proving stats read the same sanitized tags the span uploads.
        XCTAssertTrue(uploadedSpan.isSanitized)
        for key in SpanSnapshot.peerTagKeys {
            XCTAssertEqual(
                snapshot.peerTags[key],
                uploadedSpan.tags[key],
                "Snapshot peer tag '\(key)' must match the sanitized uploaded span"
            )
        }
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
        let capture = SpanSnapshotCapture()
        let tracer: DatadogTracer = .mockWith(
            core: core,
            spanEventBuilder: .mockWith(eventsMapper: { event in
                var mapped = event
                mapped.resource = "REDACTED"
                return mapped
            }),
            onSpanFinished: capture.capture
        )

        let span = tracer.startSpan(
            operationName: "network.request",
            tags: [SpanTags.resource: "GET /users/12345/profile"]
        )
        span.finish()

        let snapshot = try XCTUnwrap(capture.snapshot)
        XCTAssertEqual(snapshot.resource, "REDACTED")
    }

    func testSnapshotReflectsMappedOperationName() throws {
        let core = PassthroughCoreMock()
        let capture = SpanSnapshotCapture()
        let tracer: DatadogTracer = .mockWith(
            core: core,
            spanEventBuilder: .mockWith(eventsMapper: { event in
                var mapped = event
                mapped.operationName = "http.request.normalized"
                return mapped
            }),
            onSpanFinished: capture.capture
        )

        let span = tracer.startSpan(operationName: "http.request")
        span.finish()

        let snapshot = try XCTUnwrap(capture.snapshot)
        XCTAssertEqual(snapshot.operationName, "http.request.normalized")
    }

    func testSnapshotReflectsMappedPeerTags() throws {
        let core = PassthroughCoreMock()
        let capture = SpanSnapshotCapture()
        let tracer: DatadogTracer = .mockWith(
            core: core,
            spanEventBuilder: .mockWith(eventsMapper: { event in
                var mapped = event
                mapped.tags["peer.service"] = "redacted-db"
                return mapped
            }),
            onSpanFinished: capture.capture
        )

        let span = tracer.startSpan(
            operationName: "db.query",
            tags: ["peer.service": "postgres-primary"]
        )
        span.finish()

        let snapshot = try XCTUnwrap(capture.snapshot)
        XCTAssertEqual(snapshot.peerTags["peer.service"], "redacted-db")
    }

    func testSnapshotReflectsMapperRemovingPeerTag() throws {
        let core = PassthroughCoreMock()
        let capture = SpanSnapshotCapture()
        let tracer: DatadogTracer = .mockWith(
            core: core,
            spanEventBuilder: .mockWith(eventsMapper: { event in
                var mapped = event
                mapped.tags.removeValue(forKey: "peer.service")
                return mapped
            }),
            onSpanFinished: capture.capture
        )

        let span = tracer.startSpan(
            operationName: "db.query",
            tags: ["peer.service": "postgres-primary"]
        )
        span.finish()

        let snapshot = try XCTUnwrap(capture.snapshot)
        XCTAssertNil(snapshot.peerTags["peer.service"])
    }

    func testSnapshotReflectsMappedHTTPStatusCode() throws {
        let core = PassthroughCoreMock()
        let capture = SpanSnapshotCapture()
        let tracer: DatadogTracer = .mockWith(
            core: core,
            spanEventBuilder: .mockWith(eventsMapper: { event in
                var mapped = event
                mapped.tags[OTTags.httpStatusCode] = "500"
                return mapped
            }),
            onSpanFinished: capture.capture
        )

        let span = tracer.startSpan(
            operationName: "http.request",
            tags: [OTTags.httpStatusCode: 200]
        )
        span.finish()

        let snapshot = try XCTUnwrap(capture.snapshot)
        XCTAssertEqual(snapshot.httpStatusCode, 500)
    }

    func testSnapshotStartTimeUsesDeviceLocalClock_notServerAdjusted() throws {
        // `SpanEvent.startTime` has `context.serverTimeOffset` added for trace uploads,
        // but `StatsConcentrator.flush(now:)` runs against the device-local clock.
        // If the snapshot inherited the server-adjusted time, stats on a device whose
        // clock is behind the server would be bucketed in the future relative to the
        // flush clock and delayed or dropped. Pin the snapshot to device-local time.
        let deviceStartDate = Date(timeIntervalSince1970: 1_000)
        let serverOffset: TimeInterval = 5

        let core = PassthroughCoreMock(context: .mockWith(serverTimeOffset: serverOffset))
        let capture = SpanSnapshotCapture()
        let tracer: DatadogTracer = .mockWith(
            core: core,
            dateProvider: RelativeDateProvider(startingFrom: deviceStartDate, advancingBySeconds: 0),
            onSpanFinished: capture.capture
        )

        let span = tracer.startSpan(operationName: "timed.op", startTime: deviceStartDate)
        span.finish(at: deviceStartDate.addingTimeInterval(0.5))

        let snapshot = try XCTUnwrap(capture.snapshot)
        XCTAssertEqual(snapshot.startTime, 1_000_000_000_000, "Snapshot must use device-local start time, not server-adjusted")

        // Sanity check: the uploaded SpanEvent applies the offset, confirming the
        // offset is in play in this test setup.
        let envelopes: [SpanEventsEnvelope] = core.events()
        let uploadedSpan = try XCTUnwrap(envelopes.first?.spans.first)
        XCTAssertEqual(uploadedSpan.startTime.timeIntervalSince1970, 1_005, "SpanEvent startTime should be server-adjusted")
    }

    func testSnapshotTypeIsAlwaysCustom_evenWhenMapperSetsSpanTypeTag() throws {
        // `SpanEventEncoder.encode` writes `"custom"` for the span's top-level `type`
        // regardless of any `span.type` tag. The snapshot must match so stats and
        // uploads agree on the type dimension.
        let core = PassthroughCoreMock()
        let capture = SpanSnapshotCapture()
        let tracer: DatadogTracer = .mockWith(
            core: core,
            spanEventBuilder: .mockWith(eventsMapper: { event in
                var mapped = event
                mapped.tags["span.type"] = "http"
                return mapped
            }),
            onSpanFinished: capture.capture
        )

        let span = tracer.startSpan(operationName: "http.request")
        span.finish()

        let snapshot = try XCTUnwrap(capture.snapshot)
        XCTAssertEqual(snapshot.type, "custom", "Snapshot type must match the encoder's hardcoded value")
    }

    func testSnapshotMatchesUploadedSpanEvent_whenMapperRewritesResource() throws {
        // The strongest guarantee: snapshot and uploaded trace agree on resource name post-mapper.
        let core = PassthroughCoreMock()
        let capture = SpanSnapshotCapture()
        let tracer: DatadogTracer = .mockWith(
            core: core,
            spanEventBuilder: .mockWith(eventsMapper: { event in
                var mapped = event
                mapped.resource = "GET /users/{id}/profile"
                return mapped
            }),
            onSpanFinished: capture.capture
        )

        let span = tracer.startSpan(
            operationName: "network.request",
            tags: [SpanTags.resource: "GET /users/12345/profile"]
        )
        span.finish()

        let snapshot = try XCTUnwrap(capture.snapshot)
        let envelopes: [SpanEventsEnvelope] = core.events()
        let uploadedSpan = try XCTUnwrap(envelopes.first?.spans.first)

        XCTAssertEqual(snapshot.resource, uploadedSpan.resource)
        XCTAssertEqual(snapshot.operationName, uploadedSpan.operationName)
        XCTAssertEqual(snapshot.service, uploadedSpan.serviceName)
        XCTAssertEqual(snapshot.isError, uploadedSpan.isError)
    }
}
