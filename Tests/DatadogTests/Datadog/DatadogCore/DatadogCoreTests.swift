/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import Datadog

private struct FeatureMock: DatadogFeature {
    struct Event: Encodable {
        let value: String
    }

    var name: String
    var requestBuilder: FeatureRequestBuilder = FeatureRequestBuilderMock()
    var messageReceiver: FeatureMessageReceiver = FeatureMessageReceiverMock()
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
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))

        // Given
        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .mockRandom(),
            userInfoProvider: .mockAny(),
            performance: .mockRandom(),
            httpClient: HTTPClient(session: server.getInterceptedURLSession()),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny()
        )
        defer { core.flushAndTearDown() }

        let requestBuilderSpy = FeatureRequestBuilderSpy()
        try core.register(feature: FeatureMock(name: "mock", requestBuilder: requestBuilderSpy))
        let scope = try XCTUnwrap(core.scope(for: "mock"))

        // When
        core.set(trackingConsent: .notGranted)
        scope.eventWriteContext { context, writer in
            writer.write(value: FeatureMock.Event(value: "not granted event"))
        }

        core.set(trackingConsent: .granted)
        scope.eventWriteContext { context, writer in
            writer.write(value: FeatureMock.Event(value: "granted event"))
        }

        core.set(trackingConsent: .pending)
        scope.eventWriteContext { context, writer in
            writer.write(value: FeatureMock.Event(value: "pending event"))
        }

        // Then
        core.flushAndTearDown()
        server.waitFor(requestsCompletion: 1)

        let requests = requestBuilderSpy.requestParameters
        XCTAssertEqual(requests.count, 1, "The Feature should be asked for one request")
        XCTAssertEqual(
            requests[0].events.map { $0.utf8String },
            [#"{"value":"granted event"}"#],
            "Only `.granted` events should be uploaded"
        )
    }

    func testWhenWritingEvents_itStoresThemRespectivelyToTrackingConsent() throws {
        let consent: TrackingConsent = .mockRandom()

        // Given
        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: consent,
            userInfoProvider: .mockAny(),
            performance: .mockRandom(),
            httpClient: .mockAny(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny()
        )
        defer { core.flushAndTearDown() }

        try core.register(feature: FeatureMock(name: "mock"))
        let scope = try XCTUnwrap(core.scope(for: "mock"))

        // When
        core.set(trackingConsent: .granted)
        scope.eventWriteContext { context, writer in
            writer.write(value: FeatureMock.Event(value: "granted event"))
        }

        core.set(trackingConsent: .pending)
        scope.eventWriteContext { context, writer in
            writer.write(value: FeatureMock.Event(value: "pending event"))
        }

        // Then
        core.flush()

        let directories = core.v2Features["mock"]!.storage.directories
        let authorizedEvents = try directories.authorized.files().flatMap { try $0.readTLVEvents() }.map { $0.utf8String }
        let unauthorizedEvents = try directories.unauthorized.files().flatMap { try $0.readTLVEvents() }.map { $0.utf8String }
        XCTAssertEqual(authorizedEvents, [#"{"value":"granted event"}"#])
        XCTAssertEqual(unauthorizedEvents, [#"{"value":"pending event"}"#])
    }

    func testWhenWritingEventsWithBypassingConsent_itAlwaysStoresThemInAuthorizedDirectory() throws {
        let consent: TrackingConsent = .mockRandom()

        // Given
        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: consent,
            userInfoProvider: .mockAny(),
            performance: .mockRandom(),
            httpClient: .mockAny(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny()
        )
        defer { core.flushAndTearDown() }

        try core.register(feature: FeatureMock(name: "mock"))
        let scope = try XCTUnwrap(core.scope(for: "mock"))

        // When
        core.set(trackingConsent: .notGranted)
        scope.eventWriteContext(bypassConsent: true) { context, writer in
            writer.write(value: FeatureMock.Event(value: "not granted event with bypassed consent"))
        }

        core.set(trackingConsent: .granted)
        scope.eventWriteContext(bypassConsent: true) { context, writer in
            writer.write(value: FeatureMock.Event(value: "granted event with bypassed consent"))
        }

        core.set(trackingConsent: .pending)
        scope.eventWriteContext(bypassConsent: true) { context, writer in
            writer.write(value: FeatureMock.Event(value: "pending event with bypassed consent"))
        }

        // Then
        core.flush()

        let directories = core.v2Features["mock"]!.storage.directories
        let authorizedEvents = try directories.authorized.files().flatMap { try $0.readTLVEvents() }.map { $0.utf8String }
        let unauthorizedEvents = try directories.unauthorized.files().flatMap { try $0.readTLVEvents() }.map { $0.utf8String }

        XCTAssertEqual(
            authorizedEvents,
            [
                #"{"value":"not granted event with bypassed consent"}"#,
                #"{"value":"granted event with bypassed consent"}"#,
                #"{"value":"pending event with bypassed consent"}"#,
            ]
        )
        XCTAssertEqual(unauthorizedEvents, [])
    }
}
