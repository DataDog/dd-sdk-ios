/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@_spi(Internal)
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

private final class PendingHTTPClientMock: HTTPClient {
    private typealias Completion = (Result<(HTTPURLResponse, Data?), any Error>) -> Void

    private let queue = DispatchQueue(label: "com.datadoghq.PendingHTTPClientMock-\(UUID().uuidString)")
    private var requests: [URLRequest] = []
    private var completions: [Completion] = []

    func send(
        request: URLRequest,
        delegate: URLSessionTaskDelegate?,
        completion: @escaping (Result<(HTTPURLResponse, Data?), any Error>) -> Void
    ) {
        queue.sync {
            requests.append(request)
            completions.append(completion)
        }
    }

    func requestsSent() -> [URLRequest] {
        queue.sync {
            requests
        }
    }
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

    func testGivenRemoteConfigurationProvider_whenReadingRemoteConfiguration_itReturnsCachedValue() throws {
        // Given
        let configurationData = try JSONEncoder().encode(RemoteConfiguration(rum: .init(applicationId: "cache-application-id")))
        let cache = RemoteConfigurationCache(etag: nil, metadata: nil, configurationData: configurationData)
        try JSONEncoder().encode(cache).write(
            to: temporaryCoreDirectory.coreDirectory.url.appendingPathComponent("test-id.json"),
            options: .atomic
        )
        let remoteConfigurationProvider = RemoteConfigurationProvider(
            id: "test-id",
            site: .us1,
            directory: temporaryCoreDirectory.coreDirectory,
            httpClient: PendingHTTPClientMock(),
            notificationCenterProvider: NotificationCenterProvider.makeTestProvider()
        )
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
            backgroundTasksEnabled: .mockAny(),
            remoteConfigurationProvider: remoteConfigurationProvider
        )

