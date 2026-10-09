/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
import OpenTelemetryApi

@testable import DatadogTrace

class SpanSnapshotTests: XCTestCase {
    // MARK: - Service boundaries

    func testServiceChangingChildrenAreTopLevelRegardlessOfSamplingAndFinishOrder() throws {
        for sampled in [false, true] {
            for parentFinishesFirst in [false, true] {
                let core = PassthroughCoreMock()
                let capture = SpanSnapshotCapture()
                let tracer: DatadogTracer = .mockWith(
                    core: core,
                    samplingProvider: sampled ? TracerSamplerProviderMock.mockKeepAll() : TracerSamplerProviderMock.mockRejectAll(),
                    spanEventBuilder: .mockWith(statsComputationEnabled: true),
                    onSpanFinished: capture.capture
                )
                let parent = tracer.startSpan(operationName: "parent", tags: [SpanTags.service: "parent-service"])
                let child = tracer.startSpan(operationName: "child", childOf: parent.context)
                child.setTag(key: SpanTags.service, value: "child-service")
                if parentFinishesFirst { parent.finish() }
                child.finish()
                if !parentFinishesFirst { parent.finish() }

                let snapshot = try XCTUnwrap(capture.snapshots.first { $0.operationName == "child" })
                XCTAssertTrue(snapshot.isTopLevel)
                XCTAssertTrue(StatsConcentrator.isEligible(snapshot))
                XCTAssertNotNil(snapshot.parentSpanID)
                XCTAssertEqual(snapshot.service, "child-service")
                let events: [SpanEventsEnvelope] = core.events()
                XCTAssertEqual(events.count, sampled ? 2 : 0)
                XCTAssertTrue(events.flatMap(\.spans).allSatisfy { $0.tags[SpanTags.topLevel] == nil })
            }
        }
    }

    func testSameServiceChildrenRemainIneligibleAndUseParentsCurrentService() throws {
        let capture = SpanSnapshotCapture()
        let tracer: DatadogTracer = .mockWith(core: PassthroughCoreMock(), onSpanFinished: capture.capture)
        let parent = tracer.startSpan(operationName: "parent", tags: [SpanTags.service: "initial"])
        let child = tracer.startSpan(operationName: "child", childOf: parent.context, tags: [SpanTags.service: "updated"])
        parent.setTag(key: SpanTags.service, value: "updated")
        child.finish()
        let snapshot = try XCTUnwrap(capture.snapshot)
        XCTAssertFalse(snapshot.isTopLevel)
        XCTAssertFalse(StatsConcentrator.isEligible(snapshot))
        parent.setTag(key: SpanTags.service, value: "later")
        parent.finish()
        XCTAssertFalse(capture.snapshots[0].isTopLevel)
    }

    func testServiceOverridesAreFrozenBeforeDeferredEventMapping() throws {
        let scope = FeatureScopeMock(deferEventWriteContext: true)
        let capture = SpanSnapshotCapture()
        let tracer: DatadogTracer = .mockWith(featureScope: scope, onSpanFinished: capture.capture)
        let parent = tracer.startSpan(operationName: "parent", tags: [SpanTags.service: "same"])
        let child = tracer.startSpan(operationName: "child", childOf: parent.context, tags: [SpanTags.service: "same"])
        child.finish()
        parent.setTag(key: SpanTags.service, value: "changed-after-child-finish")
        scope.flushDeferredEventWriteContexts()
        XCTAssertFalse(try XCTUnwrap(capture.snapshot).isTopLevel)
    }

    func testChildRetainsServiceMetadataButNotItsParentSpan() throws {
        let capture = SpanSnapshotCapture()
        let tracer: DatadogTracer = .mockWith(core: PassthroughCoreMock(), onSpanFinished: capture.capture)
        var parent: OTSpan? = tracer.startSpan(operationName: "parent", tags: [SpanTags.service: "parent"])
        weak var parentReference = parent?.dd
        let child = tracer.startSpan(operationName: "child", childOf: try XCTUnwrap(parent).context, tags: [SpanTags.service: "child"])
        parent?.finish()
        parent = nil
        XCTAssertNil(parentReference)
        child.finish()
        XCTAssertTrue(try XCTUnwrap(capture.snapshot).isTopLevel)
    }

