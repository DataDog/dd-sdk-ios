/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogInternal
@testable import DatadogTrace

class ClientStatsFeatureTests: XCTestCase {
    private var core: FeatureRegistrationCoreMock! // swiftlint:disable:this implicitly_unwrapped_optional
    private var config: Trace.Configuration! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUpWithError() throws {
        core = FeatureRegistrationCoreMock()
        config = Trace.Configuration()
    }

    override func tearDown() {
        core = nil
        config = nil
        XCTAssertEqual(FeatureRegistrationCoreMock.referenceCount, 0)
    }

    // MARK: - Registration

    func testWhenStatsComputationDisabled_thenClientStatsFeatureIsNotRegistered() {
        // Given
        config.featureFlags[.clientSideStats] = false

        // When
        Trace.enable(with: config, in: core)

        // Then
        XCTAssertNil(core.get(feature: ClientStatsFeature.self))
    }

    func testWhenStatsComputationEnabled_thenClientStatsFeatureIsRegistered() {
        // Given
        config.featureFlags[.clientSideStats] = true

        // When
        Trace.enable(with: config, in: core)

        // Then
        XCTAssertNotNil(core.get(feature: ClientStatsFeature.self))
    }

    func testWhenStatsComputationEnabled_thenTraceFeatureIsAlsoRegistered() {
        // Given
        config.featureFlags[.clientSideStats] = true

        // When
        Trace.enable(with: config, in: core)

        // Then
        XCTAssertNotNil(core.get(feature: TraceFeature.self))
        XCTAssertNotNil(core.get(feature: ClientStatsFeature.self))
    }

    func testWhenDefaultConfiguration_thenStatsComputationIsDisabled() {
        // Given
        let defaultConfig = Trace.Configuration()

        // Then
        XCTAssertFalse(defaultConfig.featureFlags[.clientSideStats])
    }

    // MARK: - Consent

    func testWhenContextMessageRevokesConsent_itStopsConcentratorFromExporting() {
        // Given: a concentrator with buffered data and the feature's consent receiver
        let concentrator = StatsConcentrator(now: 0, initialConsent: .granted)
        let receiver = TraceClientStatsContextReceiver(concentrator: concentrator)
        concentrator.add(SpanSnapshot.mockWith(startTime: 0, duration: 2_000_000_000, isTopLevel: true))

        // When: the bus delivers a context carrying revoked consent
        let handled = receiver.receive(
            message: .context(.mockWith(trackingConsent: .notGranted)),
            from: core
        )

        // Then: the message is processed and the buffered data is dropped
        XCTAssertTrue(handled)
        XCTAssertTrue(concentrator.flush(now: 100_000_000_000, force: true).isEmpty)
    }

    func testWhenMessageIsNotContext_theConsentReceiverIgnoresIt() {
        let concentrator = StatsConcentrator(now: 0, initialConsent: .granted)
        let receiver = TraceClientStatsContextReceiver(concentrator: concentrator)

        XCTAssertFalse(receiver.receive(message: .payload("irrelevant"), from: core))
    }

    // MARK: - Clearing Data

    func testWhenAllDataIsClearedWhileAFlushWaitsToWrite_itsBucketsAreNeverStored() throws {
        // Given: a flush that exported a bucket but whose write context has not run yet.
        let (core, stats) = try enableClientStats()
        core.defersWriteContexts = true
        stats.record(.mockWith(resource: "before", startTime: 0, duration: 100))
        stats.flushStats(.teardown)

        // When
        stats.clearAllData()
        core.runPendingWriteContexts()

        // Then: the bucket collected before the clear is not stored, and later stats still are.
        XCTAssertTrue(core.exportedBuckets.isEmpty)
        XCTAssertFalse(core.telemetryMock.messages.compactMap(\.asMetric).contains { $0.name == TraceClientStatsMetric.name })
        core.defersWriteContexts = false
        stats.record(.mockWith(resource: "after", startTime: 0, duration: 100))
        stats.flushStats(.teardown)
        XCTAssertEqual(core.exportedBuckets.flatMap(\.stats).map(\.resource), ["after"])
    }

    func testWhenAllDataIsCleared_bufferedStatsAreNeverStored() throws {
        let (core, stats) = try enableClientStats()
        stats.record(.mockWith(startTime: 0, duration: 100))

        stats.clearAllData()
        stats.flushStats(.teardown)

        XCTAssertTrue(core.exportedBuckets.isEmpty)
    }

    // MARK: - App Lifecycle

    func testWhenTheAppMovesIntoOrOutOfASuspendableState_theReceiverReportsEachTransitionOnce() {
        let receiver = TraceClientStatsContextReceiver(concentrator: nil)
        var transitions: [Bool] = []
        receiver.appMayBeSuspendedDidChange = { transitions.append($0) }
        let foreground: DatadogContext = .mockWith(applicationStateHistory: .mockAppInForeground())
        let background: DatadogContext = .mockWith(applicationStateHistory: suspendableAppStateHistory())

        for context in [foreground, background, background, foreground, background] {
            _ = receiver.receive(message: .context(context), from: core)
        }

        XCTAssertEqual(transitions, [true, false, true])
    }

    func testWhenTheAppGoesToTheBackground_theFeatureStoresBufferedStatsOffTheCallingThread() throws {
        // Given: buffered stats in the current window, which the periodic flush would keep for 20 s or more.
        let (core, stats) = try enableClientStats()
        stats.record(.mockWith(startTime: 0, duration: 100))
        _ = stats.messageReceiver.receive(message: .context(.mockWith(applicationStateHistory: .mockAppInForeground())), from: core)
        XCTAssertTrue(core.exportedBuckets.isEmpty)

        // When
        _ = stats.messageReceiver.receive(message: .context(.mockWith(applicationStateHistory: suspendableAppStateHistory())), from: core)

        // Then: the flush runs on the feature's queue, not on the message bus caller. Its metric is sent
        // after the write, so wait for both.
        waitUntil { core.telemetryMock.messages.firstMetric(named: TraceClientStatsMetric.name) != nil }
        XCTAssertEqual(core.exportedBuckets.flatMap(\.stats).map(\.hits), [1])
        XCTAssertEqual(core.writeContextOnMainThread, [false])
        let metric = try XCTUnwrap(core.telemetryMock.messages.firstMetric(named: TraceClientStatsMetric.name))
        XCTAssertEqual(metric.attributes[TraceClientStatsMetric.forcedKey] as? Bool, false, "Only teardown reports forced")
    }

    func testWhenSpansFinishWhileTheAppMayBeSuspended_theyAreStoredSoonInFewFlushes() throws {
        // Given: the SDK starts while the app is already in the background, with nothing buffered yet.
        let (core, stats) = try enableClientStats()
        _ = stats.messageReceiver.receive(message: .context(.mockWith(applicationStateHistory: suspendableAppStateHistory())), from: core)

        // When: a burst of spans finishes afterwards.
        for _ in 0..<10 {
            stats.record(.mockWith(startTime: 0, duration: 100))
        }

        // Then: every span is stored within the delay. The burst takes at most two flushes: the one the
        // transition started, if it runs after the first span, and the one the burst scheduled.
        let storedHits = { core.exportedBuckets.flatMap(\.stats).map(\.hits).reduce(0, +) }
        waitUntil(timeout: ClientStatsFeature.suspendableFlushDelay + 3) { storedHits() == 10 }
        XCTAssertEqual(storedHits(), 10)
        let flushMetrics = core.telemetryMock.messages.compactMap(\.asMetric).filter { $0.name == TraceClientStatsMetric.name }
        XCTAssertLessThanOrEqual(flushMetrics.count, 2)
    }

    func testWhenSpansFinishInTheForeground_theyWaitForThePeriodicFlush() throws {
        let (core, stats) = try enableClientStats()
        _ = stats.messageReceiver.receive(message: .context(.mockWith(applicationStateHistory: .mockAppInForeground())), from: core)

        stats.record(.mockWith(startTime: 0, duration: 100))

        RunLoop.current.run(until: Date().addingTimeInterval(ClientStatsFeature.suspendableFlushDelay + 0.5))
        XCTAssertTrue(core.exportedBuckets.isEmpty)
    }

    // MARK: - Request Builder

    func testWhenStatsComputationEnabled_thenRequestBuilderUsesStatsEndpoint() throws {
        // Given
        config.featureFlags[.clientSideStats] = true

        // When
        Trace.enable(with: config, in: core)

        // Then
        let stats = try XCTUnwrap(core.get(feature: ClientStatsFeature.self))
        XCTAssertTrue(stats.requestBuilder is StatsRequestBuilder)
    }

    func testWhenStatsComputationEnabledWithCustomStatsEndpoint_thenRequestBuilderUsesCustomURL() throws {
        // Given
        let customURL: URL = .mockRandom()
        config.featureFlags[.clientSideStats] = true
        config.customStatsEndpoint = customURL

        // When
        Trace.enable(with: config, in: core)

        // Then
        let stats = try XCTUnwrap(core.get(feature: ClientStatsFeature.self))
        let requestBuilder = try XCTUnwrap(stats.requestBuilder as? StatsRequestBuilder)
        XCTAssertEqual(requestBuilder.customIntakeURL, customURL)
    }

    func testWhenStatsComputationEnabledWithCustomEndpointOnly_thenStatsRequestBuilderDoesNotUseIt() throws {
        // Given: customEndpoint is for spans, not stats. Setting it must not affect the stats request builder.
        let spansURL: URL = .mockRandom()
        config.featureFlags[.clientSideStats] = true
        config.customEndpoint = spansURL

        // When
        Trace.enable(with: config, in: core)

        // Then
        let stats = try XCTUnwrap(core.get(feature: ClientStatsFeature.self))
        let requestBuilder = try XCTUnwrap(stats.requestBuilder as? StatsRequestBuilder)
        XCTAssertNil(requestBuilder.customIntakeURL)
    }

