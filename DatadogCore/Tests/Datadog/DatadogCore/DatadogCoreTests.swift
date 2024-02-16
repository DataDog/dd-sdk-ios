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
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100),
            backgroundTasksEnabled: .mockAny()
        )

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
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100),
            backgroundTasksEnabled: .mockAny()
        )

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

    func testWhenFeatureBaggageIsUpdated_thenNewValueIsImmediatellyAvailable() throws {
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
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100),
            backgroundTasksEnabled: .mockAny()
        )
        defer { core.flushAndTearDown() }

        let feature = FeatureMock()
        try core.register(feature: feature)
        let scope = try XCTUnwrap(core.scope(for: FeatureMock.name))

        // When
        let key = "key"
        let expectation1 = self.expectation(description: "retrieve context")
        let expectation2 = self.expectation(description: "retrieve context and event writer")
        expectation1.expectedFulfillmentCount = 2
        expectation2.expectedFulfillmentCount = 2

        core.set(baggage: "baggage 1", forKey: key)
        scope.context { context in
            XCTAssertEqual(try! context.baggages[key]!.decode(type: String.self), "baggage 1")
            expectation1.fulfill()
        }
        scope.eventWriteContext { context, _ in
            XCTAssertEqual(try! context.baggages[key]!.decode(type: String.self), "baggage 1")
            expectation2.fulfill()
        }

        core.set(baggage: "baggage 2", forKey: key)
        scope.context { context in
            XCTAssertEqual(try! context.baggages[key]!.decode(type: String.self), "baggage 2")
            expectation1.fulfill()
        }
        scope.eventWriteContext { context, _ in
            XCTAssertEqual(try! context.baggages[key]!.decode(type: String.self), "baggage 2")
            expectation2.fulfill()
        }

        waitForExpectations(timeout: 1)
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
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100),
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
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100),
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

    func testWhenStoppingInstance_itDoesNotUploadEvents() throws {
        // Given
        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .granted,
            performance: .mockRandom(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            maxBatchesPerUpload: .mockAny(),
            backgroundTasksEnabled: .mockAny()
        )

        let requestBuilderSpy = FeatureRequestBuilderSpy()
        try core.register(feature: FeatureMock(requestBuilder: requestBuilderSpy))
        let scope = try XCTUnwrap(core.scope(for: FeatureMock.name))

        // When
        core.stop()

        scope.eventWriteContext { context, writer in
            writer.write(value: FeatureMock.Event(event: "should not be sent"))
        }

        // Then
        XCTAssertNil(core.scope(for: FeatureMock.name))
        core.flush()
        XCTAssertEqual(requestBuilderSpy.requestParameters.count, 0, "It should not send any request")
    }
}