    func testExtractedRemoteParentCreatesLocalServiceEntryWithoutChangingTraceRoot() throws {
        let capture = SpanSnapshotCapture()
        let tracer: DatadogTracer = .mockWith(core: PassthroughCoreMock(), onSpanFinished: capture.capture)
        let reader = HTTPHeadersReader(httpHeaderFields: ["x-datadog-trace-id": "123", "x-datadog-parent-id": "456"])
        let remote = try XCTUnwrap(tracer.extract(reader: reader))
        XCTAssertTrue(remote.dd.isRemote)
        let child = tracer.startSpan(operationName: "local-entry", childOf: remote)
        let grandchild = tracer.startSpan(operationName: "local-child", childOf: child.context)
        grandchild.finish()
        child.finish()
        XCTAssertFalse(capture.snapshots[0].isTopLevel)
        XCTAssertTrue(capture.snapshots[1].isTopLevel)
        XCTAssertEqual(capture.snapshots[1].parentSpanID, remote.dd.spanID)
        XCTAssertFalse(child.context.dd.isRemote)
    }

    func testUnknownParentMetadataDoesNotImplyRemoteParent() throws {
        let capture = SpanSnapshotCapture()
        let tracer: DatadogTracer = .mockWith(core: PassthroughCoreMock(), onSpanFinished: capture.capture)
        let context: DDSpanContext = .mockAny()
        tracer.startSpan(operationName: "child", childOf: context).finish()
        XCTAssertFalse(try XCTUnwrap(capture.snapshot).isTopLevel)
    }

    func testEachSpanUsesItsOwnStartTimeDefaultService() throws {
        let scope = FeatureScopeMock(context: .mockWith(service: "parent-default"), deferEventWriteContext: true)
        let capture = SpanSnapshotCapture()
        let builder = SpanEventBuilder(
            service: nil,
            networkInfoEnabled: false,
            eventsMapper: nil,
            bundleWithRUM: false,
            statsComputationEnabled: true,
            telemetry: NOPTelemetry()
        )
        let tracer: DatadogTracer = .mockWith(featureScope: scope, spanEventBuilder: builder, onSpanFinished: capture.capture)
        let parent = tracer.startSpan(operationName: "parent")
        scope.contextMock = .mockWith(service: "child-default")
        let child = tracer.startSpan(operationName: "child", childOf: parent.context)
        child.finish()
        scope.contextMock = .mockWith(service: "upload-default")
        scope.flushDeferredEventWriteContexts()
        XCTAssertEqual(capture.snapshot?.service, "child-default")
        XCTAssertTrue(try XCTUnwrap(capture.snapshot).isTopLevel)
    }

    func testInvalidServiceOverrideFallsBackToConfiguredService() throws {
        let capture = SpanSnapshotCapture()
        let tracer: DatadogTracer = .mockWith(core: PassthroughCoreMock(), onSpanFinished: capture.capture)
        let parent = tracer.startSpan(operationName: "parent", tags: [SpanTags.service: "temporary"])
        let child = tracer.startSpan(operationName: "child", childOf: parent.context)
        parent.setTag(key: SpanTags.service, value: 42)
        child.finish()
        XCTAssertFalse(try XCTUnwrap(capture.snapshot).isTopLevel)
    }