    // MARK: - Persisted deployment identity (RUM-17309)

    func testWhenBucketCarriesItsOwnIdentity_itIsReportedUnderThatIdentityNotTheUploadContext() throws {
        // Given: a bucket flushed under 1.2.3 that is uploaded after the app updated to 2.0.0.
        let uploadContext: DatadogContext = .mockWith(service: "new-service", env: "prod", version: "2.0.0")
        let bucket = makeExportedBucket(env: "staging", version: "1.2.3", service: "old-service")
        let builder = makeRequestBuilder()

        // When
        let request = try builder.request(
            for: [makeEvent(from: bucket)],
            with: uploadContext,
            execution: .init(previousResponseCode: nil, attempt: 0)
        )

        // Then
        let clientStats = try firstClientStatsPayload(in: request)
        XCTAssertEqual(clientStats["Env"] as? String, "staging")
        XCTAssertEqual(clientStats["Version"] as? String, "1.2.3")
        XCTAssertEqual(clientStats["Service"] as? String, "old-service")
    }

    func testWhenBatchMixesIdentities_eachStoredPayloadKeepsItsDeploymentAndSequence() throws {
        // Given: a batch spanning an app upgrade.
        let builder = makeRequestBuilder()
        let events = [
            makeEvent(from: makeExportedBucket(start: 1_000, env: "prod", version: "1.0.0", service: "app")),
            makeEvent(from: makeExportedBucket(start: 2_000, env: "prod", version: "2.0.0", service: "app")),
            makeEvent(from: makeExportedBucket(start: 3_000, env: "prod", version: "1.0.0", service: "app"))
        ]

        // When
        let request = try builder.request(
            for: events,
            with: .mockAny(),
            execution: .init(previousResponseCode: nil, attempt: 0)
        )

        // Then: each stored bucket is its own client payload, with its deployment and stored sequence.
        let payloads = try allClientStatsPayloads(in: request)
        XCTAssertEqual(payloads.map { $0["Version"] as? String }, ["1.0.0", "2.0.0", "1.0.0"])
        XCTAssertEqual(payloads.map { ($0["Stats"] as? [Any?])?.count }, [1, 1, 1])
        XCTAssertEqual(payloads.compactMap { $0["Sequence"] as? Int64 }, [1, 2, 3])
    }

