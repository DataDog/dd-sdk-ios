/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogCore

private struct FeatureMock: DatadogRemoteFeature {
    static let name: String = "mock"

    struct Event: Encodable {
        let event: String
    }

    var requestBuilder: FeatureRequestBuilder = FeatureRequestBuilderMock()
    var messageReceiver: FeatureMessageReceiver = FeatureMessageReceiverMock()
    var performanceOverride: PerformancePresetOverride? = nil
}

class DatadogCoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        temporaryCoreDirectory.create()
    }

    override func tearDown() {
        temporaryCoreDirectory.delete()
        super.tearDown()
    }

    func testWhenWritingEventsWithDifferentTrackingConsent_itOnlyUploadsAuthorizedEvents() throws {
        // Given
        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .mockRandom(),
            performance: .mockRandom(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            backgroundTasksEnabled: .mockAny()
        )
        defer { core.flushAndTearDown() }

        let requestBuilderSpy = FeatureRequestBuilderSpy()
        try core.register(feature: FeatureMock(requestBuilder: requestBuilderSpy))
        let scope = try XCTUnwrap(core.scope(for: FeatureMock.name))

        // When
        core.set(trackingConsent: .notGranted)
        scope.eventWriteContext { context, writer in
            writer.write(value: FeatureMock.Event(event: "not granted"))
        }

        core.set(trackingConsent: .granted)
        scope.eventWriteContext { context, writer in
            writer.write(value: FeatureMock.Event(event: "granted"))
        }

        core.set(trackingConsent: .pending)
        scope.eventWriteContext { context, writer in
            writer.write(value: FeatureMock.Event(event: "pending"))
        }

        // Then
        core.flushAndTearDown()

        let uploadedEvents = requestBuilderSpy.requestParameters
            .flatMap { $0.events }
            .map { $0.data.utf8String }

        XCTAssertEqual(uploadedEvents, [#"{"event":"granted"}"#], "Only `.granted` events should be uploaded")
        XCTAssertEqual(requestBuilderSpy.requestParameters.count, 1, "It should send only one request")
    }

    func testWhenWritingEventsWithBypassingConsent_itUploadsAllEvents() throws {
        // Given
        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .mockRandom(),
            performance: .mockRandom(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            backgroundTasksEnabled: .mockAny()
        )
        defer { core.flushAndTearDown() }

        let requestBuilderSpy = FeatureRequestBuilderSpy()
        try core.register(feature: FeatureMock(requestBuilder: requestBuilderSpy))
        let scope = try XCTUnwrap(core.scope(for: FeatureMock.name))

        // When
        core.set(trackingConsent: .notGranted)
        scope.eventWriteContext(bypassConsent: true) { context, writer in
            writer.write(value: FeatureMock.Event(event: "not granted"))
        }

        core.set(trackingConsent: .granted)
        scope.eventWriteContext(bypassConsent: true) { context, writer in
            writer.write(value: FeatureMock.Event(event: "granted"))
        }

        core.set(trackingConsent: .pending)
        scope.eventWriteContext(bypassConsent: true) { context, writer in
            writer.write(value: FeatureMock.Event(event: "pending"))
        }

        // Then
        core.flushAndTearDown()

        let uploadedEvents = requestBuilderSpy.requestParameters
            .flatMap { $0.events }
            .map { $0.data.utf8String }

        XCTAssertEqual(
            uploadedEvents,
            [
                #"{"event":"not granted"}"#,
                #"{"event":"granted"}"#,
                #"{"event":"pending"}"#,
            ],
            "It should upload all events"
        )
        XCTAssertEqual(requestBuilderSpy.requestParameters.count, 1, "It should send only one request")
    }

    func testWhenWritingEventsWithForcingNewBatch_itUploadsEachEventInSeparateRequest() throws {
        // Given
        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: RelativeDateProvider(advancingBySeconds: 0.01),
            initialConsent: .granted,
            performance: .mockRandom(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            backgroundTasksEnabled: .mockAny()
        )
        defer { core.flushAndTearDown() }

        let requestBuilderSpy = FeatureRequestBuilderSpy()
        try core.register(feature: FeatureMock(requestBuilder: requestBuilderSpy))
        let scope = try XCTUnwrap(core.scope(for: FeatureMock.name))

        // When
        scope.eventWriteContext(forceNewBatch: true) { context, writer in
            writer.write(value: FeatureMock.Event(event: "1"))
        }

        scope.eventWriteContext(forceNewBatch: true) { context, writer in
            writer.write(value: FeatureMock.Event(event: "2"))
        }

        scope.eventWriteContext(forceNewBatch: true) { context, writer in
            writer.write(value: FeatureMock.Event(event: "3"))
        }

        // Then
        core.flushAndTearDown()

        let uploadedEvents = requestBuilderSpy.requestParameters
            .flatMap { $0.events }
            .map { $0.data.utf8String }

        XCTAssertEqual(
            uploadedEvents,
            [
                #"{"event":"1"}"#,
                #"{"event":"2"}"#,
                #"{"event":"3"}"#,
            ],
            "It should upload all events"
        )
        XCTAssertEqual(requestBuilderSpy.requestParameters.count, 3, "It should send 3 requests")
    }

    func testWhenPerformancePresetOverrideIsProvided_itOverridesPresets() throws {
        // Given
        let core1 = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: RelativeDateProvider(advancingBySeconds: 0.01),
            initialConsent: .granted,
            performance: .mockRandom(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            backgroundTasksEnabled: .mockAny()
        )
        let core2 = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: RelativeDateProvider(advancingBySeconds: 0.01),
            initialConsent: .granted,
            performance: .mockRandom(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            backgroundTasksEnabled: .mockAny()
        )
        defer {
            core1.flushAndTearDown()
            core2.flushAndTearDown()
        }

        // When
        try core1.register(
            feature: FeatureMock(performanceOverride: nil)
        )
        try core2.register(
            feature: FeatureMock(
                performanceOverride: PerformancePresetOverride(
                    maxFileSize: 123,
                    maxObjectSize: 456,
                    meanFileAge: 100,
                    uploadDelay: nil
                )
            )
        )

        // Then
        let storage1 = core1.stores.values.first?.storage
        XCTAssertEqual(storage1?.authorizedFilesOrchestrator.performance.maxObjectSize, 512.KB.asUInt64())
        XCTAssertEqual(storage1?.authorizedFilesOrchestrator.performance.maxFileSize, 4.MB.asUInt64())

        let storage2 = core2.stores.values.first?.storage
        XCTAssertEqual(storage2?.authorizedFilesOrchestrator.performance.maxObjectSize, 456)
        XCTAssertEqual(storage2?.authorizedFilesOrchestrator.performance.maxFileSize, 123)
        XCTAssertEqual(storage2?.authorizedFilesOrchestrator.performance.maxFileAgeForWrite, 95)
        XCTAssertEqual(storage2?.authorizedFilesOrchestrator.performance.minFileAgeForRead, 105)
    }

    func testItUpdatesTheFeatureBaggage() throws {
        // Given
        let contextProvider: DatadogContextProvider = .mockAny()
        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .mockRandom(),
            performance: .mockRandom(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: contextProvider,
            applicationVersion: .mockAny(),
            backgroundTasksEnabled: .mockAny()
        )
        defer { core.flushAndTearDown() }
        try core.register(feature: FeatureMock())

        // When
        core.update(feature: FeatureMock.name) {
            return ["foo": "bar"]
        }
        core.update(feature: FeatureMock.name) {
            return ["bizz": "bazz"]
        }

        // Then
        let context = contextProvider.read()
        XCTAssertEqual(context.featuresAttributes[FeatureMock.name]?.foo, "bar")
        XCTAssertEqual(context.featuresAttributes[FeatureMock.name]?.bizz, "bazz")
    }
}