    func testStatsDisabledDoesNotAllocateServiceMetadataOrChangeUploads() throws {
        let core = PassthroughCoreMock()
        let tracer: DatadogTracer = .mockWith(core: core)
        let parent = tracer.startSpan(operationName: "parent", tags: [SpanTags.service: "parent"])
        let child = tracer.startSpan(operationName: "child", childOf: parent.context, tags: [SpanTags.service: "child"])
        XCTAssertNil(parent.context.dd.serviceForStats)
        XCTAssertNil(child.context.dd.serviceForStats)
        child.finish()
        parent.finish()
        let events: [SpanEventsEnvelope] = core.events()
        XCTAssertEqual(events.flatMap(\.spans).map(\.serviceName), ["child", "parent"])
        XCTAssertTrue(events.flatMap(\.spans).allSatisfy { $0.tags[SpanTags.topLevel] == nil })
    }

    func testActiveOpenTracingParentProvidesServiceMetadata() throws {
        let capture = SpanSnapshotCapture()
        let tracer: DatadogTracer = .mockWith(core: PassthroughCoreMock(), onSpanFinished: capture.capture)
        let parent = tracer.startSpan(operationName: "parent", tags: [SpanTags.service: "parent"]).setActive()
        defer { parent.finish() }
        tracer.startSpan(operationName: "child", tags: [SpanTags.service: "child"]).finish()
        XCTAssertTrue(try XCTUnwrap(capture.snapshot).isTopLevel)
    }

    func testMapperServiceTagDoesNotOverrideServiceOrClassifyBoundary() throws {
        let capture = SpanSnapshotCapture()
        let tracer: DatadogTracer = .mockWith(
            core: PassthroughCoreMock(),
            spanEventBuilder: .mockWith(eventsMapper: { event in
                var mapped = event
                mapped.tags[SpanTags.service] = event.operationName
                return mapped
            }),
            onSpanFinished: capture.capture
        )
        let parent = tracer.startSpan(operationName: "parent")
        tracer.startSpan(operationName: "child", childOf: parent.context).finish()
        XCTAssertEqual(capture.snapshot?.service, tracer.spanEventBuilder.service)
        XCTAssertFalse(try XCTUnwrap(capture.snapshot).isTopLevel)
    }

    func testConcurrentServiceUpdatesAndChildFinishesPreserveAllSnapshots() throws {
        let capture = SpanSnapshotCapture()
        let tracer: DatadogTracer = .mockWith(
            core: PassthroughCoreMock(),
            samplingProvider: TracerSamplerProviderMock.mockRejectAll(),
            onSpanFinished: capture.capture
        )
        let parent = tracer.startSpan(operationName: "parent", tags: [SpanTags.service: "parent"])
        DispatchQueue.concurrentPerform(iterations: 200) { index in
            parent.setTag(key: SpanTags.service, value: "parent-\(index)")
            tracer.startSpan(operationName: "child", childOf: parent.context, tags: [SpanTags.service: "child"]).finish()
        }
        XCTAssertEqual(capture.snapshots.count, 200)
        XCTAssertTrue(capture.snapshots.allSatisfy(\.isTopLevel))
    }

    func testOpenTelemetryUsesUnfinishedParentsCurrentAttributes() throws {
        for parentFinishesFirst in [false, true] {
            let capture = SpanSnapshotCapture()
            let tracer: DatadogTracer = .mockWith(core: PassthroughCoreMock(), onSpanFinished: capture.capture)
            let parent = tracer.spanBuilder(spanName: "parent").setNoParent().startSpan()
            parent.setAttribute(key: SpanTags.service, value: .string("initial"))
            let child = tracer.spanBuilder(spanName: "child").setParent(parent).startSpan()
            parent.setAttributes([SpanTags.service: .string("updated")])
            child.setAttribute(key: SpanTags.service, value: .string("updated"))
            if parentFinishesFirst { parent.end() }
            child.end()
            if !parentFinishesFirst { parent.end() }
            let snapshot = try XCTUnwrap(capture.snapshots.first { $0.operationName == "child" })
            XCTAssertFalse(snapshot.isTopLevel)
        }
    }

