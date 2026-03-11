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
        let scope = core.scope(for: FeatureMock.self)

        // When
        core.set(trackingConsent: .notGranted)
        Task {
            guard let (_, writer) = await scope.eventWriteContext() else { return }
            await writer.write(value: FeatureMock.Event(event: "not granted"))
        }

        core.set(trackingConsent: .granted)
        Task {
            guard let (_, writer) = await scope.eventWriteContext() else { return }
            await writer.write(value: FeatureMock.Event(event: "granted"))
        }

        core.set(trackingConsent: .pending)
        Task {
            guard let (_, writer) = await scope.eventWriteContext() else { return }
            await writer.write(value: FeatureMock.Event(event: "pending"))
        }

        // Then
        core.flushAndTearDown()

        let uploadedEvents = requestBuilderSpy.requestParameters
            .flatMap { $0.events }
            .map { $0.data.utf8String }

        XCTAssertEqual(uploadedEvents, [#"{"event":"granted"}"#], "Only `.granted` events should be uploaded")
        XCTAssertEqual(requestBuilderSpy.requestParameters.count, 1, "It should send only one request")
    }

    func testWhenWritingEventsWithPendingConsentThenGranted_itUploadsAllEvents() throws {
        // Given
        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .mockRandom(),
            performance: .combining(
                storagePerformance: StoragePerformanceMock.readAllFiles,
                uploadPerformance: UploadPerformanceMock.veryQuick
            ),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            maxBatchesPerUpload: 1,
            backgroundTasksEnabled: .mockAny()
        )
        defer { core.flushAndTearDown() }

        let send2RequestsExpectation = expectation(description: "send 2 requests")
        send2RequestsExpectation.expectedFulfillmentCount = 2

        let requestBuilderSpy = FeatureRequestBuilderSpy()
        requestBuilderSpy.onRequest = { _, _ in send2RequestsExpectation.fulfill() }

        try core.register(feature: FeatureMock(requestBuilder: requestBuilderSpy))

        // When
        let scope = core.scope(for: FeatureMock.self)
        core.set(trackingConsent: .pending)
        Task {
            guard let (context, writer) = await scope.eventWriteContext() else { return }
            XCTAssertEqual(context.trackingConsent, .pending)
            await writer.write(value: FeatureMock.Event(event: "pending"))
        }

        core.set(trackingConsent: .granted)
        Task {
            guard let (context, writer) = await scope.eventWriteContext() else { return }
            XCTAssertEqual(context.trackingConsent, .granted)
            await writer.write(value: FeatureMock.Event(event: "granted"))
        }

        // Then
        waitForExpectations(timeout: 2)

        let uploadedEvents = requestBuilderSpy.requestParameters
            .flatMap { $0.events }
            .map { $0.data.utf8String }

        XCTAssertEqual(
            uploadedEvents,
            [
                #"{"event":"pending"}"#,
                #"{"event":"granted"}"#
            ],
            "It should upload all events"
        )
        XCTAssertEqual(requestBuilderSpy.requestParameters.count, 2, "It should send 2 requests")
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
        let scope = core.scope(for: FeatureMock.self)

        // When
        core.set(trackingConsent: .notGranted)
        Task {
            guard let (_, writer) = await scope.eventWriteContext(bypassConsent: true) else { return }
            await writer.write(value: FeatureMock.Event(event: "not granted"))
        }

        core.set(trackingConsent: .granted)
        Task {
            guard let (_, writer) = await scope.eventWriteContext(bypassConsent: true) else { return }
            await writer.write(value: FeatureMock.Event(event: "granted"))
        }

        core.set(trackingConsent: .pending)
        Task {
            guard let (_, writer) = await scope.eventWriteContext(bypassConsent: true) else { return }
            await writer.write(value: FeatureMock.Event(event: "pending"))
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

    func testWhenFeatureAdditionalContextIsUpdated_thenNewValueIsImmediatellyAvailable() throws {
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
        let scope = core.scope(for: FeatureMock.self)

        // When
        struct ContextMock: AdditionalContext {
            static let key = "key"
            let value: String
        }
        let expectation1 = self.expectation(description: "retrieve context")
        let expectation2 = self.expectation(description: "retrieve context and event writer")
        expectation1.expectedFulfillmentCount = 2
        expectation2.expectedFulfillmentCount = 2

        core.set(context: ContextMock(value: "value 1"))
        scope.context { context in
            XCTAssertEqual(context.additionalContext(ofType: ContextMock.self)?.value, "value 1")
            expectation1.fulfill()
        }
        Task {
            guard let (context, _) = await scope.eventWriteContext() else { return }
            XCTAssertEqual(context.additionalContext(ofType: ContextMock.self)?.value, "value 1")
            expectation2.fulfill()
        }

        core.set(context: ContextMock(value: "value 1"))
        scope.context { context in
            XCTAssertEqual(context.additionalContext(ofType: ContextMock.self)?.value, "value 1")
            expectation1.fulfill()
        }
        Task {
            guard let (context, _) = await scope.eventWriteContext() else { return }
            XCTAssertEqual(context.additionalContext(ofType: ContextMock.self)?.value, "value 1")
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
        XCTAssertEqual(storage1?.authorizedFilesOrchestrator.performance.maxObjectSize, 512.KB.asUInt32())
        XCTAssertEqual(storage1?.authorizedFilesOrchestrator.performance.maxFileSize, 4.MB.asUInt32())

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
        let scope = core.scope(for: FeatureMock.self)

        // When
        core.stop()

        Task {
            guard let (_, writer) = await scope.eventWriteContext() else { return }
            await writer.write(value: FeatureMock.Event(event: "should not be sent"))
        }

        // Then
        XCTAssertNil(core.get(feature: FeatureMock.self))
        core.flush()
        XCTAssertEqual(requestBuilderSpy.requestParameters.count, 0, "It should not send any request")
    }

    func testItAppendsUserDataIfAnonymousIdentifierExists() async {
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
        core.set(anonymousId: "anonymous-id")
        let userBefore = await core.contextProvider.read().userInfo!
        XCTAssertEqual(userBefore.anonymousId, "anonymous-id")
        XCTAssertNil(userBefore.id)
        XCTAssertNil(userBefore.name)
        XCTAssertNil(userBefore.email)

        core.setUserInfo(id: "user-id", name: "user-name", email: "user-email")

        let userAfter = await core.contextProvider.read().userInfo!
        XCTAssertEqual(userAfter.anonymousId, "anonymous-id")
        XCTAssertEqual(userAfter.id, "user-id")
        XCTAssertEqual(userAfter.name, "user-name")
        XCTAssertEqual(userAfter.email, "user-email")
    }

    func testItAppendsAnonymousIdentifierIfUserExists() async {
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
        core.setUserInfo(id: "user-id", name: "user-name", email: "user-email")

        let userBefore = await core.contextProvider.read().userInfo!
        XCTAssertNil(userBefore.anonymousId)
        XCTAssertEqual(userBefore.id, "user-id")
        XCTAssertEqual(userBefore.name, "user-name")
        XCTAssertEqual(userBefore.email, "user-email")

        core.set(anonymousId: "anonymous-id")

        let userAfter = await core.contextProvider.read().userInfo!
        XCTAssertEqual(userAfter.anonymousId, "anonymous-id")
        XCTAssertEqual(userAfter.id, "user-id")
        XCTAssertEqual(userAfter.name, "user-name")
        XCTAssertEqual(userAfter.email, "user-email")
    }

    func testItAppendsAccountDataAndUpdatesIt() async {
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
        let accountBefore = await core.contextProvider.read().accountInfo
        XCTAssertNil(accountBefore)

        core.setAccountInfo(id: "account-id", name: "account-name")
        let accountAfterInitialSet = await core.contextProvider.read().accountInfo
        XCTAssertNotNil(accountAfterInitialSet)
        XCTAssertEqual(accountAfterInitialSet?.id, "account-id")
        XCTAssertEqual(accountAfterInitialSet?.name, "account-name")

        core.setAccountInfo(id: "account-id-2", name: "account-name-2")
        let accountAfterUpdate = await core.contextProvider.read().accountInfo
        XCTAssertNotNil(accountAfterUpdate)
        XCTAssertEqual(accountAfterUpdate?.id, "account-id-2")
        XCTAssertEqual(accountAfterUpdate?.name, "account-name-2")
    }

    func testItUpdatesAccountExtraInfoWhileKeepingOriginalAccountInfo() async {
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
        let accountBefore = await core.contextProvider.read().accountInfo
        XCTAssertNil(accountBefore)

        core.setAccountInfo(id: "account-id", name: "account-name")
        let accountAfterInitialSet = await core.contextProvider.read().accountInfo
        XCTAssertNotNil(accountAfterInitialSet)
        XCTAssertEqual(accountAfterInitialSet?.id, "account-id")
        XCTAssertEqual(accountAfterInitialSet?.name, "account-name")

        core.addAccountExtraInfo(["test": "test"])
        let accountAfterAddExtraInfo = await core.contextProvider.read().accountInfo
        XCTAssertNotNil(accountAfterAddExtraInfo)
        XCTAssertEqual(accountAfterAddExtraInfo?.id, "account-id")
        XCTAssertEqual(accountAfterAddExtraInfo?.name, "account-name")
    }

    func testItClearsAccountInfo() async {
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
        let accountBefore = await core.contextProvider.read().accountInfo
        XCTAssertNil(accountBefore)

        core.setAccountInfo(id: "account-id", name: "account-name")
        let accountAfterInitialSet = await core.contextProvider.read().accountInfo
        XCTAssertNotNil(accountAfterInitialSet)
        XCTAssertEqual(accountAfterInitialSet?.id, "account-id")
        XCTAssertEqual(accountAfterInitialSet?.name, "account-name")

        core.clearAccountInfo()
        let accountAfterUpdate = await core.contextProvider.read().accountInfo
        XCTAssertNil(accountAfterUpdate)
    }

    func testItClearUserInfo() async {
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
        let userBefore = await core.contextProvider.read().userInfo!
        XCTAssertNil(userBefore.id)
        XCTAssertNil(userBefore.name)
        XCTAssertNil(userBefore.email)

        core.setUserInfo(id: "user-id", name: "user-name", email: "user-email")
        let userAfterInitialSet = await core.contextProvider.read().userInfo!
        XCTAssertEqual(userAfterInitialSet.id, "user-id")
        XCTAssertEqual(userAfterInitialSet.name, "user-name")
        XCTAssertEqual(userAfterInitialSet.email, "user-email")

        core.clearUserInfo()
        let userAfterUpdate = await core.contextProvider.read().userInfo!
        XCTAssertNil(userAfterUpdate.id)
        XCTAssertNil(userAfterUpdate.name)
        XCTAssertNil(userAfterUpdate.email)
    }

    func testItClearsAnonymousIdentifier() async {
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
        core.set(anonymousId: "anonymous-id")
        core.setUserInfo(id: "user-id", name: "user-name", email: "user-email")
        core.set(anonymousId: nil)

        let userAfter = await core.contextProvider.read().userInfo!
        XCTAssertNil(userAfter.anonymousId)
        XCTAssertEqual(userAfter.id, "user-id")
        XCTAssertEqual(userAfter.name, "user-name")
        XCTAssertEqual(userAfter.email, "user-email")
    }
}