    func testWhenABucketHasNoDeploymentIdentity_theWholeBatchIsDropped() throws {
        // Given: a bucket stored by an earlier internal build without env, version and service.
        let earlierBuild = Event(data: Data(#"{"start":1000,"duration":10000000000,"stats":[],"payload":{"runtimeID":"runtime-id","sequence":1}}"#.utf8))
        let current = makeEvent(from: makeExportedBucket())

        // Then: upgrades from those builds are not supported, so the batch cannot be built and is dropped.
        XCTAssertThrowsError(try makeRequestBuilder().request(for: [earlierBuild, current], with: .mockAny(), execution: .init(previousResponseCode: nil, attempt: 0)))
    }

    func testWhenVersionChangesBeforeFlush_itReportsTheDeploymentTheSpanWasRecordedUnder() throws {
        // Given: the span was recorded under 1.0.0, and the version changed to 2.0.0 before the flush,
        // as `Datadog._internal.set(customVersion:)` can do.
        let core = FeatureRegistrationPassthroughCoreMock(
            context: .mockWith(service: "ios-app", env: "staging", version: "2.0.0")
        )
        config.featureFlags[.clientSideStats] = true
        Trace.enable(with: config, in: core)
        let stats = try XCTUnwrap(core.get(feature: ClientStatsFeature.self))
        stats.concentrator.add(SpanSnapshot.mockWith(
            isTopLevel: true,
            deployment: .mockWith(env: "staging", version: "1.0.0", service: "ios-app")
        ))

        // When
        stats.flush()

        // Then
        let bucket = try XCTUnwrap(core.exportedBuckets.first)
        XCTAssertEqual(bucket.version, "1.0.0", "The flush-time version must not be reported")
        XCTAssertEqual(bucket.env, "staging")
        XCTAssertEqual(bucket.service, "ios-app")
    }

    // MARK: - Feature Name

    func testFeatureName() {
        XCTAssertEqual(ClientStatsFeature.name, "tracing-client-stats")
    }

    func testWhenStatsComputationEnabledWithCustomDateProvider_thenStatsFeatureUsesItForFlushTiming() throws {
        let core = FeatureRegistrationPassthroughCoreMock()
        let dateProvider = RelativeDateProvider(using: Date(timeIntervalSince1970: 0))

        config.featureFlags[.clientSideStats] = true
        config.dateProvider = dateProvider

        Trace.enable(with: config, in: core)

        let stats = try XCTUnwrap(core.get(feature: ClientStatsFeature.self))
        stats.concentrator.add(SpanSnapshot.mockWith(
            startTime: 20_000_000_000,
            duration: 5_000_000_000,
            isTopLevel: true
        ))

        stats.flushStats(.periodic)

        XCTAssertTrue(core.exportedBuckets.isEmpty)
    }

    // MARK: - Flush Telemetry

    func testHighCardinalityTrafficBoundsStoredAndWirePayloadsAndPreservesTotals() throws {
        let limit = StatsConcentrator.defaultMaxGroupsPerBucket
        var storedSizes: [Int] = []
        var wireSizes: [Int] = []
        for spanCount in [limit, limit + 1, 10_000] {
            let core = FeatureRegistrationPassthroughCoreMock()
            config.featureFlags[.clientSideStats] = true
            config.dateProvider = RelativeDateProvider(using: Date(timeIntervalSince1970: 0))
            Trace.enable(with: config, in: core)
            let stats = try XCTUnwrap(core.get(feature: ClientStatsFeature.self))
            for index in 0..<spanCount {
                stats.concentrator.add(.mockWith(resource: "GET /items/\(index)", startTime: 0, duration: 100))
            }

            stats.flushStats(.teardown)

            XCTAssertEqual(core.exportedBuckets.count, 1)
            let bucket = try XCTUnwrap(core.exportedBuckets.first)
            let expectedGroupCount = min(spanCount, limit + 1)
            XCTAssertEqual(bucket.stats.count, expectedGroupCount)
            XCTAssertEqual(bucket.stats.map(\.hits).reduce(0, +), UInt64(spanCount))
            storedSizes.append(try JSONEncoder().encode(bucket).count)
            let request = try makeRequestBuilder().request(
                for: [makeEvent(from: bucket)],
                with: .mockAny(),
                execution: .init(previousResponseCode: nil, attempt: 0)
            )
            wireSizes.append(try XCTUnwrap(request.decompressed().httpBody).count)
            let client = try firstClientStatsPayload(in: request)
            let wireBuckets = try XCTUnwrap(client["Stats"] as? [Any?])
            let wireBucket = try mapFields(wireBuckets[0])
            let wireGroups = try XCTUnwrap(wireBucket["Stats"] as? [Any?])
            XCTAssertEqual(wireGroups.count, expectedGroupCount)
            let wireHits = try wireGroups.map { try XCTUnwrap(mapFields($0)["Hits"] as? Int64) }.reduce(0, +)
            XCTAssertEqual(wireHits, Int64(spanCount))
            let collapsedMetric = core.telemetryMock.messages.firstMetric(named: TraceClientStatsMetric.collapsedSpansName)
            if spanCount == limit {
                XCTAssertNil(collapsedMetric)
            } else {
                let metric = try XCTUnwrap(collapsedMetric)
                XCTAssertEqual(metric.attributes[TraceClientStatsMetric.collapsedSpansCountKey] as? UInt64, UInt64(spanCount - limit))
            }
        }
        // Counters/sketch counts need a few more bytes, but new resource keys allocate no more groups.
        XCTAssertLessThan(storedSizes[2], storedSizes[1] + 100)
        XCTAssertLessThan(wireSizes[2], wireSizes[1] + 100)
    }

    func testAlternatingOverflowDeploymentsAreStoredOncePerDeploymentWithTheirWireIdentity() throws {
        let core = FeatureRegistrationPassthroughCoreMock(context: .mockWith(trackingConsent: .pending))
        config.featureFlags[.clientSideStats] = true
        config.dateProvider = RelativeDateProvider(using: Date(timeIntervalSince1970: 0))
        Trace.enable(with: config, in: core)
        let stats = try XCTUnwrap(core.get(feature: ClientStatsFeature.self))
        let limit = StatsConcentrator.defaultMaxGroupsPerBucket
        for index in 0..<limit {
            stats.concentrator.add(.mockWith(resource: "retained-\(index)", startTime: 0, duration: 100))
        }
        for version in ["one", "one", "two", "one"] {
            stats.concentrator.add(.mockWith(
                resource: "overflow",
                startTime: 0,
                duration: 100,
                deployment: .mockWith(env: "original-env", version: version, service: "original-service")
            ))
        }

        // The time bucket is still recent, so nothing is stored early.
        stats.flushStats(.periodic)
        XCTAssertTrue(core.exportedBuckets.isEmpty)

        stats.flushStats(.teardown)
        let overflowBuckets = core.exportedBuckets.filter { $0.env == "original-env" }
        XCTAssertEqual(overflowBuckets.compactMap(\.version).sorted(), ["one", "two"], "Each bucket and deployment is stored exactly once")
        XCTAssertEqual(overflowBuckets.first { $0.version == "one" }?.stats.map(\.hits), [3])
        XCTAssertEqual(overflowBuckets.first { $0.version == "two" }?.stats.map(\.hits), [1])
        XCTAssertEqual(core.exportedBuckets.flatMap(\.stats).map(\.hits).reduce(0, +), UInt64(limit + 4))
        XCTAssertTrue(core.writeContextBypassConsentValues.allSatisfy { !$0 }, "Pending data must use consent-aware storage")
        for bucket in overflowBuckets {
            let request = try makeRequestBuilder().request(
                for: [makeEvent(from: bucket)],
                with: .mockWith(env: "changed-env", version: "changed-version"),
                execution: .init(previousResponseCode: nil, attempt: 0)
            )
            let client = try firstClientStatsPayload(in: request)
            XCTAssertEqual(client["Env"] as? String, "original-env")
            XCTAssertEqual(client["Version"] as? String, bucket.version)
            XCTAssertEqual(client["Service"] as? String, "original-service")
        }
        let collapsed = try XCTUnwrap(core.telemetryMock.messages.firstMetric(named: TraceClientStatsMetric.collapsedSpansName))
        XCTAssertEqual(collapsed.attributes[TraceClientStatsMetric.collapsedSpansCountKey] as? UInt64, 4)
        XCTAssertEqual(collapsed.attributes[TraceClientStatsMetric.droppedSpansCountKey] as? UInt64, 0)
        let exportMetrics = core.telemetryMock.messages.compactMap(\.asMetric).filter { $0.name == TraceClientStatsMetric.name }
        XCTAssertEqual(exportMetrics.count, 1)
        XCTAssertEqual(exportMetrics.first?.attributes[TraceClientStatsMetric.spansCountKey] as? UInt64, UInt64(limit + 4))
        let count = core.exportedBuckets.count
        stats.flushStats(.teardown)
        XCTAssertEqual(core.exportedBuckets.count, count)
    }

    func testPeriodicFlushRunsOffTheMainThread() throws {
        // Given: a short flush interval and a bucket that is old enough to flush.
        let core = FeatureRegistrationPassthroughCoreMock()
        let dateProvider = RelativeDateProvider(using: Date(timeIntervalSince1970: 0))
        let feature = ClientStatsFeature(core: core, configuration: config, dateProvider: dateProvider, flushInterval: 0.05)
        feature.concentrator.add(.mockWith(startTime: 0, duration: 100))
        dateProvider.advance(bySeconds: 60)

        // When: the main run loop keeps running, as in an app.
        let deadline = Date().addingTimeInterval(5)
        while core.exportedBuckets.isEmpty && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        // Then: the periodic flush stored the bucket from its own queue.
        XCTAssertEqual(core.exportedBuckets.count, 1)
        XCTAssertEqual(core.writeContextOnMainThread.first, false)
        withExtendedLifetime(feature) {}
    }

    func testWhenFlushProducesBuckets_itSendsFlushMetric() throws {
        // Given
        let core = FeatureRegistrationPassthroughCoreMock()
        let dateProvider = RelativeDateProvider(using: Date(timeIntervalSince1970: 0))
        config.featureFlags[.clientSideStats] = true
        config.dateProvider = dateProvider

        Trace.enable(with: config, in: core)
        let stats = try XCTUnwrap(core.get(feature: ClientStatsFeature.self))

        // Two spans landing in the same aggregation group, one of them an error.
        stats.concentrator.add(.mockWith(startTime: 0, duration: 1_000_000_000, isTopLevel: true))
        stats.concentrator.add(.mockWith(isError: true, startTime: 0, duration: 2_000_000_000, isTopLevel: true))

        // When: advancing past the buffer window makes the bucket flushable.
        dateProvider.advance(bySeconds: 60)
        stats.flushStats(.periodic)

        // Then
        let metric = try XCTUnwrap(core.telemetryMock.messages.firstMetric(named: TraceClientStatsMetric.name))
        XCTAssertEqual(metric.attributes[SDKMetricFields.typeKey] as? String, TraceClientStatsMetric.typeValue)
        XCTAssertEqual(metric.attributes[TraceClientStatsMetric.bucketsCountKey] as? Int, 1)
        XCTAssertEqual(metric.attributes[TraceClientStatsMetric.groupsCountKey] as? Int, 1)
        XCTAssertEqual(metric.attributes[TraceClientStatsMetric.spansCountKey] as? UInt64, 2)
        XCTAssertEqual(metric.attributes[TraceClientStatsMetric.errorsCountKey] as? UInt64, 1)
        XCTAssertEqual(metric.attributes[TraceClientStatsMetric.forcedKey] as? Bool, false)
    }

    func testWhenForcedFlushProducesBuckets_itMarksMetricAsForced() throws {
        // Given
        let core = FeatureRegistrationPassthroughCoreMock()
        let dateProvider = RelativeDateProvider(using: Date(timeIntervalSince1970: 0))
        config.featureFlags[.clientSideStats] = true
        config.dateProvider = dateProvider

        Trace.enable(with: config, in: core)
        let stats = try XCTUnwrap(core.get(feature: ClientStatsFeature.self))
        stats.concentrator.add(.mockWith(startTime: 0, duration: 1_000_000_000, isTopLevel: true))

        // When: a forced flush (teardown) exports the still-recent bucket.
        stats.flushStats(.teardown)

        // Then
        let metric = try XCTUnwrap(core.telemetryMock.messages.firstMetric(named: TraceClientStatsMetric.name))
        XCTAssertEqual(metric.attributes[TraceClientStatsMetric.forcedKey] as? Bool, true)
        XCTAssertEqual(metric.attributes[TraceClientStatsMetric.spansCountKey] as? UInt64, 1)
    }

    func testWhenFlushProducesNoBuckets_itDoesNotSendFlushMetric() throws {
        // Given
        let core = FeatureRegistrationPassthroughCoreMock()
        config.featureFlags[.clientSideStats] = true
        config.dateProvider = RelativeDateProvider(using: Date(timeIntervalSince1970: 0))

        Trace.enable(with: config, in: core)
        let stats = try XCTUnwrap(core.get(feature: ClientStatsFeature.self))

        // When: nothing was aggregated, so the flush is empty.
        stats.flushStats(.teardown)

        // Then
        XCTAssertNil(core.telemetryMock.messages.firstMetric(named: TraceClientStatsMetric.name))
    }

    func testWhenConsentIsNotGranted_itDoesNotSendFlushMetric() throws {
        // Given
        let core = FeatureRegistrationPassthroughCoreMock()
        let dateProvider = RelativeDateProvider(using: Date(timeIntervalSince1970: 0))
        config.featureFlags[.clientSideStats] = true
        config.dateProvider = dateProvider

        Trace.enable(with: config, in: core)
        let stats = try XCTUnwrap(core.get(feature: ClientStatsFeature.self))

        // When: consent is revoked, aggregation and flush are gated off.
        stats.concentrator.updateConsent(.notGranted)
        stats.concentrator.add(.mockWith(startTime: 0, duration: 1_000_000_000, isTopLevel: true))
        dateProvider.advance(bySeconds: 60)
        stats.flushStats(.teardown)

        // Then: no buckets are exported, so no metric is emitted.
        XCTAssertNil(core.telemetryMock.messages.firstMetric(named: TraceClientStatsMetric.name))
    }

    // MARK: - Request Builder - Encoding

    // MARK: - Storage Event Limit

    func testJSONSizeEstimateBoundsEscapingBase64AndMaximumWidthFields() throws {
        let swiftStrings = [
            "", "ascii /path", "\"\\\n\r\t", "\u{0000}\u{001f}",
            "é👩🏽‍💻e\u{0301}", "\u{2028}\u{2029}",
            String(repeating: "\"\\\u{0000}", count: 1_024),
            String(repeating: "é👩🏽‍💻", count: 512),
            String(repeating: "long-resource/", count: 1_000)
        ]
        // Strings bridged from Objective-C have no contiguous UTF-8 storage, so they take the other scan.
        let strings = swiftStrings + swiftStrings.map { NSMutableString(string: $0) as String }
        for string in strings {
            for byteCount in [0, 1, 2, 3, 4, 5, 16_384] {
                let group = ExportedGroupedStats(
                    service: string,
                    name: string,
                    resource: string,
                    httpStatusCode: .max,
                    type: string,
                    spanKind: string,
                    isTraceRoot: .notSet,
                    synthetics: false,
                    hits: .max,
                    errors: .max,
                    duration: .max,
                    topLevelHits: .max,
                    okSummary: Data(repeating: 0xff, count: byteCount),
                    errorSummary: Data(repeating: 0, count: byteCount),
                    peerTags: Array(repeating: string, count: 6),
                    serviceSource: string
                )
                XCTAssertGreaterThanOrEqual(try estimatedSize(of: group), try JSONEncoder.dd.default().encode(group).count)
                let metadata: [(ExportedBucket.PayloadIdentity?, Int?)] = [(nil, nil), (.init(runtimeID: string, sequence: .max), .max)]
                for (payload, pieceCount) in metadata {
                    let bucket = ExportedBucket(
                        start: .max,
                        duration: .max,
                        stats: [group, group],
                        env: string,
                        version: string,
                        service: string,
                        payload: payload,
                        pieceCount: pieceCount
                    )
                    XCTAssertGreaterThanOrEqual(try estimatedSize(of: bucket), try encodedSize(of: bucket))
                }
            }
        }
    }

    func testFixedJSONSizeAllowancesCoverTheWorstCaseLayout() throws {
        // Every string empty and every number at its widest. The estimator counts each string's and
        // sketch's quotes with the value itself, so they are not part of the fixed size.
        let header = ExportedBucket(
            start: .max,
            duration: .max,
            stats: [],
            env: "",
            version: "",
            service: "",
            payload: .init(runtimeID: "", sequence: .max),
            pieceCount: .min
        )
        let headerFixedSize = try encodedSize(of: header) - 2 * 4
        XCTAssertEqual(headerFixedSize, 193)
        XCTAssertLessThanOrEqual(headerFixedSize, ExportedBucket.fixedJSONSizeAllowance)

        for isTraceRoot in [Trilean.notSet, .true, .false] {
            for synthetics in [false, true] {
                let group = ExportedGroupedStats(
                    service: "",
                    name: "",
                    resource: "",
                    httpStatusCode: .max,
                    type: "",
                    spanKind: "",
                    isTraceRoot: isTraceRoot,
                    synthetics: synthetics,
                    hits: .max,
                    errors: .max,
                    duration: .max,
                    topLevelHits: .max,
                    okSummary: Data(),
                    errorSummary: Data(),
                    peerTags: [],
                    serviceSource: ""
                )
                let groupFixedSize = try JSONEncoder.dd.default().encode(group).count - 2 * 8
                XCTAssertLessThanOrEqual(groupFixedSize, 301)
                XCTAssertLessThanOrEqual(groupFixedSize, ExportedGroupedStats.fixedJSONSizeAllowance)
            }
        }
    }

    func testJSONSizeEstimateStopsAtTheBudgetAndSupportsTheLargestBudget() throws {
        let bucket = ExportedBucket(start: 0, duration: 10, stats: [makeGroup(resource: String(repeating: "x", count: 1_000_000))], env: "env", version: "1.0", service: "app")
        for budget in [1, 512, 1_024] {
            XCTAssertEqual(bucket.estimatedJSONSize(budget: budget), .exceedsBudget)
        }
        guard case .fits(let size) = bucket.estimatedJSONSize(budget: .max - 1) else {
            return XCTFail("A finite value fits the largest budget")
        }
        XCTAssertGreaterThan(size, 1_000_000)
        let result = bucket.split(toFit: 1)
        XCTAssertTrue(result.pieces.isEmpty)
        XCTAssertEqual(result.oversizedGroups.count, 1)
    }

    func testJSONSizeEstimateAtExactlyTheBudgetFits() throws {
        let bucket = makeExportedBucket(groupCount: 3, env: "prod", version: "1.0.0", service: "app")
        let size = try estimatedSize(of: bucket)

        XCTAssertEqual(bucket.estimatedJSONSize(budget: size), .fits(size))
        XCTAssertEqual(bucket.estimatedJSONSize(budget: size - 1), .exceedsBudget)
    }

    func testWhenSplittingEscapedStrings_estimatesBoundEveryStoredPiece() throws {
        let groups = (0..<20).map { makeGroup(resource: "\($0)\"\\\u{0000}é👩🏽‍💻") }
        let bucket = ExportedBucket(
            start: .max,
            duration: .max,
            stats: groups,
            env: "prod\n",
            version: "é",
            service: "service\\name"
        )
        let limit = 2_000
        let result = split(bucket, toFit: limit)
        XCTAssertGreaterThan(result.pieces.count, 1)
        XCTAssertTrue(result.oversizedGroups.isEmpty)
        XCTAssertEqual(result.pieces.flatMap(\.stats).map(\.resource), groups.map(\.resource))
        for piece in result.pieces {
            XCTAssertLessThanOrEqual(try encodedSize(of: piece), try estimatedSize(of: piece))
            XCTAssertNotEqual(piece.estimatedJSONSize(budget: limit), .exceedsBudget)
        }
    }

    func testWhenDeploymentMetadataCannotFit_noOversizedPieceIsWritten() {
        let bucket = makeExportedBucket(groupCount: 3, env: String(repeating: "x", count: 2_000))
        let result = split(bucket, toFit: 2_000)
        XCTAssertTrue(result.pieces.isEmpty)
        XCTAssertEqual(result.oversizedGroups.count, 3)
    }

    func testStoredBucketBudgetSurvivesEncryptionThatDoublesTheSize() {
        // Actual JSON never exceeds the estimate, which never exceeds the budget. A hex-encoding
        // `DataEncryption` doubles it, and the batch block adds a 2-byte type and a 4-byte length.
        let storageEventLimit = 1_024 * 1_024
        let blockHeaderSize = 6
        XCTAssertLessThanOrEqual(2 * ClientStatsFeature.maxStoredBucketSize + blockHeaderSize, storageEventLimit)
    }

    func testWhenBucketFitsTheLimit_splitReturnsItWhole() throws {
        let bucket = makeExportedBucket(groupCount: 3, env: "prod", version: "1.0.0", service: "app")
            .assigning(.init(runtimeID: splitRuntimeID, sequence: 1))

        let result = bucket.split(toFit: try estimatedSize(of: bucket))

        XCTAssertEqual(result.pieces.count, 1)
        XCTAssertFalse(result.pieces[0].isPartial)
        XCTAssertEqual(result.pieces[0].stats.map(\.service), bucket.stats.map(\.service))
        XCTAssertTrue(result.oversizedGroups.isEmpty)
    }

    func testWhenBucketExceedsTheLimit_itIsSplitIntoPartialBucketsThatFit() throws {
        let bucket = makeExportedBucket(start: 7_000, groupCount: 50, env: "prod", version: "1.0.0", service: "app")
        let limit = 2_000
        XCTAssertGreaterThan(try encodedSize(of: bucket), limit)

        let result = split(bucket, toFit: limit)

        XCTAssertGreaterThan(result.pieces.count, 1)
        XCTAssertTrue(result.oversizedGroups.isEmpty)
        for piece in result.pieces {
            XCTAssertLessThanOrEqual(try encodedSize(of: piece), limit)
            XCTAssertEqual(piece.pieceCount, result.pieces.count)
            XCTAssertEqual(piece.start, 7_000)
            XCTAssertEqual(piece.duration, bucket.duration)
            XCTAssertEqual(piece.env, "prod")
            XCTAssertEqual(piece.version, "1.0.0")
            XCTAssertEqual(piece.service, "app")
        }
        XCTAssertEqual(result.pieces.flatMap(\.stats).map(\.service), bucket.stats.map(\.service), "Every group is kept once, in order")
    }

    func testWhenAGroupCannotFitAlone_itIsReturnedAsOversizedAndTheOthersAreStored() throws {
        let limit = ClientStatsFeature.maxStoredBucketSize
        let normal = makeExportedBucket(groupCount: 3, env: "prod", version: "1.0.0", service: "app")
        let oversized = makeGroup(resource: String(repeating: "a", count: limit))
        let bucket = ExportedBucket(
            start: normal.start,
            duration: normal.duration,
            stats: [normal.stats[0], oversized, normal.stats[1], normal.stats[2]],
            env: "prod",
            version: "1.0.0",
            service: "app"
        )

        let result = split(bucket, toFit: limit)

        XCTAssertEqual(result.oversizedGroups.map(\.resource), [oversized.resource])
        XCTAssertEqual(result.pieces.flatMap(\.stats).map(\.service), normal.stats.map(\.service))
        for piece in result.pieces {
            XCTAssertLessThanOrEqual(try encodedSize(of: piece), limit)
        }
    }

    func testWhenTheOnlyGroupCannotFitAlone_nothingIsStored() throws {
        let limit = ClientStatsFeature.maxStoredBucketSize
        let bucket = ExportedBucket(start: 1_000, duration: 10, stats: [makeGroup(resource: String(repeating: "a", count: limit))], env: "env", version: "1.0", service: "app")

        let result = split(bucket, toFit: limit)

        XCTAssertTrue(result.pieces.isEmpty)
        XCTAssertEqual(result.oversizedGroups.count, 1)
    }

    func testWhenAFlushedGroupCannotFitAlone_itIsDroppedAndReportedWhileOthersAreStored() throws {
        let core = FeatureRegistrationPassthroughCoreMock()
        config.featureFlags[.clientSideStats] = true
        config.dateProvider = RelativeDateProvider(using: Date(timeIntervalSince1970: 0))
        Trace.enable(with: config, in: core)
        let stats = try XCTUnwrap(core.get(feature: ClientStatsFeature.self))
        stats.concentrator.add(.mockWith(resource: String(repeating: "a", count: ClientStatsFeature.maxStoredBucketSize), startTime: 0, duration: 100))
        stats.concentrator.add(.mockWith(resource: "GET /items", startTime: 0, duration: 100))
        stats.concentrator.add(.mockWith(resource: "GET /items", startTime: 0, duration: 100))

        stats.flushStats(.teardown)

        XCTAssertEqual(core.exportedBuckets.flatMap(\.stats).map(\.resource), ["GET /items"])
        XCTAssertEqual(core.exportedBuckets.flatMap(\.stats).map(\.hits), [2])
        for bucket in core.exportedBuckets {
            XCTAssertLessThanOrEqual(try encodedSize(of: bucket), ClientStatsFeature.maxStoredBucketSize)
        }
        let metric = try XCTUnwrap(core.telemetryMock.messages.firstMetric(named: TraceClientStatsMetric.name))
        XCTAssertEqual(metric.attributes[TraceClientStatsMetric.oversizedGroupsCountKey] as? Int, 1)
        XCTAssertEqual(metric.attributes[TraceClientStatsMetric.oversizedSpansCountKey] as? UInt64, 1)
    }

    func testWhenWideLatencyBucketIsSplit_everySpanAndSketchReachesTheIntakeOnce() throws {
        // Given: 100 groups of fast and very slow successful and failed requests ending in one window.
        // Their sketches span about 550 bins each, so the bucket encodes to more than the 1 MB
        // storage event limit. `expected` is the same input flushed without splitting.
        let groupCount = StatsConcentrator.defaultMaxGroupsPerBucket
        let durations: [UInt64] = [1_000_000, 60_000_000_000]
        let end: UInt64 = 100_000_000_000
        let addSpans = { (concentrator: StatsConcentrator) in
            for group in 0..<groupCount {
                for duration in durations {
                    for isError in [false, true] {
                        concentrator.add(.mockWith(resource: "GET /\(group)", isError: isError, startTime: end - duration, duration: duration))
                    }
                }
            }
        }
        let reference = StatsConcentrator(now: 0, initialConsent: .granted)
        addSpans(reference)
        let expected = try XCTUnwrap(reference.flush(now: 0, force: true).first)
        XCTAssertGreaterThan(try encodedSize(of: expected), 1_024 * 1_024)

        let core = FeatureRegistrationPassthroughCoreMock()
        config.featureFlags[.clientSideStats] = true
        config.dateProvider = RelativeDateProvider(using: Date(timeIntervalSince1970: 0))
        Trace.enable(with: config, in: core)
        let stats = try XCTUnwrap(core.get(feature: ClientStatsFeature.self))
        addSpans(stats.concentrator)

        // When
        stats.flushStats(.teardown)

        // Then: every stored piece fits.
        let pieces = core.exportedBuckets
        XCTAssertGreaterThan(pieces.count, 1)
        for piece in pieces {
            XCTAssertLessThanOrEqual(try encodedSize(of: piece), ClientStatsFeature.maxStoredBucketSize)
            XCTAssertEqual(piece.pieceCount, pieces.count)
        }

        // Then: with each piece in its own request, every request is marked split, keeps the identity,
        // and together they carry every group exactly once with unchanged counts and sketches.
        var uploadedGroups: [[String: Any?]] = []
        var fragmentIDs: Set<String> = []
        let builder = makeRequestBuilder()
        for piece in pieces {
            let request = try builder.request(
                for: [makeEvent(from: piece)],
                with: .mockWith(env: "upload-env", version: "upload-version"),
                execution: .init(previousResponseCode: nil, attempt: 0)
            )
            XCTAssertEqual(try decodeEnvelope(in: request)["SplitPayload"] as? Bool, true)
            let client = try firstClientStatsPayload(in: request)
            fragmentIDs.insert("\(client["RuntimeID"] as? String ?? "")/\(client["Sequence"] as? Int64 ?? 0)")
            XCTAssertEqual(client["Env"] as? String, expected.env)
            XCTAssertEqual(client["Version"] as? String, expected.version)
            XCTAssertEqual(client["Service"] as? String, expected.service)
            let wireBuckets = try XCTUnwrap(client["Stats"] as? [Any?]).map(mapFields)
            XCTAssertEqual(wireBuckets.map { $0["Start"] as? Int64 }, [Int64(expected.start)])
            uploadedGroups += try wireBuckets.flatMap { try XCTUnwrap($0["Stats"] as? [Any?]).map(mapFields) }
        }
        let splitID = try XCTUnwrap(pieces.first?.payload)
        XCTAssertEqual(fragmentIDs, ["\(splitID.runtimeID)/\(splitID.sequence)"], "Every fragment carries the split's runtime ID and sequence number")
        XCTAssertEqual(uploadedGroups.count, groupCount)
        let uploadedByResource = Dictionary(uniqueKeysWithValues: uploadedGroups.map { ($0["Resource"] as? String ?? "", $0) })
        XCTAssertEqual(uploadedByResource.count, groupCount, "No group is duplicated")
        for group in expected.stats {
            let uploaded = try XCTUnwrap(uploadedByResource[group.resource])
            XCTAssertEqual(uploaded["Hits"] as? Int64, Int64(group.hits))
            XCTAssertEqual(uploaded["Errors"] as? Int64, Int64(group.errors))
            XCTAssertEqual(uploaded["Duration"] as? Int64, Int64(group.duration))
            XCTAssertEqual(uploaded["OkSummary"] as? Data, group.okSummary)
            XCTAssertEqual(uploaded["ErrorSummary"] as? Data, group.errorSummary)
        }
        XCTAssertEqual(uploadedGroups.compactMap { $0["Hits"] as? Int64 }.reduce(0, +), Int64(groupCount * 4))
        XCTAssertEqual(uploadedGroups.compactMap { $0["Errors"] as? Int64 }.reduce(0, +), Int64(groupCount * 2))
        XCTAssertEqual(
            uploadedGroups.compactMap { $0["Duration"] as? Int64 }.reduce(0, +),
            Int64(groupCount) * 2 * Int64(durations.reduce(0, +))
        )

        // Then: with all pieces in one request, they are merged back into one bucket that is not split.
        let request = try makeRequestBuilder().request(
            for: pieces.map(makeEvent(from:)),
            with: .mockAny(),
            execution: .init(previousResponseCode: nil, attempt: 0)
        )
        XCTAssertEqual(try decodeEnvelope(in: request)["SplitPayload"] as? Bool, false)
        let wireBuckets = try XCTUnwrap(firstClientStatsPayload(in: request)["Stats"] as? [Any?])
        XCTAssertEqual(wireBuckets.count, 1)
        XCTAssertEqual((try mapFields(wireBuckets[0])["Stats"] as? [Any?])?.count, groupCount)
    }

    func testWhenBatchHoldsPartialBuckets_itMergesEachWindowAndMarksThePayloadSplit() throws {
        let window = makeExportedBucket(start: 1_000, groupCount: 4, env: "prod", version: "1.0.0", service: "app")
        let onePiecePerGroup = try estimatedSize(of: ExportedBucket(
            start: window.start,
            duration: window.duration,
            stats: [window.stats[0]],
            env: "prod",
            version: "1.0.0",
            service: "app",
            payload: .init(runtimeID: splitRuntimeID, sequence: 1),
            pieceCount: 4
        ))
        let pieces = split(window, toFit: onePiecePerGroup).pieces
        XCTAssertEqual(pieces.map(\.stats.count), [1, 1, 1, 1])
        let otherVersion = makeExportedBucket(start: 1_000, groupCount: 1, env: "prod", version: "2.0.0", service: "app")
        let whole = makeExportedBucket(start: 2_000, groupCount: 2, env: "prod", version: "1.0.0", service: "app")
        let events = [pieces[0], whole, pieces[1], otherVersion, pieces[2]].map(makeEvent(from:))

        let request = try makeRequestBuilder().request(for: events, with: .mockAny(), execution: .init(previousResponseCode: nil, attempt: 0))

        let envelope = try decodeEnvelope(in: request)
        XCTAssertEqual(envelope["SplitPayload"] as? Bool, true, "The fourth piece may travel in another request")
        // The split is its own client payload; whole buckets of each identity share one.
        let payloads = try allClientStatsPayloads(in: request)
        XCTAssertEqual(payloads.map { $0["Version"] as? String }, ["1.0.0", "1.0.0", "2.0.0"])
        XCTAssertEqual(payloads.map { $0["RuntimeID"] as? String }, [splitRuntimeID, "runtime-id", "runtime-id"])
        XCTAssertEqual(payloads[0]["Sequence"] as? Int64, Int64(try XCTUnwrap(pieces[0].payload?.sequence)))
        let splitBuckets = try XCTUnwrap(payloads[0]["Stats"] as? [Any?]).map(mapFields)
        XCTAssertEqual(splitBuckets.map { $0["Start"] as? Int64 }, [1_000])
        XCTAssertEqual(splitBuckets.map { ($0["Stats"] as? [Any?])?.count }, [3])
        let wholeBuckets = try XCTUnwrap(payloads[1]["Stats"] as? [Any?]).map(mapFields)
        XCTAssertEqual(wholeBuckets.map { $0["Start"] as? Int64 }, [2_000])
    }

    func testWhenBatchHoldsEveryPieceOfAWindow_itMergesThemWithoutMarkingThePayloadSplit() throws {
        let window = makeExportedBucket(start: 1_000, groupCount: 4, env: "prod", version: "1.0.0", service: "app")
        let onePiecePerGroup = try estimatedSize(of: ExportedBucket(
            start: window.start,
            duration: window.duration,
            stats: [window.stats[0]],
            env: "prod",
            version: "1.0.0",
            service: "app",
            payload: .init(runtimeID: splitRuntimeID, sequence: 1),
            pieceCount: 4
        ))
        let pieces = split(window, toFit: onePiecePerGroup).pieces
        XCTAssertEqual(pieces.count, 4)

        let request = try makeRequestBuilder().request(
            for: pieces.reversed().map(makeEvent(from:)),
            with: .mockAny(),
            execution: .init(previousResponseCode: nil, attempt: 0)
        )

        XCTAssertEqual(try decodeEnvelope(in: request)["SplitPayload"] as? Bool, false)
        let buckets = try XCTUnwrap(firstClientStatsPayload(in: request)["Stats"] as? [Any?])
        XCTAssertEqual(buckets.count, 1)
        XCTAssertEqual((try mapFields(buckets[0])["Stats"] as? [Any?])?.count, 4)
    }

    func testWhenTheSameWindowIsSplitTwice_eachSplitIsReassembledAndCheckedOnItsOwn() throws {
        // Given: two exports of one window, for example a periodic flush and a later forced flush.
        let first = makeExportedBucket(start: 1_000, groupCount: 2, env: "prod", version: "1.0.0", service: "app")
        let second = makeExportedBucket(start: 1_000, groupCount: 3, env: "prod", version: "1.0.0", service: "app")
        let onePiecePerGroup = try estimatedSize(of: ExportedBucket(
            start: 1_000,
            duration: first.duration,
            stats: [first.stats[0]],
            env: "prod",
            version: "1.0.0",
            service: "app",
            payload: .init(runtimeID: splitRuntimeID, sequence: 1),
            pieceCount: 3
        ))
        let firstPieces = split(first, toFit: onePiecePerGroup).pieces
        let secondPieces = split(second, toFit: onePiecePerGroup).pieces
        XCTAssertEqual(firstPieces.count, 2)
        XCTAssertEqual(secondPieces.count, 3)
        XCTAssertNotEqual(firstPieces[0].payload?.sequence, secondPieces[0].payload?.sequence)

        // When: a batch holds both pieces of the first split and one of the second.
        let partial = try makeRequestBuilder().request(
            for: (firstPieces + [secondPieces[0]]).map(makeEvent(from:)),
            with: .mockAny(),
            execution: .init(previousResponseCode: nil, attempt: 0)
        )

        // Then: the second split is incomplete, and the two exports stay separate payloads.
        XCTAssertEqual(try decodeEnvelope(in: partial)["SplitPayload"] as? Bool, true)
        XCTAssertEqual(try groupCountsPerPayload(in: partial), [[2], [1]])

        // When: a batch holds every piece of both splits.
        let complete = try makeRequestBuilder().request(
            for: (firstPieces + secondPieces).map(makeEvent(from:)),
            with: .mockAny(),
            execution: .init(previousResponseCode: nil, attempt: 0)
        )

        // Then
        XCTAssertEqual(try decodeEnvelope(in: complete)["SplitPayload"] as? Bool, false)
        XCTAssertEqual(try groupCountsPerPayload(in: complete), [[2], [3]])
    }

    func testWhenSplitPiecesAreUploadedSeparatelyRetriedOrAfterARestart_theyKeepTheSplitsPayloadIdentity() throws {
        let window = makeExportedBucket(start: 1_000, groupCount: 2, env: "prod", version: "1.0.0", service: "app")
        let onePiecePerGroup = try estimatedSize(of: ExportedBucket(
            start: 1_000,
            duration: window.duration,
            stats: [window.stats[0]],
            env: "prod",
            version: "1.0.0",
            service: "app",
            payload: .init(runtimeID: splitRuntimeID, sequence: 1),
            pieceCount: 2
        ))
        let pieces = split(window, toFit: onePiecePerGroup).pieces
        XCTAssertEqual(pieces.count, 2)
        let splitSequence = Int64(try XCTUnwrap(pieces[0].payload?.sequence))

        let sameProcess = makeRequestBuilder()
        // After a restart: pieces left on disk are uploaded by a new runtime.
        let afterRestart = makeRequestBuilder()
        let builds: [(StatsRequestBuilder, ExportedBucket)] = [
            (sameProcess, pieces[0]),
            (sameProcess, pieces[0]), // retry
            (afterRestart, pieces[1])
        ]

        for (builder, piece) in builds {
            let request = try builder.request(for: [makeEvent(from: piece)], with: .mockAny(), execution: .init(previousResponseCode: nil, attempt: 0))
            let client = try firstClientStatsPayload(in: request)
            XCTAssertEqual(client["RuntimeID"] as? String, splitRuntimeID)
            XCTAssertEqual(client["Sequence"] as? Int64, splitSequence)
            XCTAssertEqual(try decodeEnvelope(in: request)["SplitPayload"] as? Bool, true)
        }
    }

    // MARK: - Payload Identity

    func testWhenFlushStoresBuckets_eachGetsAPayloadIdentityIncreasingInWriteOrder() throws {
        let (core, stats) = try enableClientStats()
        stats.concentrator.add(.mockWith(startTime: 0, duration: 100, deployment: .mockWith(version: "1.0.0")))
        stats.concentrator.add(.mockWith(startTime: 0, duration: 100, deployment: .mockWith(version: "2.0.0")))
        stats.flushStats(.teardown)
        stats.concentrator.add(.mockWith(startTime: 20_000_000_000, duration: 100))
        stats.flushStats(.teardown)

        let payloads = core.exportedBuckets.compactMap(\.payload)
        XCTAssertEqual(payloads.count, 3, "Every stored bucket has a payload identity")
        XCTAssertEqual(Set(payloads.map(\.runtimeID)).count, 1)
        XCTAssertEqual(payloads.map(\.sequence), payloads.map(\.sequence).sorted())
        XCTAssertEqual(Set(payloads.map(\.sequence)).count, 3)
    }

    func testWhenAWholeBucketIsStoredBeforeASplitOne_oneRequestCarriesIncreasingSequences() throws {
        // Given: a whole bucket stored first, then a bucket split into pieces.
        let (core, stats) = try enableClientStats()
        stats.concentrator.add(.mockWith(resource: "GET /small", startTime: 0, duration: 100))
        stats.flushStats(.teardown)
        addWideLatencySpans(to: stats.concentrator, endingAt: 100_000_000_000)
        stats.flushStats(.teardown)
        let events = core.exportedBuckets.map(makeEvent(from:))
        XCTAssertGreaterThan(events.count, 2)
        let builder = try XCTUnwrap(stats.requestBuilder as? StatsRequestBuilder)

        // When
        let request = try builder.request(for: events, with: .mockAny(), execution: .init(previousResponseCode: nil, attempt: 0))

        // Then: payloads appear in storage order with increasing sequence numbers, and the split is complete.
        let sequences = try allClientStatsPayloads(in: request).compactMap { $0["Sequence"] as? Int64 }
        XCTAssertEqual(sequences.count, 2)
        XCTAssertLessThan(sequences[0], sequences[1])
        XCTAssertEqual(try decodeEnvelope(in: request)["SplitPayload"] as? Bool, false)
    }

    func testWhenABatchIsRetriedOrUploadedAfterARestart_itKeepsEveryPayloadIdentity() throws {
        let (core, stats) = try enableClientStats()
        stats.concentrator.add(.mockWith(resource: "GET /small", startTime: 0, duration: 100))
        stats.flushStats(.teardown)
        addWideLatencySpans(to: stats.concentrator, endingAt: 100_000_000_000)
        stats.flushStats(.teardown)
        let events = core.exportedBuckets.map(makeEvent(from:))
        let builder = try XCTUnwrap(stats.requestBuilder as? StatsRequestBuilder)
        let afterRestart = makeRequestBuilder()

        func identities(of request: URLRequest) throws -> [String] {
            try allClientStatsPayloads(in: request).map { "\($0["RuntimeID"] as? String ?? "")/\($0["Sequence"] as? Int64 ?? -1)" }
        }
        let first = try identities(of: builder.request(for: events, with: .mockAny(), execution: .init(previousResponseCode: nil, attempt: 0)))
        let retry = try identities(of: builder.request(for: events, with: .mockAny(), execution: .init(previousResponseCode: 500, attempt: 1)))
        let restarted = try identities(of: afterRestart.request(for: events, with: .mockAny(), execution: .init(previousResponseCode: nil, attempt: 0)))

        let stored = core.exportedBuckets.compactMap(\.payload).map { "\($0.runtimeID)/\($0.sequence)" }
        XCTAssertEqual(first, Array(NSOrderedSet(array: stored)) as? [String])
        XCTAssertEqual(retry, first)
        XCTAssertEqual(restarted, first)
    }

    func testWhenABatchHoldsABucketWithoutPayloadIdentity_theWholeBatchIsDropped() throws {
        // Given: a bucket stored by an earlier internal build, next to a current one in the same file.
        let earlierBuild = Event(data: Data(#"{"start":1000,"duration":10000000000,"stats":[],"env":"prod","version":"1.0.0","service":"app"}"#.utf8))
        let current = makeEvent(from: makeExportedBucket(env: "prod", version: "1.0.0", service: "app"))

        // Then: upgrades from those builds are not supported, so the batch cannot be built and is dropped.
        XCTAssertThrowsError(try makeRequestBuilder().request(for: [earlierBuild, current], with: .mockAny(), execution: .init(previousResponseCode: nil, attempt: 0)))
    }

    func testWhenBatchHoldsOnlyWholeBuckets_itDoesNotMarkThePayloadSplit() throws {
        let events = [makeExportedBucket(start: 1_000), makeExportedBucket(start: 1_000)].map(makeEvent(from:))

        let request = try makeRequestBuilder().request(for: events, with: .mockAny(), execution: .init(previousResponseCode: nil, attempt: 0))

        XCTAssertEqual(try decodeEnvelope(in: request)["SplitPayload"] as? Bool, false)
        XCTAssertEqual(try groupCountsPerPayload(in: request), [[1], [1]], "Whole buckets are never merged")
    }

    func testWhenBuildingRequest_itTargetsStatsIntakeWithMsgPackContentType() throws {
        // Given
        let context: DatadogContext = .mockWith(clientToken: "client-token", source: "ios", ciAppOrigin: nil)
        let builder = makeRequestBuilder()

        // When
        let request = try builder.request(
            for: [makeEvent(from: makeExportedBucket())],
            with: context,
            execution: .init(previousResponseCode: nil, attempt: 0)
        )

        // Then
        XCTAssertEqual(request.url, context.site.endpoint.appendingPathComponent("api/v0.2/stats"))
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.allHTTPHeaderFields?["Content-Type"], "application/msgpack")
        XCTAssertEqual(request.allHTTPHeaderFields?["DD-API-KEY"], "client-token")
        XCTAssertEqual(request.allHTTPHeaderFields?["DD-EVP-ORIGIN"], "ios")
        XCTAssertEqual(request.allHTTPHeaderFields?["DD-EVP-ORIGIN-VERSION"], context.sdkVersion)
        XCTAssertEqual(request.allHTTPHeaderFields?["DD-REQUEST-ID"]?.matches(regex: .uuidRegex), true)
    }

    func testWhenBuildingRequest_itCompressesBodyWithDeflate() throws {
        // Given: a payload large and repetitive enough that deflate shrinks it.
        let builder = makeRequestBuilder()

        // When
        let request = try builder.request(
            for: [makeEvent(from: makeExportedBucket(groupCount: 20))],
            with: .mockAny(),
            execution: .init(previousResponseCode: nil, attempt: 0)
        )

        // Then
        XCTAssertEqual(request.allHTTPHeaderFields?["Content-Encoding"], "deflate")
        XCTAssertNotNil(try request.decompressed().httpBody)
    }

    func testWhenBuildingRequest_itEncodesEnvelopeFromContext() throws {
        // Given
        let context: DatadogContext = .mockWith(
            service: "ios-app",
            env: "staging",
            version: "1.2.3",
            sdkVersion: "2.0.0"
        )
        let builder = makeRequestBuilder()

        // When
        let request = try builder.request(
            for: [makeEvent(from: makeExportedBucket(env: "prod", version: "1.0.0", service: "app"))],
            with: context,
            execution: .init(previousResponseCode: nil, attempt: 0)
        )

        // Then: the deployment identity comes from the bucket, not the upload-time context.
        let clientStats = try firstClientStatsPayload(in: request)
        XCTAssertEqual(clientStats["Hostname"] as? String, "")
        XCTAssertEqual(clientStats["Env"] as? String, "prod")
        XCTAssertEqual(clientStats["Version"] as? String, "1.0.0")
        XCTAssertEqual(clientStats["Service"] as? String, "app")
        XCTAssertEqual(clientStats["TracerVersion"] as? String, "2.0.0")
        XCTAssertEqual(clientStats["Lang"] as? String, "ios")
        XCTAssertEqual(clientStats["RuntimeID"] as? String, "runtime-id")
        XCTAssertEqual(clientStats["Sequence"] as? Int64, 1)
    }

    func testShiftingToTheServerClockMovesTheStartAndKeepsItAlignedToBuckets() {
        let bucketDuration: UInt64 = 10_000_000_000
        let start = 170_000_000 * bucketDuration
        let cases: [(offset: TimeInterval, start: UInt64, expected: UInt64)] = [
            (0, 1_000, 1_000), // no offset keeps the start exactly
            (3_600, start, start + 360 * bucketDuration), // device clock an hour behind
            (-7.4, start, start - bucketDuration), // rounds to the nearest boundary
            (2, start, start), // under half a bucket
            (1, .max, .max), // a saturated start stays saturated
            (-100, 0, 0)
        ]
        for testCase in cases {
            let bucket = makeExportedBucket(start: testCase.start, duration: bucketDuration)
            XCTAssertEqual(bucket.shiftedToServerClock(by: testCase.offset).start, testCase.expected, "Offset \(testCase.offset)")
        }
    }

    func testWhenTheClockSynchronizesAfterSpansFinished_theirBucketUsesTheNewerOffset() throws {
        // Given: spans finish at startup, before the first clock synchronization, so the offset is still 0.
        let core = FeatureRegistrationPassthroughCoreMock(context: .mockWith(serverTimeOffset: 0))
        config.featureFlags[.clientSideStats] = true
        config.dateProvider = RelativeDateProvider(using: Date(timeIntervalSince1970: 0))
        Trace.enable(with: config, in: core)
        let stats = try XCTUnwrap(core.get(feature: ClientStatsFeature.self))
        stats.record(.mockWith(startTime: 0, duration: 100))

        // When: the synchronization finds the device clock an hour behind before the bucket is stored.
        core.contextValue = .mockWith(serverTimeOffset: 3_600)
        stats.flushStats(.teardown)

        // Then: the bucket uses the newer offset. It is intentionally not the offset of each span, which
        // comes from the context the span captured when it started, so it can still be the unsynchronized 0.
        XCTAssertEqual(core.exportedBuckets.first?.start, 3_600_000_000_000)
    }

    func testWhenABucketIsStored_itKeepsTheServerOffsetOfThatMomentWhateverTheUploadContext() throws {
        // Given: the device clock is an hour behind when the bucket is stored.
        let core = FeatureRegistrationPassthroughCoreMock(context: .mockWith(serverTimeOffset: 3_600))
        config.featureFlags[.clientSideStats] = true
        config.dateProvider = RelativeDateProvider(using: Date(timeIntervalSince1970: 0))
        Trace.enable(with: config, in: core)
        let stats = try XCTUnwrap(core.get(feature: ClientStatsFeature.self))
        stats.concentrator.add(.mockWith(startTime: 0, duration: 100))
        stats.flushStats(.teardown)
        let stored = try XCTUnwrap(core.exportedBuckets.first)
        XCTAssertEqual(stored.start, 3_600_000_000_000)

        // When: it is uploaded, and retried, after the offset changed, for example after a relaunch.
        let builder = try XCTUnwrap(stats.requestBuilder as? StatsRequestBuilder)
        for (offset, attempt): (TimeInterval, UInt) in [(0, 0), (-500, 1)] {
            let request = try builder.request(
                for: [makeEvent(from: stored)],
                with: .mockWith(serverTimeOffset: offset),
                execution: .init(previousResponseCode: attempt > 0 ? 500 : nil, attempt: attempt)
            )

            // Then: the uploaded start is the stored one.
            let bucket = try mapFields(try XCTUnwrap(firstClientStatsPayload(in: request)["Stats"] as? [Any?]).first ?? nil)
            XCTAssertEqual(bucket["Start"] as? Int64, 3_600_000_000_000, "Upload offset \(offset)")
        }
    }

    func testWhenBuildingRequest_itMapsExportedBucketsOntoWirePayload() throws {
        // Given
        let bucket = makeExportedBucket(start: 1_000, duration: 10_000_000_000, groupCount: 1)
        let builder = makeRequestBuilder()

        // When
        let request = try builder.request(
            for: [makeEvent(from: bucket)],
            with: .mockAny(),
            execution: .init(previousResponseCode: nil, attempt: 0)
        )

        // Then
        let clientStats = try firstClientStatsPayload(in: request)
        let buckets = try XCTUnwrap(clientStats["Stats"] as? [Any?])
        XCTAssertEqual(buckets.count, 1)

        let bucketFields = try mapFields(buckets[0])
        XCTAssertEqual(bucketFields["Start"] as? Int64, 1_000)
        XCTAssertEqual(bucketFields["Duration"] as? Int64, 10_000_000_000)

        let groups = try XCTUnwrap(bucketFields["Stats"] as? [Any?])
        let group = try mapFields(groups[0])
        XCTAssertEqual(group["Service"] as? String, "service-0")
        XCTAssertEqual(group["Name"] as? String, "operation")
        XCTAssertEqual(group["Resource"] as? String, "GET /resource")
        XCTAssertEqual(group["HTTPStatusCode"] as? Int64, 200)
        XCTAssertEqual(group["Hits"] as? Int64, 10)
        XCTAssertEqual(group["Errors"] as? Int64, 2)
        XCTAssertEqual(group["IsTraceRoot"] as? Int64, Int64(Trilean.true.rawValue))
        XCTAssertEqual(group["Synthetics"] as? Bool, false)
        XCTAssertEqual(group["OkSummary"] as? Data, Data(repeating: 0x1, count: 64))

        let peerTags = try XCTUnwrap(group["PeerTags"] as? [Any?])
        XCTAssertEqual(peerTags.compactMap { $0 as? String }, ["peer.service:db"])
    }

    func testWhenBuildingRequestFromMultipleEvents_itEncodesAllBuckets() throws {
        // Given
        let events = [
            makeEvent(from: makeExportedBucket(start: 1_000)),
            makeEvent(from: makeExportedBucket(start: 2_000)),
        ]
        let builder = makeRequestBuilder()

        // When
        let request = try builder.request(
            for: events,
            with: .mockAny(),
            execution: .init(previousResponseCode: nil, attempt: 0)
        )

        // Then: each stored bucket is encoded, as its own client payload.
        let payloads = try allClientStatsPayloads(in: request)
        XCTAssertEqual(payloads.count, 2)
        XCTAssertEqual(payloads.map { ($0["Stats"] as? [Any?])?.count }, [1, 1])
    }

    func testWhenEventsAreEmpty_itThrows() {
        let builder = makeRequestBuilder()
        XCTAssertThrowsError(
            try builder.request(
                for: [],
                with: .mockAny(),
                execution: .init(previousResponseCode: nil, attempt: 0)
            )
        )
    }

    func testSequenceNumberProviderIncrementsMonotonically() {
        let provider = StatsSequenceNumberProvider()
        XCTAssertEqual(provider.next(), 1)
        XCTAssertEqual(provider.next(), 2)
        XCTAssertEqual(provider.next(), 3)
    }

    func testSequenceNumberProviderSupportsConcurrentAccess() {
        // Given
        let provider = StatsSequenceNumberProvider()
        let threadCount = 16
        let iterationsPerThread = 1_000
        let total = threadCount * iterationsPerThread

        var perThread = [[UInt64]](repeating: [], count: threadCount)
        let lock = NSLock()

        // When: every thread hammers `next()` concurrently.
        DispatchQueue.concurrentPerform(iterations: threadCount) { thread in
            var local: [UInt64] = []
            local.reserveCapacity(iterationsPerThread)
            for _ in 0..<iterationsPerThread {
                local.append(provider.next())
            }
            lock.lock()
            perThread[thread] = local
            lock.unlock()
        }

        // Then: no value is dropped or handed out twice, and the counter is left consistent.
        let all = perThread.flatMap { $0 }
        XCTAssertEqual(all.count, total)
        XCTAssertEqual(Set(all).count, total, "Concurrent next() calls must each return a unique value")
        XCTAssertEqual(all.max(), UInt64(total))
        XCTAssertEqual(provider.next(), UInt64(total) + 1)
    }

    func testEachRequestCarriesTheSequenceNumberStoredWithItsBucket() throws {
        // Given
        let builder = makeRequestBuilder()
        let execution = ExecutionContext(previousResponseCode: nil, attempt: 0)

        // When
        let first = try builder.request(
            for: [makeEvent(from: makeExportedBucket())],
            with: .mockAny(),
            execution: execution
        )
        let second = try builder.request(
            for: [makeEvent(from: makeExportedBucket())],
            with: .mockAny(),
            execution: execution
        )

        // Then
        XCTAssertEqual(try firstClientStatsPayload(in: first)["Sequence"] as? Int64, 1)
        XCTAssertEqual(try firstClientStatsPayload(in: second)["Sequence"] as? Int64, 2)
    }

    func testCustomStatsEndpointOverridesURL() {
        let customURL: URL = .mockRandom()
        let builder = makeRequestBuilder(customIntakeURL: customURL)
        XCTAssertEqual(builder.url(with: .mockAny()), customURL)
    }

    // MARK: - Request Builder - Helpers

    private func makeRequestBuilder(
        customIntakeURL: URL? = nil,
    ) -> StatsRequestBuilder {
        StatsRequestBuilder(
            customIntakeURL: customIntakeURL,
            telemetry: NOPTelemetry()
        )
    }

    /// Encodes an `ExportedBucket` the same way the feature storage does (JSON), producing a
    /// stored `Event` for the request builder to decode.
    private func makeEvent(from bucket: ExportedBucket) -> Event {
        // swiftlint:disable:next force_try
        let data = try! JSONEncoder.dd.default().encode(bucket)
        return Event(data: data)
    }

    private let splitRuntimeID = "split-runtime-id"
    /// Sequence numbers of the payload identities that `makeExportedBucket` assigns by default.
    private let bucketSequences = StatsSequenceNumberProvider()
    private let sequenceNumbers = StatsSequenceNumberProvider()

    private func split(_ bucket: ExportedBucket, toFit maxEncodedSize: Int) -> (pieces: [ExportedBucket], oversizedGroups: [ExportedGroupedStats]) {
        bucket.assigning(.init(runtimeID: splitRuntimeID, sequence: sequenceNumbers.next())).split(toFit: maxEncodedSize)
    }

    /// The number of groups in each bucket of each client payload of `request`.
    private func groupCountsPerPayload(in request: URLRequest) throws -> [[Int?]] {
        try allClientStatsPayloads(in: request).map { payload in
            try XCTUnwrap(payload["Stats"] as? [Any?]).map { try (mapFields($0)["Stats"] as? [Any?])?.count }
        }
    }

    /// An app state in which the app may be suspended: the background, or sleep on macOS.
    private func suspendableAppStateHistory() -> AppStateHistory {
        #if os(macOS)
        return .mockWith(initialState: .sleeping, date: Date())
        #else
        return .mockAppInBackground()
        #endif
    }

    /// Spins the run loop until `condition` holds or `timeout` passes.
    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }

    private func enableClientStats() throws -> (FeatureRegistrationPassthroughCoreMock, ClientStatsFeature) {
        let core = FeatureRegistrationPassthroughCoreMock()
        config.featureFlags[.clientSideStats] = true
        config.dateProvider = RelativeDateProvider(using: Date(timeIntervalSince1970: 0))
        Trace.enable(with: config, in: core)
        return (core, try XCTUnwrap(core.get(feature: ClientStatsFeature.self)))
    }

    /// 100 groups of fast and very slow successful and failed requests, whose bucket exceeds the storage limit.
    private func addWideLatencySpans(to concentrator: StatsConcentrator, endingAt end: UInt64) {
        for group in 0..<StatsConcentrator.defaultMaxGroupsPerBucket {
            for duration: UInt64 in [1_000_000, 60_000_000_000] {
                for isError in [false, true] {
                    concentrator.add(.mockWith(resource: "GET /\(group)", isError: isError, startTime: end - duration, duration: duration))
                }
            }
        }
    }

    /// Reads an estimate as a number, with a budget no test value reaches.
    private func estimatedSize(of bucket: ExportedBucket) throws -> Int {
        guard case .fits(let size) = bucket.estimatedJSONSize(budget: 1 << 40) else {
            return try XCTUnwrap(nil as Int?, "Unexpectedly over the test budget")
        }
        return size
    }

    private func estimatedSize(of group: ExportedGroupedStats) throws -> Int {
        guard case .fits(let size) = group.estimatedJSONSize(budget: 1 << 40) else {
            return try XCTUnwrap(nil as Int?, "Unexpectedly over the test budget")
        }
        return size
    }

    private func encodedSize(of bucket: ExportedBucket) throws -> Int {
        try JSONEncoder.dd.default().encode(bucket).count
    }

    private func makeGroup(resource: String) -> ExportedGroupedStats {
        ExportedGroupedStats(
            service: "service",
            name: "operation",
            resource: resource,
            httpStatusCode: 200,
            type: "web",
            spanKind: "server",
            isTraceRoot: .true,
            synthetics: false,
            hits: 1,
            errors: 0,
            duration: 100,
            topLevelHits: 1,
            okSummary: Data(repeating: 0x1, count: 64),
            errorSummary: Data(),
            peerTags: [],
            serviceSource: ""
        )
    }

    private func makeExportedBucket(
        start: UInt64 = 1_000,
        duration: UInt64 = 10_000_000_000,
        groupCount: Int = 1,
        env: String = "test-env",
        version: String = "1.0.0",
        service: String = "test-app",
        payload: ExportedBucket.PayloadIdentity? = nil
    ) -> ExportedBucket {
        let stats = (0..<groupCount).map { index in
            ExportedGroupedStats(
                service: "service-\(index)",
                name: "operation",
                resource: "GET /resource",
                httpStatusCode: 200,
                type: "web",
                spanKind: "server",
                isTraceRoot: .true,
                synthetics: false,
                hits: 10,
                errors: 2,
                duration: 5_000,
                topLevelHits: 10,
                okSummary: Data(repeating: 0x1, count: 64),
                errorSummary: Data(repeating: 0x2, count: 64),
                peerTags: ["peer.service:db"],
                serviceSource: "src"
            )
        }
        return ExportedBucket(
            start: start,
            duration: duration,
            stats: stats,
            env: env,
            version: version,
            service: service,
            payload: payload ?? .init(runtimeID: "runtime-id", sequence: bucketSequences.next())
        )
    }

    private func decodeEnvelope(in request: URLRequest) throws -> [String: Any?] {
        let body = try XCTUnwrap(request.decompressed().httpBody)
        var decoder = MsgPackTestDecoder(data: body)
        return Dictionary(uniqueKeysWithValues: try decoder.readMap())
    }

    private func firstClientStatsPayload(in request: URLRequest) throws -> [String: Any?] {
        let envelope = try decodeEnvelope(in: request)
        let clientStatsArray = try XCTUnwrap(envelope["Stats"] as? [Any?])
        return try mapFields(clientStatsArray[0])
    }

    private func allClientStatsPayloads(in request: URLRequest) throws -> [[String: Any?]] {
        let envelope = try decodeEnvelope(in: request)
        let clientStatsArray = try XCTUnwrap(envelope["Stats"] as? [Any?])
        return try clientStatsArray.map { try mapFields($0) }
    }

    private func mapFields(_ value: Any?) throws -> [String: Any?] {
        let entries = try XCTUnwrap(value as? [(String, Any?)])
        return Dictionary(uniqueKeysWithValues: entries.map { ($0.0, $0.1) })
    }
}

private final class FeatureRegistrationPassthroughCoreMock: DatadogCoreProtocol, FeatureScope {
    private let writer = FileWriterMock()
    /// The context of every write context. Tests can change it, for example to simulate a clock synchronization.
    var contextValue: DatadogContext
    private var registeredFeatures: [DatadogFeature] = []

    var remoteConfiguration: RemoteConfiguration?

    init(context: DatadogContext = .mockAny()) {
        self.contextValue = context
    }

    func register<T>(feature: T) throws where T: DatadogFeature {
        registeredFeatures.append(feature)
    }

    func feature<T>(named name: String, type: T.Type) -> T? {
        registeredFeatures.first { $0 is T } as? T
    }

    func scope<T>(for featureType: T.Type) -> FeatureScope where T: DatadogFeature {
        self
    }

    func set<Context>(context: @escaping () -> Context?) where Context: AdditionalContext { }

    func send(message: FeatureMessage, else fallback: @escaping () -> Void) { }

    func mostRecentModifiedFileAt(before: Date) throws -> Date? {
        nil
    }

    func eventWriteContext(bypassConsent: Bool, _ block: @escaping (DatadogContext, Writer) -> Void) {
        _writeContextBypassConsentValues.mutate { $0.append(bypassConsent) }
        _writeContextOnMainThread.mutate { $0.append(Thread.isMainThread) }
        if defersWriteContexts {
            pendingWriteContexts.append { [contextValue, writer] in block(contextValue, writer) }
        } else {
            block(contextValue, writer)
        }
    }

    /// When `true`, write contexts wait for `runPendingWriteContexts()`, like a context read that has
    /// not completed yet.
    var defersWriteContexts = false
    private var pendingWriteContexts: [() -> Void] = []

    func runPendingWriteContexts() {
        let pending = pendingWriteContexts
        pendingWriteContexts = []
        pending.forEach { $0() }
    }

    /// Whether each write context was opened on the main thread.
    @ReadWriteLock
    var writeContextOnMainThread: [Bool] = []

    @ReadWriteLock
    var writeContextBypassConsentValues: [Bool] = []

    func context(_ block: @escaping (DatadogContext) -> Void) {
        block(contextValue)
    }

    var dataStore: DataStore { NOPDataStore() }
    let telemetryMock = TelemetryMock()
    var telemetry: Telemetry { telemetryMock }

    func set(anonymousId: String?) { }

    var exportedBuckets: [ExportedBucket] {
        writer.events(ofType: ExportedBucket.self)
    }
}