    func testOpenTelemetryServiceChangingChildCountsWithoutParentFinishing() throws {
        let capture = SpanSnapshotCapture()
        let tracer: DatadogTracer = .mockWith(core: PassthroughCoreMock(), onSpanFinished: capture.capture)
        let parent = tracer.spanBuilder(spanName: "parent").setNoParent().setAttribute(key: SpanTags.service, value: .string("parent")).startSpan()
        let child = tracer.spanBuilder(spanName: "child").setParent(parent).startSpan()
        child.setAttribute(key: SpanTags.service, value: .string("child"))
        child.end()
        XCTAssertTrue(try XCTUnwrap(capture.snapshot).isTopLevel)
        XCTAssertTrue(parent.isRecording)
    }

    func testOpenTelemetryActiveParentProvidesServiceMetadata() throws {
        let capture = SpanSnapshotCapture()
        let tracer: DatadogTracer = .mockWith(core: PassthroughCoreMock(), onSpanFinished: capture.capture)
        let parent = tracer.spanBuilder(spanName: "parent")
            .setNoParent()
            .setAttribute(key: SpanTags.service, value: .string("parent"))
            .startSpan()
        OpenTelemetry.instance.contextProvider.withActiveSpan(parent) {
            tracer.spanBuilder(spanName: "child").setAttribute(key: SpanTags.service, value: .string("child")).startSpan().end()
        }
        XCTAssertTrue(try XCTUnwrap(capture.snapshot).isTopLevel)
        parent.end()
    }

    func testOpenTelemetrySampledOutServiceEntryStillContributesStats() throws {
        let core = PassthroughCoreMock()
        let capture = SpanSnapshotCapture()
        let tracer: DatadogTracer = .mockWith(core: core, samplingProvider: TracerSamplerProviderMock.mockRejectAll(), onSpanFinished: capture.capture)
        let parent = tracer.spanBuilder(spanName: "parent").setNoParent().setAttribute(key: SpanTags.service, value: .string("parent")).startSpan()
        tracer.spanBuilder(spanName: "child").setParent(parent).setAttribute(key: SpanTags.service, value: .string("child")).startSpan().end()
        let snapshot = try XCTUnwrap(capture.snapshot)
        XCTAssertTrue(snapshot.isTopLevel)
        XCTAssertTrue(StatsConcentrator.isEligible(snapshot))
        let events: [SpanEventsEnvelope] = core.events()
        XCTAssertTrue(events.isEmpty)
    }

    func testOpenTelemetryNestedServiceAttributesAreVisibleToChildren() throws {
        let capture = SpanSnapshotCapture()
        let tracer: DatadogTracer = .mockWith(core: PassthroughCoreMock(), onSpanFinished: capture.capture)
        let parent = tracer.spanBuilder(spanName: "parent").setNoParent().startSpan()
        parent.setAttribute(key: "service", value: .set(.init(labels: ["name": .string("shared")])))
        parent.setAttribute(key: "unrelated", value: .string("value"))
        tracer.spanBuilder(spanName: "same").setParent(parent).setAttribute(key: SpanTags.service, value: .string("shared")).startSpan().end()
        XCTAssertFalse(try XCTUnwrap(capture.snapshot).isTopLevel)
        parent.setAttributes(["service": .set(.init(labels: ["name": .string("updated")]))])
        tracer.spanBuilder(spanName: "different").setParent(parent).setAttribute(key: SpanTags.service, value: .string("shared")).startSpan().end()
        XCTAssertTrue(try XCTUnwrap(capture.snapshot).isTopLevel)
    }

