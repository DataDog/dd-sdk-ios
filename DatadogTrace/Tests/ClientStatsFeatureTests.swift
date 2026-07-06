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
        config.statsComputationEnabled = false

        // When
        Trace.enable(with: config, in: core)

        // Then
        XCTAssertNil(core.get(feature: ClientStatsFeature.self))
    }

    func testWhenStatsComputationEnabled_thenClientStatsFeatureIsRegistered() {
        // Given
        config.statsComputationEnabled = true

        // When
        Trace.enable(with: config, in: core)

        // Then
        XCTAssertNotNil(core.get(feature: ClientStatsFeature.self))
    }

    func testWhenStatsComputationEnabled_thenTraceFeatureIsAlsoRegistered() {
        // Given
        config.statsComputationEnabled = true

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
        XCTAssertFalse(defaultConfig.statsComputationEnabled)
    }

    // MARK: - Consent

    func testWhenContextMessageRevokesConsent_itStopsConcentratorFromExporting() {
        // Given: a concentrator with buffered data and the feature's consent receiver
        let concentrator = StatsConcentrator(now: 0, initialConsent: .granted)
        let receiver = TraceClientStatsConsentReceiver(concentrator: concentrator)
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
        let receiver = TraceClientStatsConsentReceiver(concentrator: concentrator)

        XCTAssertFalse(receiver.receive(message: .payload("irrelevant"), from: core))
    }

    // MARK: - Request Builder

    func testWhenStatsComputationEnabled_thenRequestBuilderUsesStatsEndpoint() throws {
        // Given
        config.statsComputationEnabled = true

        // When
        Trace.enable(with: config, in: core)

        // Then
        let stats = try XCTUnwrap(core.get(feature: ClientStatsFeature.self))
        XCTAssertTrue(stats.requestBuilder is StatsRequestBuilder)
    }

    func testWhenStatsComputationEnabledWithCustomStatsEndpoint_thenRequestBuilderUsesCustomURL() throws {
        // Given
        let customURL: URL = .mockRandom()
        config.statsComputationEnabled = true
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
        config.statsComputationEnabled = true
        config.customEndpoint = spansURL

        // When
        Trace.enable(with: config, in: core)

        // Then
        let stats = try XCTUnwrap(core.get(feature: ClientStatsFeature.self))
        let requestBuilder = try XCTUnwrap(stats.requestBuilder as? StatsRequestBuilder)
        XCTAssertNil(requestBuilder.customIntakeURL)
    }

    // MARK: - Feature Name

    func testFeatureName() {
        XCTAssertEqual(ClientStatsFeature.name, "tracing-client-stats")
    }

    func testWhenStatsComputationEnabledWithCustomDateProvider_thenStatsFeatureUsesItForFlushTiming() throws {
        let core = FeatureRegistrationPassthroughCoreMock()
        let dateProvider = RelativeDateProvider(using: Date(timeIntervalSince1970: 0))

        config.statsComputationEnabled = true
        config.dateProvider = dateProvider

        Trace.enable(with: config, in: core)

        let stats = try XCTUnwrap(core.get(feature: ClientStatsFeature.self))
        stats.concentrator.add(SpanSnapshot.mockWith(
            startTime: 20_000_000_000,
            duration: 5_000_000_000,
            isTopLevel: true
        ))

        stats.flushStats(force: false)

        XCTAssertTrue(core.exportedBuckets.isEmpty)
    }

    // MARK: - Flush Telemetry

    func testWhenFlushProducesBuckets_itSendsFlushMetric() throws {
        // Given
        let core = FeatureRegistrationPassthroughCoreMock()
        let dateProvider = RelativeDateProvider(using: Date(timeIntervalSince1970: 0))
        config.statsComputationEnabled = true
        config.dateProvider = dateProvider

        Trace.enable(with: config, in: core)
        let stats = try XCTUnwrap(core.get(feature: ClientStatsFeature.self))

        // Two spans landing in the same aggregation group, one of them an error.
        stats.concentrator.add(.mockWith(startTime: 0, duration: 1_000_000_000, isTopLevel: true))
        stats.concentrator.add(.mockWith(isError: true, startTime: 0, duration: 2_000_000_000, isTopLevel: true))

        // When: advancing past the buffer window makes the bucket flushable.
        dateProvider.advance(bySeconds: 60)
        stats.flushStats(force: false)

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
        config.statsComputationEnabled = true
        config.dateProvider = dateProvider

        Trace.enable(with: config, in: core)
        let stats = try XCTUnwrap(core.get(feature: ClientStatsFeature.self))
        stats.concentrator.add(.mockWith(startTime: 0, duration: 1_000_000_000, isTopLevel: true))

        // When: a forced flush (teardown) exports the still-recent bucket.
        stats.flushStats(force: true)

        // Then
        let metric = try XCTUnwrap(core.telemetryMock.messages.firstMetric(named: TraceClientStatsMetric.name))
        XCTAssertEqual(metric.attributes[TraceClientStatsMetric.forcedKey] as? Bool, true)
        XCTAssertEqual(metric.attributes[TraceClientStatsMetric.spansCountKey] as? UInt64, 1)
    }

    func testWhenFlushProducesNoBuckets_itDoesNotSendFlushMetric() throws {
        // Given
        let core = FeatureRegistrationPassthroughCoreMock()
        config.statsComputationEnabled = true
        config.dateProvider = RelativeDateProvider(using: Date(timeIntervalSince1970: 0))

        Trace.enable(with: config, in: core)
        let stats = try XCTUnwrap(core.get(feature: ClientStatsFeature.self))

        // When: nothing was aggregated, so the flush is empty.
        stats.flushStats(force: true)

        // Then
        XCTAssertNil(core.telemetryMock.messages.firstMetric(named: TraceClientStatsMetric.name))
    }

    func testWhenConsentIsNotGranted_itDoesNotSendFlushMetric() throws {
        // Given
        let core = FeatureRegistrationPassthroughCoreMock()
        let dateProvider = RelativeDateProvider(using: Date(timeIntervalSince1970: 0))
        config.statsComputationEnabled = true
        config.dateProvider = dateProvider

        Trace.enable(with: config, in: core)
        let stats = try XCTUnwrap(core.get(feature: ClientStatsFeature.self))

        // When: consent is revoked, aggregation and flush are gated off.
        stats.concentrator.updateConsent(.notGranted)
        stats.concentrator.add(.mockWith(startTime: 0, duration: 1_000_000_000, isTopLevel: true))
        dateProvider.advance(bySeconds: 60)
        stats.flushStats(force: true)

        // Then: no buckets are exported, so no metric is emitted.
        XCTAssertNil(core.telemetryMock.messages.firstMetric(named: TraceClientStatsMetric.name))
    }

    // MARK: - Request Builder - Encoding

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
        let builder = makeRequestBuilder(runtimeID: "runtime-id")

        // When
        let request = try builder.request(
            for: [makeEvent(from: makeExportedBucket())],
            with: context,
            execution: .init(previousResponseCode: nil, attempt: 0)
        )

        // Then
        let clientStats = try firstClientStatsPayload(in: request)
        XCTAssertEqual(clientStats["Hostname"] as? String, "")
        XCTAssertEqual(clientStats["Env"] as? String, "staging")
        XCTAssertEqual(clientStats["Version"] as? String, "1.2.3")
        XCTAssertEqual(clientStats["Service"] as? String, "ios-app")
        XCTAssertEqual(clientStats["TracerVersion"] as? String, "2.0.0")
        XCTAssertEqual(clientStats["Lang"] as? String, "ios")
        XCTAssertEqual(clientStats["RuntimeID"] as? String, "runtime-id")
        XCTAssertEqual(clientStats["Sequence"] as? Int64, 1)
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

        // Then: all buckets land under a single ClientStatsPayload (one tracer).
        let envelope = try decodeEnvelope(in: request)
        let clientStatsArray = try XCTUnwrap(envelope["Stats"] as? [Any?])
        XCTAssertEqual(clientStatsArray.count, 1)

        let clientStats = try mapFields(clientStatsArray[0])
        let buckets = try XCTUnwrap(clientStats["Stats"] as? [Any?])
        XCTAssertEqual(buckets.count, 2)
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

    func testSequenceNumberIncrementsAcrossRequests() throws {
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
        runtimeID: String = "runtime-id",
        sequenceNumberProvider: StatsSequenceNumberProvider = StatsSequenceNumberProvider()
    ) -> StatsRequestBuilder {
        StatsRequestBuilder(
            customIntakeURL: customIntakeURL,
            telemetry: NOPTelemetry(),
            runtimeID: runtimeID,
            sequenceNumberProvider: sequenceNumberProvider
        )
    }

    /// Encodes an `ExportedBucket` the same way the feature storage does (JSON), producing a
    /// stored `Event` for the request builder to decode.
    private func makeEvent(from bucket: ExportedBucket) -> Event {
        // swiftlint:disable:next force_try
        let data = try! JSONEncoder.dd.default().encode(bucket)
        return Event(data: data)
    }

    private func makeExportedBucket(
        start: UInt64 = 1_000,
        duration: UInt64 = 10_000_000_000,
        groupCount: Int = 1
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
        return ExportedBucket(start: start, duration: duration, stats: stats)
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

    private func mapFields(_ value: Any?) throws -> [String: Any?] {
        let entries = try XCTUnwrap(value as? [(String, Any?)])
        return Dictionary(uniqueKeysWithValues: entries.map { ($0.0, $0.1) })
    }
}

private final class FeatureRegistrationPassthroughCoreMock: DatadogCoreProtocol, FeatureScope {
    private let writer = FileWriterMock()
    private let contextValue: DatadogContext
    private var registeredFeatures: [DatadogFeature] = []

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
        block(contextValue, writer)
    }

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