        // Then
        XCTAssertEqual(core.remoteConfiguration?.rum?.applicationId, "cache-application-id")
    }

    func testGivenNoRemoteConfigurationProvider_whenReadingRemoteConfiguration_itReturnsNil() throws {
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

        // Then
        XCTAssertNil(core.remoteConfiguration)
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
        scope.eventWriteContext { context, writer in
            XCTAssertEqual(context.trackingConsent, .pending)
            writer.write(value: FeatureMock.Event(event: "pending"))
        }

        core.set(trackingConsent: .granted)
        scope.eventWriteContext { context, writer in
            XCTAssertEqual(context.trackingConsent, .granted)
            writer.write(value: FeatureMock.Event(event: "granted"))
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
        scope.eventWriteContext { context, _ in
            XCTAssertEqual(context.additionalContext(ofType: ContextMock.self)?.value, "value 1")
            expectation2.fulfill()
        }

        core.set(context: ContextMock(value: "value 1"))
        scope.context { context in
            XCTAssertEqual(context.additionalContext(ofType: ContextMock.self)?.value, "value 1")
            expectation1.fulfill()
        }
        scope.eventWriteContext { context, _ in
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
        XCTAssertEqual(storage1?.authorizedFilesOrchestrator.performance.maxObjectSize, 1.MB.asUInt32())
        XCTAssertEqual(storage1?.authorizedFilesOrchestrator.performance.maxFileSize, 5.MB.asUInt32())

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

        scope.eventWriteContext { context, writer in
            writer.write(value: FeatureMock.Event(event: "should not be sent"))
        }

        // Then
        XCTAssertNil(core.get(feature: FeatureMock.self))
        core.flush()
        XCTAssertEqual(requestBuilderSpy.requestParameters.count, 0, "It should not send any request")
    }

    func testWhenStoppingInstance_itDisconnectsMessageBus() throws {
        // Given
        let messageReceiver = FeatureMessageReceiverMock()
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
        try core.register(feature: FeatureMock(messageReceiver: messageReceiver))
        core.send(message: .payload("sent before stop"))
        core.bus.flush()

        let busQueueBlocked = DispatchSemaphore(value: 0)
        core.bus.queue.async { busQueueBlocked.wait() } // keep the next message queued until `stop()` returns
        core.send(message: .payload("queued before stop"))

        // When
        core.stop()
        busQueueBlocked.signal()
        core.send(message: .payload("sent after stop"))
        core.bus.flush()

        // Then
        let deliveredPayloads = messageReceiver.messages.compactMap { message -> String? in
            guard case .payload(let payload as String) = message else {
                return nil
            }
            return payload
        }
        XCTAssertEqual(deliveredPayloads, ["sent before stop"], "Messages queued or sent after `stop()` must not be delivered")
    }

    func testWhenStoppingInstance_itDoesNotDeliverPendingInitialContext() throws {
        // Given
        let messageReceiver = FeatureMessageReceiverMock()
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
        let busQueueBlocked = DispatchSemaphore(value: 0)
        core.bus.queue.async { busQueueBlocked.wait() } // keep the initial context delivery pending until `stop()` returns
        try core.register(feature: FeatureMock(messageReceiver: messageReceiver))
        core.contextProvider.flush() // the initial context is read and its delivery is queued

        // When
        core.stop()
        busQueueBlocked.signal()
        core.bus.flush()

        // Then
        let deliveredContexts = messageReceiver.messages.filter { message in
            guard case .context = message else {
                return false
            }
            return true
        }
        XCTAssertTrue(deliveredContexts.isEmpty, "The initial context must not be delivered after `stop()`")
    }

    func testWhenStoppingInstance_itStopsRemoteConfigurationProvider() throws {
        // Given
        let notificationCenterProvider = NotificationCenterProvider.makeTestProvider()
        let httpClient = PendingHTTPClientMock()
        weak var weakProvider: RemoteConfigurationProvider?
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
            backgroundTasksEnabled: .mockAny(),
            remoteConfigurationProvider: {
                let provider = RemoteConfigurationProvider(
                    id: "test-id",
                    site: .us1,
                    directory: temporaryCoreDirectory.coreDirectory,
                    httpClient: httpClient,
                    notificationCenterProvider: notificationCenterProvider
                )
                weakProvider = provider
                return provider
            }()
        )

        XCTAssertEqual(httpClient.requestsSent().count, 1)
        #if os(macOS)
        notificationCenterProvider.workspaceCenter.post(name: WorkspaceNotifications.didWake, object: nil)
        #else
        notificationCenterProvider.applicationCenter.post(name: ApplicationNotifications.willEnterForeground, object: nil)
        #endif
        XCTAssertEqual(httpClient.requestsSent().count, 2)

        // When
        core.stop()

        // Then
        XCTAssertNotNil(core.remoteConfigurationProvider)
        XCTAssertNotNil(weakProvider)
        #if os(macOS)
        notificationCenterProvider.workspaceCenter.post(name: WorkspaceNotifications.didWake, object: nil)
        #else
        notificationCenterProvider.applicationCenter.post(name: ApplicationNotifications.willEnterForeground, object: nil)
        #endif
        XCTAssertEqual(httpClient.requestsSent().count, 2)
    }

    func testItAppendsUserDataIfAnonymousIdentifierExists() {
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
        let userBefore = core.userInfoPublisher.current
        XCTAssertEqual(userBefore.anonymousId, "anonymous-id")
        XCTAssertNil(userBefore.id)
        XCTAssertNil(userBefore.name)
        XCTAssertNil(userBefore.email)

        core.setUserInfo(id: "user-id", name: "user-name", email: "user-email")

        let userAfter = core.userInfoPublisher.current
        XCTAssertEqual(userAfter.anonymousId, "anonymous-id")
        XCTAssertEqual(userAfter.id, "user-id")
        XCTAssertEqual(userAfter.name, "user-name")
        XCTAssertEqual(userAfter.email, "user-email")
    }

    func testItAppendsAnonymousIdentifierIfUserExists() {
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

        let userBefore = core.userInfoPublisher.current
        XCTAssertNil(userBefore.anonymousId)
        XCTAssertEqual(userBefore.id, "user-id")
        XCTAssertEqual(userBefore.name, "user-name")
        XCTAssertEqual(userBefore.email, "user-email")

        core.set(anonymousId: "anonymous-id")

        let userAfter = core.userInfoPublisher.current
        XCTAssertEqual(userAfter.anonymousId, "anonymous-id")
        XCTAssertEqual(userAfter.id, "user-id")
        XCTAssertEqual(userAfter.name, "user-name")
        XCTAssertEqual(userAfter.email, "user-email")
    }

    func testItAppendsAccountDataAndUpdatesIt() {
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
        let accountBefore = core.accountInfoPublisher.current
        XCTAssertNil(accountBefore)

        core.setAccountInfo(id: "account-id", name: "account-name")
        let accountAfterInitialSet = core.accountInfoPublisher.current
        XCTAssertNotNil(accountAfterInitialSet)
        XCTAssertEqual(accountAfterInitialSet?.id, "account-id")
        XCTAssertEqual(accountAfterInitialSet?.name, "account-name")

        core.setAccountInfo(id: "account-id-2", name: "account-name-2")
        let accountAfterUpdate = core.accountInfoPublisher.current
        XCTAssertNotNil(accountAfterUpdate)
        XCTAssertEqual(accountAfterUpdate?.id, "account-id-2")
        XCTAssertEqual(accountAfterUpdate?.name, "account-name-2")
    }

    func testItUpdatesAccountExtraInfoWhileKeepingOriginalAccountInfo() {
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
        let accountBefore = core.accountInfoPublisher.current
        XCTAssertNil(accountBefore)

        core.setAccountInfo(id: "account-id", name: "account-name")
        let accountAfterInitialSet = core.accountInfoPublisher.current
        XCTAssertNotNil(accountAfterInitialSet)
        XCTAssertEqual(accountAfterInitialSet?.id, "account-id")
        XCTAssertEqual(accountAfterInitialSet?.name, "account-name")

        core.addAccountExtraInfo(["test": "test"])
        let accountAfterAddExtraInfo = core.accountInfoPublisher.current
        XCTAssertNotNil(accountAfterAddExtraInfo)
        XCTAssertEqual(accountAfterAddExtraInfo?.id, "account-id")
        XCTAssertEqual(accountAfterAddExtraInfo?.name, "account-name")
    }

    func testItClearsAccountInfo() {
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
        let accountBefore = core.accountInfoPublisher.current
        XCTAssertNil(accountBefore)

        core.setAccountInfo(id: "account-id", name: "account-name")
        let accountAfterInitialSet = core.accountInfoPublisher.current
        XCTAssertNotNil(accountAfterInitialSet)
        XCTAssertEqual(accountAfterInitialSet?.id, "account-id")
        XCTAssertEqual(accountAfterInitialSet?.name, "account-name")

        core.clearAccountInfo()
        let accountAfterUpdate = core.accountInfoPublisher.current
        XCTAssertNil(accountAfterUpdate)
    }

    func testItClearUserInfo() {
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
        let userBefore = core.userInfoPublisher.current
        XCTAssertNil(userBefore.id)
        XCTAssertNil(userBefore.name)
        XCTAssertNil(userBefore.email)

        core.setUserInfo(id: "user-id", name: "user-name", email: "user-email")
        let userAfterInitialSet = core.userInfoPublisher.current
        XCTAssertEqual(userAfterInitialSet.id, "user-id")
        XCTAssertEqual(userAfterInitialSet.name, "user-name")
        XCTAssertEqual(userAfterInitialSet.email, "user-email")

        core.clearUserInfo()
        let userAfterUpdate = core.userInfoPublisher.current
        XCTAssertNil(userAfterUpdate.id)
        XCTAssertNil(userAfterUpdate.name)
        XCTAssertNil(userAfterUpdate.email)
    }

    func testFlushAndUpload_uploadsAuthorizedEvents() throws {
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
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100),
            backgroundTasksEnabled: .mockAny()
        )
        defer { core.stop() }

        let requestBuilderSpy = FeatureRequestBuilderSpy()
        try core.register(feature: FeatureMock(requestBuilder: requestBuilderSpy))
        let scope = core.scope(for: FeatureMock.self)

        scope.eventWriteContext { _, writer in
            writer.write(value: FeatureMock.Event(event: "test"))
        }

        // When
        core.flushAndUpload()

        // Then
        let uploadedEvents = requestBuilderSpy.requestParameters
            .flatMap { $0.events }
            .map { $0.data.utf8String }

        XCTAssertEqual(uploadedEvents, [#"{"event":"test"}"#])
    }

    func testFlushAndUpload_sdkRemainsOperationalAfterFlush() throws {
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
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100),
            backgroundTasksEnabled: .mockAny()
        )
        defer { core.stop() }

        let requestBuilderSpy = FeatureRequestBuilderSpy()
        try core.register(feature: FeatureMock(requestBuilder: requestBuilderSpy))
        let scope = core.scope(for: FeatureMock.self)

        scope.eventWriteContext { _, writer in
            writer.write(value: FeatureMock.Event(event: "first"))
        }
        core.flushAndUpload()

        // When - write more events after flush
        scope.eventWriteContext { _, writer in
            writer.write(value: FeatureMock.Event(event: "second"))
        }
        core.flushAndUpload()

        // Then
        let uploadedEvents = requestBuilderSpy.requestParameters
            .flatMap { $0.events }
            .map { $0.data.utf8String }

        XCTAssertTrue(uploadedEvents.contains(#"{"event":"first"}"#))
        XCTAssertTrue(uploadedEvents.contains(#"{"event":"second"}"#))
    }

    func testFlushAndTearDown_whenMessageIsPostedDuringFinalUpload_itDeliversItBeforeReturning() throws {
        // Given
        let requestBuilderSpy = FeatureRequestBuilderSpy()
        let deliveredPayloads = ReadWriteLock<[String]>(wrappedValue: [])
        let messageReceiver = FeatureMessageReceiverMock { message in
            guard case .payload(let payload as String) = message else {
                return
            }
            deliveredPayloads.mutate { $0.append(payload) }
        }
        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .granted,
            performance: .combining(storagePerformance: .readAllFiles, uploadPerformance: .noOp),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockWith(context: .mockWith(networkConnectionInfo: .mockWith(reachability: .no))),
            applicationVersion: .mockAny(),
            maxBatchesPerUpload: 1,
            backgroundTasksEnabled: false
        )
        try core.register(feature: FeatureMock(requestBuilder: requestBuilderSpy, messageReceiver: messageReceiver))
        core.scope(for: FeatureMock.self).eventWriteContext { _, writer in
            writer.write(value: FeatureMock.Event(event: "test"))
        }
        // Only the final forced upload builds requests: scheduled uploads are blocked by the unreachable network.
        // The bus queue is parked so the message is still queued when the final upload completes. The timeout only
        // bounds how long `flushAndTearDown()` waits on it: the message must be delivered whenever the queue resumes.
        let busQueueParked = DispatchSemaphore(value: 0)
        requestBuilderSpy.onRequest = { [weak core] _, _ in
            core?.bus.queue.async { _ = busQueueParked.wait(timeout: .now() + 1) }
            core?.send(message: .payload("posted during final upload"))
        }

        // When
        core.flushAndTearDown()

        // Then
        XCTAssertEqual(deliveredPayloads.wrappedValue, ["posted during final upload"])
    }

    func testFlushAndTearDown_whenMessageIsPostedDuringFinalUpload_itCompletesTheWriteItTriggersBeforeReturning() throws {
        // Given
        let requestBuilderSpy = FeatureRequestBuilderSpy()
        let isWriteCompleted = ReadWriteLock(wrappedValue: false)
        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .granted,
            performance: .combining(storagePerformance: .readAllFiles, uploadPerformance: .noOp),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockWith(context: .mockWith(networkConnectionInfo: .mockWith(reachability: .no))),
            applicationVersion: .mockAny(),
            maxBatchesPerUpload: 1,
            backgroundTasksEnabled: false
        )
        // Like RUM's telemetry receiver, write an event when the message is delivered.
        let contextQueueParked = DispatchSemaphore(value: 0)
        let messageReceiver = FeatureMessageReceiverMock { [weak core] message in
            guard case .payload(let payload as String) = message, payload == "posted during final upload", let core = core else {
                return
            }
            // Park the context queue so the write is still pending when the delivery completes. The timeout only
            // bounds how long `flushAndTearDown()` waits on it: the write must complete whenever the queue resumes.
            core.contextProvider.queue.async { _ = contextQueueParked.wait(timeout: .now() + 1) }
            core.scope(for: FeatureMock.self).eventWriteContext { _, writer in
                writer.write(value: FeatureMock.Event(event: "written during teardown")) {
                    isWriteCompleted.mutate { $0 = true }
                }
            }
        }
        try core.register(feature: FeatureMock(requestBuilder: requestBuilderSpy, messageReceiver: messageReceiver))
        core.scope(for: FeatureMock.self).eventWriteContext { _, writer in
            writer.write(value: FeatureMock.Event(event: "test"))
        }
        // Only the final forced upload builds requests: scheduled uploads are blocked by the unreachable network.
        requestBuilderSpy.onRequest = { [weak core] _, _ in
            core?.send(message: .payload("posted during final upload"))
        }

        // When
        core.flushAndTearDown()

        // Then
        XCTAssertTrue(isWriteCompleted.wrappedValue, "A write triggered during teardown must complete before `flushAndTearDown()` returns")
    }

    func testDatadogFlush_uploadsEventsAndReturnsSynchronously() throws {
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
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100),
            backgroundTasksEnabled: .mockAny()
        )
        let requestBuilderSpy = FeatureRequestBuilderSpy()
        try core.register(feature: FeatureMock(requestBuilder: requestBuilderSpy))
        let scope = core.scope(for: FeatureMock.self)

        CoreRegistry.register(default: core)
        defer { Datadog.internalFlushAndDeinitialize() }

        scope.eventWriteContext { _, writer in
            writer.write(value: FeatureMock.Event(event: "test"))
        }

        // When
        Datadog.flush()

        // Then - if flush is synchronous, events are uploaded before this assertion
        let uploadedEvents = requestBuilderSpy.requestParameters
            .flatMap { $0.events }
            .map { $0.data.utf8String }

        XCTAssertEqual(uploadedEvents, [#"{"event":"test"}"#])
    }

    func testItClearsAnonymousIdentifier() {
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

        let userAfter = core.userInfoPublisher.current
        XCTAssertNil(userAfter.anonymousId)
        XCTAssertEqual(userAfter.id, "user-id")
        XCTAssertEqual(userAfter.name, "user-name")
        XCTAssertEqual(userAfter.email, "user-email")
    }
}