    func testOpenTelemetryGlobalManualKeepRetainsItsExistingSideEffect() throws {
        for statsEnabled in [false, true] {
            let core = PassthroughCoreMock()
            let capture = SpanSnapshotCapture()
            let onSpanFinished: (@Sendable (SpanSnapshot) -> Void)?
            if statsEnabled {
                onSpanFinished = { capture.capture($0) }
            } else {
                onSpanFinished = nil
            }
            let tracer: DatadogTracer = .mockWith(
                core: core,
                samplingProvider: TracerSamplerProviderMock.mockRejectAll(),
                tags: [SpanTags.manualKeep: true, SpanTags.service: "global"],
                onSpanFinished: onSpanFinished
            )
            let span = tracer.spanBuilder(spanName: "span").setNoParent().startSpan()
            span.setAttribute(key: SpanTags.manualKeep, value: .bool(false))
            span.setAttribute(key: SpanTags.service, value: .string("local"))
            span.end()
            let events: [SpanEventsEnvelope] = core.events()
            XCTAssertEqual(events.count, 1)
            XCTAssertEqual(events.first?.spans.first?.serviceName, "local")
        }
    }

    func testOpenTelemetryRemovingServiceAttributeRestoresGlobalService() throws {
        let capture = SpanSnapshotCapture()
        let tracer: DatadogTracer = .mockWith(core: PassthroughCoreMock(), tags: [SpanTags.service: "global"], onSpanFinished: capture.capture)
        let parent = tracer.spanBuilder(spanName: "parent").setNoParent().setAttribute(key: SpanTags.service, value: .string("override")).startSpan()
        let child = tracer.spanBuilder(spanName: "child").setParent(parent).startSpan()
        parent.setAttribute(key: SpanTags.service, value: nil)
        child.end()
        XCTAssertFalse(try XCTUnwrap(capture.snapshot).isTopLevel)
    }

    func testOpenTelemetryRemoteParentIsNotInferredFromMissingMetadata() throws {
        let capture = SpanSnapshotCapture()
        let tracer: DatadogTracer = .mockWith(core: PassthroughCoreMock(), onSpanFinished: capture.capture)
        let local = SpanContext.create(traceId: .random(), spanId: .random(), traceFlags: .init(), traceState: .init())
        let remote = SpanContext.createFromRemoteParent(traceId: local.traceId, spanId: local.spanId, traceFlags: .init(), traceState: .init())
        tracer.spanBuilder(spanName: "local-context-only").setParent(local).startSpan().end()
        tracer.spanBuilder(spanName: "remote").setParent(remote).startSpan().end()
        XCTAssertFalse(capture.snapshots[0].isTopLevel)
        XCTAssertTrue(capture.snapshots[1].isTopLevel)
        XCTAssertNotNil(capture.snapshots[1].parentSpanID)
    }

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
        let capture = SpanSnapshotCapture()
        let tracer: DatadogTracer = .mockWith(
            core: core,
            samplingProvider: TracerSamplerProviderMock.mockKeepAll(),
            onSpanFinished: capture.capture
        )

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

        let snapshot = try XCTUnwrap(capture.snapshot)
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

    func testWhenVersionChangesBetweenSpans_eachSnapshotKeepsTheDeploymentItsUploadedSpanReports() throws {
        let core = PassthroughCoreMock(context: .mockWith(service: "ios-app", env: "staging", version: "1.0.0"))
        let capture = SpanSnapshotCapture()
        let tracer: DatadogTracer = .mockWith(core: core, onSpanFinished: capture.capture)

        tracer.startSpan(operationName: "first").finish()
        core.context.version = "2.0.0"
        tracer.startSpan(operationName: "second").finish()

        let deployments = capture.snapshots.map(\.deployment)
        XCTAssertEqual(deployments.map(\.version), ["1.0.0", "2.0.0"])
        XCTAssertEqual(deployments.map(\.env), ["staging", "staging"])
        XCTAssertEqual(deployments.map(\.service), ["ios-app", "ios-app"])

        let uploadedVersions = (core.events() as [SpanEventsEnvelope]).flatMap(\.spans).map(\.applicationVersion)
        XCTAssertEqual(uploadedVersions, deployments.map(\.version), "Stats and uploaded spans report the same version")
    }
}
