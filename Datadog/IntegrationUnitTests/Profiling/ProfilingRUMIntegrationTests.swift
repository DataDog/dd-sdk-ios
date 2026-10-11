/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

#if !os(watchOS)

@_spi(Internal) import DatadogInternal
@_spi(Internal) @testable import DatadogCore
#if os(iOS)
import UIKit
#endif
//swiftlint:disable duplicate_imports
import DatadogMachProfiler
import DatadogMachProfiler.Testing
//swiftlint:enable duplicate_imports
import TestUtilities

@testable import DatadogProfiling
@testable import DatadogRUM

final class ProfilingRUMIntegrationTests: XCTestCase {
    private enum Fixtures {
        static let deterministicSessionUUID = UUID(uuidString: "c5b3c4ab-fa4a-4de9-8199-a522131ec48a")!
        static let sampledInRUMSessionRate: SampleRate = 60
        static let unsampledRUMSessionRate: SampleRate = 50
        static let continuousSampledInRate: SampleRate = 85
        static let continuousSampledOutRate: SampleRate = 50
        static let minProfileDuration: TimeInterval = 0.1
    }

    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        dd_profiler_stop()
        dd_profiler_start()

        let launchInfo: LaunchInfo = .mockWith(processLaunchDate: Date())
        core = DatadogCoreProxy(
            context: .mockWith(
                trackingConsent: .granted,
                launchInfo: launchInfo
            )
        )
    }

    override func tearDownWithError() throws {
        try core.flushAndTearDown()
        core = nil
        dd_profiler_stop()
        dd_profiler_destroy()
        dd_delete_profiling_defaults()

        super.tearDown()
    }

    func testProfilingWithoutRUM_itDoesNotSendAProfileEvent() {
        // When
        enableProfiling()

        // Then
        // No passive output should be produced when profiling is enabled without RUM.
        assertNoProfileOutput()

        // No output should be produced even after forcing a profile flush.
        triggerProfileFlush()
        assertNoProfileOutput(timeout: timeout(after: 1.0))
        XCTAssertTrue(dd_is_profiling_enabled())
    }

    func testWhenRUMSendsTTIDMessage_itSendsAProfileEvent() throws {
        var frameInfoProvider: FrameInfoProviderMock? = nil

        // When
        enableRUM(
            sessionSampleRate: .maxSampleRate,
            sessionUUID: Fixtures.deterministicSessionUUID,
            frameInfoProviderFactory: {
                frameInfoProvider = FrameInfoProviderMock(target: $0, selector: $1)
                return frameInfoProvider!
            }
        )
        enableProfiling()
        startRUMView()

        frameInfoProvider?.triggerCallback(interval: 1)

        // Then
        waitAndAssertRUMViewEvents()
        waitAndAssertRUMAppLaunchVitalEvents(count: 1)
        triggerProfileFlush()
        try waitAndAssertProfileOutput(count: 1)

        XCTAssertTrue(dd_is_profiling_enabled())
    }

    func testWhenRUMDoesNotSendTTIDMessage_itDoesNotSendAProfileEvent() throws {
        var frameInfoProvider: FrameInfoProviderMock? = nil

        // When
        enableRUM(
            sessionSampleRate: .maxSampleRate,
            sessionUUID: Fixtures.deterministicSessionUUID,
            frameInfoProviderFactory: {
                frameInfoProvider = FrameInfoProviderMock(target: $0, selector: $1)
                return frameInfoProvider!
            }
        )
        enableProfiling()
        startRUMView()

        // Then
        waitAndAssertRUMViewEvents()
        waitAndAssertRUMAppLaunchVitalEvents(count: 0)
        try waitAndAssertProfileOutput(count: 0)

        XCTAssertTrue(dd_is_profiling_enabled())
    }

    func testContinuousProfilingWithSampledInRUMSession_itSamplesContinuousProfilingIn() throws {
        // Given
        let sessionUUID = Fixtures.deterministicSessionUUID
        let sessionSampler = DeterministicSampler(uuid: sessionUUID, samplingRate: Fixtures.sampledInRUMSessionRate)
        try XCTSkipUnless(sessionSampler.isSampled, "Precondition: UUID must be sampled at 60%")
        try XCTSkipUnless(
            sessionSampler.combined(with: Fixtures.continuousSampledInRate).isSampled,
            "Precondition: UUID must be sampled at the combined 51% rate"
        )

        // When
        enableRUM(sessionSampleRate: Fixtures.sampledInRUMSessionRate, sessionUUID: sessionUUID)
        enableProfiling(continuousSampleRate: Fixtures.continuousSampledInRate)

        startRUMView()

        // Then
        waitAndAssertRUMViewEvents()
        waitUntilContinuousProfilingSampled(true)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)
    }

    func testContinuousProfilingWithSampledOutRUMSession_itDoesNotSendAProfileEvent() throws {
        // Given
        let sessionUUID = Fixtures.deterministicSessionUUID
        let sessionSampler = DeterministicSampler(uuid: sessionUUID, samplingRate: Fixtures.sampledInRUMSessionRate)
        try XCTSkipUnless(sessionSampler.isSampled, "Precondition: UUID must be sampled at 60%")
        try XCTSkipUnless(
            !sessionSampler.combined(with: Fixtures.continuousSampledOutRate).isSampled,
            "Precondition: UUID must NOT be sampled at the combined 30% rate"
        )

        // When
        enableRUM(sessionSampleRate: Fixtures.sampledInRUMSessionRate, sessionUUID: sessionUUID)
        enableProfiling(continuousSampleRate: Fixtures.continuousSampledOutRate)

        startRUMView()

        // Then
        waitAndAssertRUMViewEvents()
        waitUntilContinuousProfilingSampled(false)
        triggerProfileFlush()
        assertNoProfileOutput(timeout: timeout(after: 0.1))
    }

    func testCustomProfilingWithSampledInRUMSession_itDoesNotWriteProfileBeforeAVitalStarts() throws {
        // Given
        let sessionUUID = Fixtures.deterministicSessionUUID
        try XCTSkipUnless(
            DeterministicSampler(uuid: sessionUUID, samplingRate: Fixtures.sampledInRUMSessionRate).isSampled,
            "Precondition: UUID must be sampled at 60%"
        )

        // When
        enableRUM(sessionSampleRate: Fixtures.sampledInRUMSessionRate, sessionUUID: sessionUUID)
        enableProfiling(applicationLaunchSampleRate: 0, continuousSampleRate: 0) // custom profiling

        startRUMView()

        // Then
        waitAndAssertRUMViewEvents()
        assertNoProfileOutput(timeout: timeout(after: 0.5))
    }

    func testCustomProfilingWithSampledOutRUMSession_itDoesNotSendAProfileEvent() throws {
        // Given
        let sessionUUID = Fixtures.deterministicSessionUUID
        let vitalName = "vital-name"
        try XCTSkipUnless(
            !DeterministicSampler(uuid: sessionUUID, samplingRate: Fixtures.unsampledRUMSessionRate).isSampled,
            "Precondition: UUID must NOT be sampled at 50%"
        )

        // When
        enableRUM(sessionSampleRate: Fixtures.unsampledRUMSessionRate, sessionUUID: sessionUUID)
        enableProfiling(applicationLaunchSampleRate: 0, continuousSampleRate: 0) // custom profiling

        startRUMView()
        startVital(name: vitalName)
        finishVital(name: vitalName)

        // Then
        triggerProfileFlush()

        let rumViews = core.waitAndReturnEvents(
            ofFeature: RUMFeature.name,
            ofType: RUMViewEvent.self,
            timeout: timeout(after: 0.1)
        )
        XCTAssertTrue(rumViews.isEmpty)
        assertNoProfileOutput(timeout: timeout(after: 0.1))
    }

    func testContinuousProfilingSamplesOut_customVitalDoesNotSendProfileEvent() throws {
        // Given
        let sessionUUID = Fixtures.deterministicSessionUUID
        let vitalName = "vital-name"
        let operationKey = "vital-key"
        let sessionSampler = DeterministicSampler(uuid: sessionUUID, samplingRate: Fixtures.sampledInRUMSessionRate)
        try XCTSkipUnless(sessionSampler.isSampled, "Precondition: UUID must be sampled at 60%")
        try XCTSkipUnless(
            !sessionSampler.combined(with: Fixtures.continuousSampledOutRate).isSampled,
            "Precondition: UUID must NOT be sampled at the combined 30% rate"
        )

        // When
        enableRUM(sessionSampleRate: Fixtures.sampledInRUMSessionRate, sessionUUID: sessionUUID)
        enableProfiling(applicationLaunchSampleRate: 0, continuousSampleRate: Fixtures.continuousSampledOutRate)

        startRUMView()

        // Then
        waitAndAssertRUMViewEvents()
        waitUntilContinuousProfilingSampled(false)

        // Stop the setup-started profiler so this verifies only the custom vital start behavior.
        dd_profiler_stop()
        waitUntilProfilerStatus(DD_PROFILER_STATUS_STOPPED, description: "profiler is stopped before the custom vital")

        startVital(name: vitalName, operationKey: operationKey)
        core.flush()
        waitUntilProfilerStatus(DD_PROFILER_STATUS_STOPPED, description: "custom vital does not start the profiler")

        finishVital(name: vitalName, operationKey: operationKey)
        core.flush()
        waitUntilProfilerStatus(DD_PROFILER_STATUS_STOPPED, description: "profiler is still stopped after the custom vital")
        assertNoProfileOutput(timeout: timeout(after: Fixtures.minProfileDuration + 0.1))
    }
}

private extension ProfilingRUMIntegrationTests {
    func enableRUM(
        sessionSampleRate: SampleRate,
        sessionUUID: UUID,
        dateProvider: DateProvider = DateProviderMock(),
        mediaTimeProvider: CACurrentMediaTimeProvider = MediaTimeProviderMock(current: 0),
        frameInfoProviderFactory: ((Any, Selector) -> FrameInfoProvider)? = nil
    ) {
        var configuration = RUM.Configuration(applicationID: "test-app-id")
        configuration.sessionSampleRate = sessionSampleRate
        configuration.uuidGenerator = RUMUUIDGeneratorMock(uuid: RUMUUID(rawValue: sessionUUID))
        configuration.dateProvider = dateProvider
        configuration.mediaTimeProvider = mediaTimeProvider
        configuration.frameInfoProviderFactory = frameInfoProviderFactory ?? {
            FrameInfoProviderMock(target: $0, selector: $1)
        }

        RUM.enable(with: configuration, in: core)
    }

    func enableProfiling(applicationLaunchSampleRate: SampleRate = .maxSampleRate, continuousSampleRate: SampleRate = .maxSampleRate) {
        var configuration = Profiling.Configuration(
            applicationLaunchSampleRate: applicationLaunchSampleRate,
            continuousSampleRate: continuousSampleRate
        )
        configuration.minProfileDuration = Fixtures.minProfileDuration

        Profiling.enable(
            with: configuration,
            in: core
        )
    }

    func startRUMView() {
        RUMMonitor.shared(in: core).startView(key: "test-view", name: "Test View")
    }

    func startVital(name: String, operationKey: String? = nil) {
        RUMMonitor.shared(in: core).startOperation(
            name: name,
            operationKey: operationKey,
            options: ProfilingOptions(sampleRate: .maxSampleRate)
        )
    }

    func finishVital(name: String, operationKey: String? = nil) {
        RUMMonitor.shared(in: core).succeedOperation(
            name: name,
            operationKey: operationKey
        )
    }

    func triggerProfileFlush() {
        let expectation = expectation(description: "read latest profiler context")
        var currentContext: DatadogContext?
        core.scope(for: ProfilerFeature.self).context {
            currentContext = $0
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1)

        guard var backgroundContext = currentContext else {
            XCTFail("Expected to read the latest profiler context before triggering a background flush")
            return
        }
        backgroundContext.applicationStateHistory.append(state: .background, at: Date())
        core.context = backgroundContext
        core.send(message: .context(backgroundContext), else: {})
        // Wait until all the pieces injected in the context and shared between modules are in place.
        core.flush()
    }

    func timeout(after interval: TimeInterval) -> DispatchTime {
        .now() + interval
    }

    func rumVitals(from attachments: ProfileAttachments) throws -> [[String: Any]] {
        let rumEventsData = try XCTUnwrap(attachments.rumEvents)
        let rumEvents = try XCTUnwrap(JSONSerialization.jsonObject(with: rumEventsData) as? [[String: Any]])
        return rumEvents.filter { $0["type"] as? String == "vital" }
    }

    func waitAndAssertRUMViewEvents(expectedViewName: String = "Test View") {
        let rumViews = core.waitAndReturnEvents(
            ofFeature: RUMFeature.name,
            ofType: RUMViewEvent.self,
            timeout: timeout(after: 1.0)
        )

        XCTAssertFalse(rumViews.isEmpty)
        XCTAssertTrue(rumViews.allSatisfy { $0.type == "view" })
        XCTAssertTrue(rumViews.contains { $0.view.name == "ApplicationLaunch" })
        XCTAssertTrue(rumViews.contains { $0.view.name == expectedViewName })

        let matchingView = rumViews.last { $0.view.name == expectedViewName }
        XCTAssertTrue(matchingView.map { $0.view.id.isEmpty == false } ?? false)
    }

    func waitAndAssertRUMAppLaunchVitalEvents(count expectedCount: Int) {
        let rumVitalEvents = core.waitAndReturnEvents(
            ofFeature: RUMFeature.name,
            ofType: RUMVitalAppLaunchEvent.self,
            timeout: timeout(after: 1.0)
        )

        XCTAssertEqual(rumVitalEvents.count, expectedCount)

        if let ttidVitalEvent = rumVitalEvents.first {
            XCTAssertEqual(ttidVitalEvent.dd.profiling?.status, .running)
            XCTAssertEqual(ttidVitalEvent.vital.appLaunchMetric, .ttid)
        }
    }

    func waitAndAssertProfileOutput(count expectedCount: Int) throws {
        let attachments = try XCTUnwrap(expectedCount > 0
            ? waitForProfileAttachments()
            : core.waitAndReturnEventsMetadata(
                ofFeature: ProfilerFeature.name,
                ofType: ProfileAttachments.self
            ))

        XCTAssertEqual(attachments.count, expectedCount)

        if let attachment = attachments.first {
            XCTAssertNotNil(attachment.pprof)
            XCTAssertNotNil(attachment.rumEvents)
        }

        let profilingEvents = try XCTUnwrap(core.waitAndReturnEvents(
            ofFeature: ProfilerFeature.name,
            ofType: ProfileEvent.self,
            timeout: expectedCount > 0 ? timeout(after: 1.0) : .distantFuture
        ))
        XCTAssertEqual(profilingEvents.count, expectedCount)

        if let profilingEvent = profilingEvents.first {
            XCTAssertEqual(profilingEvent.family, "ios")
            XCTAssertEqual(profilingEvent.runtime, "ios")
            XCTAssertEqual(profilingEvent.attachments, [
                ProfileAttachments.Constants.pprofFilename,
                ProfileAttachments.Constants.rumEventsFilename
            ])
            XCTAssertFalse(profilingEvent.tags.isEmpty)
            XCTAssertFalse(profilingEvent.additionalAttributes!.isEmpty)
        }
    }

    func assertNoProfileOutput(timeout: DispatchTime = .now() + 0.1) {
        XCTAssertTrue(core.waitAndReturnEvents(
            ofFeature: ProfilerFeature.name,
            ofType: ProfileEvent.self,
            timeout: timeout
        ).isEmpty)
        XCTAssertTrue(core.waitAndReturnEventsMetadata(
            ofFeature: ProfilerFeature.name,
            ofType: ProfileAttachments.self,
            timeout: timeout
        ).isEmpty)
    }

    func waitForProfileAttachments(timeout: TimeInterval = 1.0) -> [ProfileAttachments] {
        let deadline = Date().addingTimeInterval(timeout)

        repeat {
            core.flush()
            let attachments = core.waitAndReturnEventsMetadata(
                ofFeature: ProfilerFeature.name,
                ofType: ProfileAttachments.self,
                timeout: .now()
            )
            if attachments.isEmpty == false {
                return attachments
            }

            let remaining = deadline.timeIntervalSinceNow
            if remaining > 0 {
                wait(during: min(0.05, remaining)) {}
            }
        } while Date() < deadline

        return []
    }

    func waitUntilContinuousProfilingSampled(_ expected: Bool) {
        let expectation = expectation(description: "continuous profiling sampled is \(expected)")
        wait(until: {
            self.core.flush()
            return self.core
                .feature(named: ProfilerFeature.name, type: ProfilerFeature.self)?
                .profilingSamplerProvider
                .continuousProfilingSampled == expected
        }, andThenFulfill: expectation)
        waitForExpectations(timeout: 1.0)
    }

    func waitUntilProfilerStatus(_ expected: dd_profiler_status_t, description: String) {
        let expectation = expectation(description: description)
        wait(until: {
            dd_profiler_get_status() == expected
        }, andThenFulfill: expectation)
        waitForExpectations(timeout: 1.0)
    }
}

#endif

#if os(iOS)

private struct StoredOperationEvent: Codable {
    let data: Data
    let metadata: Data?
}

private struct CaptureDecoderControl: Codable {
    let file: String
    let raw: Data?
    let deletionAttempts: [String]
    let returnedBatch: Bool
    let fileRetained: Bool
    let rejectedInventory: [StoredOperationBatch]
    let unreadableInventory: [StoredOperationBatch]
}

private enum OperationBatchReadStatus: String, Codable {
    case notAttempted
    case rawReadFailed
    case decodeRejected
    case rawChanged
    case decoded
}

private struct StoredOperationBatch: Codable {
    let file: String
    let raw: Data?
    let readStatus: OperationBatchReadStatus
    let events: [StoredOperationEvent]

    private enum CodingKeys: String, CodingKey { case file, raw, readStatus, events }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(file, forKey: .file)
        if let raw {
            try values.encode(raw, forKey: .raw)
        } else {
            try values.encodeNil(forKey: .raw)
        }
        try values.encode(readStatus, forKey: .readStatus)
        try values.encode(events, forKey: .events)
    }
}



private final class OperationReadOnlyOrchestrator: FilesOrchestratorType {
    enum Failure: Error { case writeDuringCapture }
    let original: FilesOrchestratorType
    let directory: Directory
    private(set) var enumerationFailed = false
    private(set) var deletionAttempts: [String] = []

    init(original: FilesOrchestratorType, directory: Directory) {
        self.original = original
        self.directory = directory
    }

    var performance: StoragePerformancePreset { original.performance }
    var trackName: String { original.trackName }
    var ignoreFilesAgeWhenReading: Bool {
        get { original.ignoreFilesAgeWhenReading }
        set { original.ignoreFilesAgeWhenReading = newValue }
    }

    func getWritableFile(writeSize: UInt64) throws -> WritableFile {
        throw Failure.writeDuringCapture
    }

    // Forensic inventory includes every original file; it never purges obsolete files.
    func getReadableFiles(excludingFilesNamed excluded: Set<String>, limit: Int) -> [ReadableFile] {
        do {
            return try directory.files()
                .filter { !excluded.contains($0.name) }
                .sorted { fileCreationDateFrom(fileName: $0.name) < fileCreationDateFrom(fileName: $1.name) }
                .prefix(limit).map { $0 as ReadableFile }
        } catch {
            enumerationFailed = true
            return []
        }
    }

    func delete(readableFile: ReadableFile, deletionReason: BatchDeletedMetric.RemovalReason) {
        deletionAttempts.append(readableFile.name)
    }
}

private final class OperationSnapshotReader: Reader {
    let reader: FileReader
    let orchestrator: OperationReadOnlyOrchestrator
    private(set) var rawFiles: [String: Data] = [:]
    private(set) var filesInEnumerationOrder: [String] = []
    private(set) var filesInReadOrder: [String] = []
    private(set) var readStatuses: [String: OperationBatchReadStatus] = [:]
    private(set) var captureFailed = false

    init(storage: FeatureStorage, directory: Directory? = nil) {
        orchestrator = OperationReadOnlyOrchestrator(original: storage.authorizedFilesOrchestrator,
                                                     directory: directory ?? storage.directories.authorized)
        reader = FileReader(orchestrator: orchestrator,
                            encryption: storage.encryption, telemetry: storage.telemetry)
    }

    func readFiles(limit: Int) -> [ReadableFile] {
        let files = reader.readFiles(limit: limit)
        for file in files where !filesInEnumerationOrder.contains(file.name) {
            filesInEnumerationOrder.append(file.name)
            readStatuses[file.name] = .notAttempted
        }
        if orchestrator.enumerationFailed { captureFailed = true }
        return files
    }

    // DataReader invokes this on the original storage queue, excluding concurrent writes.
    func readBatch(from file: ReadableFile) -> Batch? {
        filesInReadOrder.append(file.name)
        readStatuses[file.name] = .rawReadFailed
        do {
            guard !file.name.contains("/") else { captureFailed = true; return nil }
            let url = orchestrator.directory.url.appendingPathComponent(file.name)
            let before = try Data(contentsOf: url)
            rawFiles[file.name] = before
            readStatuses[file.name] = .decodeRejected
            guard let batch = reader.readBatch(from: file),
                  orchestrator.deletionAttempts.isEmpty else {
                captureFailed = true
                return nil
            }
            readStatuses[file.name] = .rawChanged
            guard before == (try Data(contentsOf: url)) else {
                captureFailed = true
                return nil
            }
            readStatuses[file.name] = .decoded
            return batch
        } catch {
            captureFailed = true
            return nil
        }
    }

    func partialBatches(decoded: [StoredOperationBatch]) -> [StoredOperationBatch] {
        let inventory = filesInEnumerationOrder
            + filesInReadOrder.filter { !filesInEnumerationOrder.contains($0) }
        return inventory.map { file in
            decoded.first { $0.file == file }
                ?? StoredOperationBatch(file: file, raw: rawFiles[file],
                    readStatus: readStatuses[file] ?? .notAttempted, events: [])
        }
    }

    func markFileAsRead(_ file: ReadableFile, reason: BatchDeletedMetric.RemovalReason) {
        captureFailed = true
        XCTFail("Evidence capture must not consume stored batches")
    }
}

@MainActor
private final class OperationProfileStorageFixture {
    enum Failure: Error {
        case hostNotReady
        case storeChanged
        case unreadableBatch
        case conditionNotReached
    }

    let core: DatadogCore
    let window: UIWindow
    let scene: UIWindowScene
    let monitor: Monitor
    let resolvedOn: Bool
    private let root: UIViewController
    private let directory: URL
    private var stores: [String: (storage: FeatureStorage, upload: FeatureUpload)] = [:]
    private(set) var partialCapture: [String: [StoredOperationBatch]] = [:]
    private var nativeCleanedUp = false

    static var hostIsReady: Bool { hostedWindow() != nil }

    private static func hostedWindow() -> (UIWindowScene, UIWindow, UIViewController)? {
        guard UIApplication.shared.applicationState == .active else { return nil }
        let matches = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap { scene in
                scene.windows.filter { $0.accessibilityIdentifier == "operation-profile-test-window" }
                    .map { (scene, $0) }
            }
        guard matches.count == 1, let (scene, window) = matches.first,
              window.windowScene === scene, window.isKeyWindow,
              let root = window.rootViewController, !window.isHidden,
              window.bounds.width > 0, window.bounds.height > 0 else { return nil }
        return (scene, window, root)
    }

    init(expectedOn: Bool, automaticUIKit: Bool = false) throws {
        guard let (scene, window, root) = Self.hostedWindow() else { throw Failure.hostNotReady }
        self.scene = scene
        self.window = window
        self.root = root
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("operation-profile-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        self.directory = directory
        var configuration = Datadog.Configuration(
            clientToken: "local-operation-fixture", env: "tests", service: "operation-profile-fixture"
        )
        configuration.version = "1.0"
        configuration.systemDirectory = { Directory(url: directory) }
        configuration.httpClientFactory = { _ in HTTPClientMock(error: URLError(.notConnectedToInternet)) }
        configuration.serverDateProvider = ServerDateProviderMock()
        configuration.backgroundTasksEnabled = false
        let core: DatadogCore
        do {
            core = try DatadogCore(
                configuration: configuration, trackingConsent: .granted,
                instanceName: "operation-profile-\(UUID().uuidString)"
            )
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        self.core = core
        do {
            var rum = RUM.Configuration(applicationID: "local-operation-fixture")
            rum.sessionSampleRate = 100
            rum.featureFlags[.multiSceneTracking] = true
            if automaticUIKit {
                rum.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
                rum.uiKitActionsPredicate = DefaultUIKitRUMActionsPredicate()
                rum.longTaskThreshold = nil
            }
            guard !rum.debugSDK else { throw Failure.hostNotReady }
            try RUM.enableOrThrow(with: rum, in: core)
            let feature = try XCTUnwrap(core.get(feature: RUMFeature.self))
            monitor = feature.monitor
            let actualOn = feature.isMultiSceneTrackingEnabled
            resolvedOn = actualOn
            guard actualOn == expectedOn else { throw Failure.hostNotReady }
            if expectedOn {
                let owner = try XCTUnwrap(core.rumContextHandoffOwner)
                guard owner.isValid, feature.rumContextHandoffOwner === owner,
                      feature.operationOrigin?.isCurrent == true else { throw Failure.hostNotReady }
            } else {
                guard core.rumContextHandoffOwner == nil,
                      feature.operationOrigin == nil else { throw Failure.hostNotReady }
            }
            stores = core.stores
            for store in stores.values { store.upload.uploader.cancelSynchronously() }
            drain()
        } catch {
            for store in core.stores.values { store.upload.uploader.cancelSynchronously() }
            core.stop()
            DatadogProfiler.defaultQueue.sync { }
            dd_profiler_stop()
            dd_profiler_destroy()
            dd_delete_profiling_defaults()
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func enableProfiler() throws {
        guard core.get(feature: ProfilerFeature.self) == nil else { throw Failure.conditionNotReached }
        let configuration = Profiling.Configuration(
            applicationLaunchSampleRate: 0, continuousSampleRate: 0
        )
        guard !configuration.debugSDK,
              configuration.minProfileDuration == DatadogProfiler.Constants.minProfileDuration else {
            throw Failure.hostNotReady
        }
        do {
            try Profiling.enableOrThrow(with: configuration, in: core)
        } catch {
            stores = core.stores
            for store in stores.values { store.upload.uploader.cancelSynchronously() }
            throw error
        }
        stores = core.stores
        for store in stores.values { store.upload.uploader.cancelSynchronously() }
        _ = try XCTUnwrap(core.get(feature: ProfilerFeature.self))
        drain()
    }

    func drain() {
        core.flush()
        DatadogProfiler.defaultQueue.sync { }
        core.flush()
        DatadogProfiler.defaultQueue.sync { }
    }

    func verifyReadOnlyCaptureControl() throws -> CaptureDecoderControl {
        let pair = try XCTUnwrap(stores[RUMFeature.name])
        let url = directory.appendingPathComponent("decoder-control", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: url) }
        let controlDirectory = Directory(url: url)
        let date = Date()
        let (file, later) = try pair.storage.queue.sync {
            (try controlDirectory.createFile(named: fileNameFrom(fileCreationDate: date)),
             try controlDirectory.createFile(named: fileNameFrom(fileCreationDate: date.addingTimeInterval(1))))
        }
        let snapshot = OperationSnapshotReader(storage: pair.storage, directory: controlDirectory)
        let reader = DataReader(readWriteQueue: pair.storage.queue, fileReader: snapshot)
        XCTAssertEqual(reader.readFiles(limit: .max).map(\.name), [file.name, later.name])
        let batch = reader.readBatch(from: file)
        XCTAssertNil(batch)
        XCTAssertTrue(snapshot.captureFailed)
        XCTAssertEqual(snapshot.orchestrator.deletionAttempts, [file.name])
        XCTAssertEqual(snapshot.rawFiles[file.name], Data())
        let retained = FileManager.default.fileExists(atPath: url.appendingPathComponent(file.name).path)
        XCTAssertTrue(retained)
        let rejected = snapshot.partialBatches(decoded: [])
        XCTAssertEqual(rejected.map(\.file), [file.name, later.name])
        XCTAssertEqual(rejected.map(\.readStatus), [.decodeRejected, .notAttempted])
        XCTAssertEqual(rejected.first?.raw, Data())
        XCTAssertNil(rejected.last?.raw)

        let unreadable = OperationSnapshotReader(storage: pair.storage, directory: controlDirectory)
        let unreadableReader = DataReader(readWriteQueue: pair.storage.queue, fileReader: unreadable)
        let enumerated = unreadableReader.readFiles(limit: .max)
        let missing = try XCTUnwrap(enumerated.last)
        try pair.storage.queue.sync {
            try FileManager.default.removeItem(at: url.appendingPathComponent(missing.name))
        }
        XCTAssertNil(unreadableReader.readBatch(from: missing))
        XCTAssertTrue(unreadable.captureFailed)
        let unreadableInventory = unreadable.partialBatches(decoded: [])
        XCTAssertEqual(unreadableInventory.map(\.file), [file.name, later.name])
        XCTAssertEqual(unreadableInventory.map(\.readStatus), [.notAttempted, .rawReadFailed])
        XCTAssertNil(unreadableInventory.last?.raw)
        let encoded = try JSONEncoder().encode(unreadableInventory)
        let encodedRows = try XCTUnwrap(try JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        XCTAssertTrue(encodedRows.allSatisfy { $0["raw"] is NSNull })

        return CaptureDecoderControl(file: file.name, raw: snapshot.rawFiles[file.name],
            deletionAttempts: snapshot.orchestrator.deletionAttempts,
            returnedBatch: batch != nil, fileRetained: retained,
            rejectedInventory: rejected, unreadableInventory: unreadableInventory)
    }

    func capture() throws -> [String: [StoredOperationBatch]] {
        guard Set(stores.keys) == Set(core.stores.keys) else { throw Failure.storeChanged }
        drain()
        var result: [String: [StoredOperationBatch]] = [:]
        for (name, pair) in stores {
            guard let current = core.stores[name],
                  current.storage.authorizedFilesOrchestrator === pair.storage.authorizedFilesOrchestrator else {
                throw Failure.storeChanged
            }
            let storage = pair.storage
            let originalAge = storage.queue.sync {
                storage.authorizedFilesOrchestrator.ignoreFilesAgeWhenReading
            }
            let snapshot = OperationSnapshotReader(storage: storage)
            let reader = DataReader(readWriteQueue: storage.queue, fileReader: snapshot)
            let files = reader.readFiles(limit: .max)
            var batches: [StoredOperationBatch] = []
            defer {
                partialCapture[name] = snapshot.partialBatches(decoded: batches)
            }
            guard !snapshot.captureFailed else { throw Failure.unreadableBatch }
            for file in files {
                guard let batch = reader.readBatch(from: file), !snapshot.captureFailed,
                      let bytes = snapshot.rawFiles[file.name] else {
                    throw Failure.unreadableBatch
                }
                batches.append(.init(file: file.name, raw: bytes, readStatus: .decoded,
                    events: batch.events.map { StoredOperationEvent(data: $0.data, metadata: $0.metadata) }))
            }
            guard Set(reader.readFiles(limit: .max).map(\.name)) == Set(files.map(\.name)),
                  !snapshot.captureFailed,
                  storage.queue.sync(execute: {
                      storage.authorizedFilesOrchestrator.ignoreFilesAgeWhenReading == originalAge
                  }) else {
                throw Failure.storeChanged
            }
            result[name] = batches
        }
        return result
    }

    func context() throws -> RUMCoreContext {
        drain()
        return try XCTUnwrap(core.contextProvider.read().additionalContext(ofType: RUMCoreContext.self))
    }

    func verifyHost() throws {
        guard window.windowScene === scene, window.rootViewController === root,
              window.isKeyWindow, scene.activationState == .foregroundActive,
              UIApplication.shared.applicationState == .active, !window.isHidden,
              window.bounds.width > 0, window.bounds.height > 0 else { throw Failure.hostNotReady }
    }

    func hostInventory() -> [[String: Any]] {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.map { scene in
            ["scene": scene.session.persistentIdentifier, "state": scene.activationState.rawValue,
             "windows": scene.windows.map { window in
                 ["identity": String(describing: ObjectIdentifier(window)),
                  "fixtureOwned": window === self.window, "key": window.isKeyWindow,
                  "hidden": window.isHidden, "root": window.rootViewController.map {
                      String(describing: ObjectIdentifier($0))
                  } ?? "", "bounds": NSCoder.string(for: window.bounds)]
             }]
        }
    }

    func stop() throws {
        for store in stores.values { store.upload.uploader.cancelSynchronously() }
        drain()
        let owner = core.rumContextHandoffOwner
        core.stop()
        XCTAssertFalse(owner?.isValid ?? false)
        drain()
        destroyNativeProfiler()
        try FileManager.default.removeItem(at: directory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func destroyNativeProfiler() {
        guard !nativeCleanedUp else { return }
        DatadogProfiler.defaultQueue.sync { }
        dd_profiler_stop()
        dd_profiler_destroy()
        dd_delete_profiling_defaults()
        nativeCleanedUp = true
    }
}

@MainActor
private final class InferredOperationProfileController: UIViewController {
    let button = UIButton(type: .system)
    var onTap: (() -> Void)?

    init(inputIdentifier: String) {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        button.accessibilityIdentifier = inputIdentifier
        button.accessibilityLabel = "Preparing operation"
        button.isEnabled = false
    }

    required init?(coder: NSCoder) { return nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        button.setTitle("Run operation", for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(tapped), for: .touchUpInside)
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 240),
            button.heightAnchor.constraint(equalToConstant: 60)
        ])
    }

    @objc private func tapped() {
        button.isEnabled = false
        button.accessibilityLabel = "Input received \(button.accessibilityIdentifier ?? "")"
        onTap?()
    }
}

final class OriginalOperationProfileIntegrationTests: XCTestCase {
    @MainActor
    func testManualOperationWithSceneTracking_keepsOriginalProfileAttribution() async throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Scene ownership requires iOS 27") }
        try await exerciseManualOperation(expectedOn: true)
    }

    @MainActor
    func testRequestedSceneTrackingOnOlderSystem_keepsLegacyOperationProfile() async throws {
        if #available(iOS 27.0, *) { throw XCTSkip("This control requires the older runtime") }
        try await exerciseManualOperation(expectedOn: false)
    }

    @MainActor
    func testAutomaticUIKitOperation_keepsOriginalActionAndProfileAttribution() async throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Scene ownership requires iOS 27") }
        let supplied = try XCTUnwrap(ProcessInfo.processInfo.environment["PR10_INFERRED_INPUT_ID"])
        let inputID = try XCTUnwrap(UUID(uuidString: supplied))
        guard inputID.uuidString.lowercased() == supplied else {
            throw OperationProfileStorageFixture.Failure.hostNotReady
        }
        dd_profiler_stop()
        dd_profiler_destroy()
        dd_delete_profiling_defaults()
        try await eventually { OperationProfileStorageFixture.hostIsReady }
        let fixture = try OperationProfileStorageFixture(expectedOn: true, automaticUIKit: true)
        let root = try XCTUnwrap(fixture.window.rootViewController)
        let controller = InferredOperationProfileController(
            inputIdentifier: "operation-profile-inferred-\(supplied)"
        )
        let operationKey = UUID().uuidString
        let monitor: RUMMonitorProtocol = fixture.monitor
        var callbackCount = 0
        var capturedInput: RUMContextHandoff.CurrentValue?
        var callbackPreparationError: Error?
        func callbackInventory() -> [[String: Any]] {
            let resolved = fixture.core.rumContextHandoffOwner.flatMap {
                capturedInput?.resolvedRUMContext(for: $0)
            }
            return [["inputID": supplied, "processID": ProcessInfo.processInfo.processIdentifier,
                     "callbackCount": callbackCount,
                     "callbackPreparationFailed": callbackPreparationError != nil,
                     "hasCapturedContext": capturedInput != nil,
                     "hasPendingUserAction": capturedInput?.hasPendingUserAction ?? false,
                     "hasActionReceipt": capturedInput?.actionReceipt != nil,
                     "scene": capturedInput?.sceneIdentifier ?? "",
                     "sessionID": capturedInput?.rumContext?.sessionID ?? "",
                     "viewID": capturedInput?.rumContext?.viewID ?? "",
                     "acceptedActionID": resolved?.userActionID ?? ""]]
        }
        defer {
            attach(callbackInventory(), name: "inferred-terminal-callback-state")
            controller.button.isEnabled = false
            controller.onTap = nil
            attach(fixture.partialCapture, name: "inferred-partial-storage-before-terminal-read")
            do { attach(try fixture.capture(), name: "inferred-terminal-storage") }
            catch { XCTFail("Terminal inferred storage capture was incomplete") }
            attach(fixture.partialCapture, name: "inferred-partial-storage-after-terminal-read")
            // No test-side dismissal result substitutes for the controller's native cleanup proof.
            if root.presentedViewController === controller { root.dismiss(animated: false) }
            do { try fixture.stop() } catch { XCTFail("Owned directory cleanup failed") }
            fixture.destroyNativeProfiler()
        }
        try await settleAppLaunch(beforeProfilingIn: fixture)
        controller.onTap = {
            callbackCount += 1
            guard callbackCount == 1 else { return }
            capturedInput = fixture.monitor.currentExecutionContext
            do {
                // Construction is inside the real callback, so input waiting does not age the profile.
                try fixture.enableProfiler()
                dd_profiler_start()
                guard dd_profiler_get_status() == DD_PROFILER_STATUS_RUNNING else {
                    throw OperationProfileStorageFixture.Failure.conditionNotReached
                }
                monitor.startOperation(name: "inferred-stored-operation", operationKey: operationKey,
                    attributes: ["fixture_phase": "start"], options: ProfilingOptions(sampleRate: 100))
                monitor.succeedOperation(name: "inferred-stored-operation", operationKey: operationKey,
                    attributes: ["fixture_phase": "end"])
            } catch { callbackPreparationError = error }
        }
        root.present(controller, animated: false)
        let expectedView = try XCTUnwrap(DefaultUIKitRUMViewsPredicate().rumView(for: controller))
        try await eventually {
            guard controller.viewIfLoaded?.window === fixture.window,
                  root.presentedViewController === controller else { return false }
            return try fixture.context().viewPath == expectedView.path
        }
        let before = try fixture.context()
        _ = try XCTUnwrap(before.viewID)
        try fixture.verifyHost()
        XCTAssertEqual(before.viewName, expectedView.name)
        XCTAssertNil(fixture.monitor.currentExecutionContext)
        attach(fixture.hostInventory(), name: "inferred-before-input-window-inventory")
        attach([["inputID": supplied, "processID": ProcessInfo.processInfo.processIdentifier,
                 "buttonIdentifier": try XCTUnwrap(controller.button.accessibilityIdentifier),
                 "scene": fixture.scene.session.persistentIdentifier,
                 "viewID": try XCTUnwrap(before.viewID), "viewPath": expectedView.path,
                 "buttonBoundsInWindow": NSCoder.string(for:
                     controller.button.convert(controller.button.bounds, to: fixture.window))]],
               name: "inferred-input-ready")
        controller.button.accessibilityLabel = "Run operation \(supplied)"
        controller.button.accessibilityValue = "Ready"
        controller.button.isEnabled = true
        // The independently owned Xcode input session performs one actual tap.
        // This wait is an operational bound, not a duration or performance assertion.
        try await eventually(timeout: 120) { callbackCount > 0 }
        fixture.drain()
        controller.button.isEnabled = false
        attach(callbackInventory(), name: "inferred-original-callback")
        XCTAssertEqual(callbackCount, 1)
        if let error = callbackPreparationError { throw error }
        let captured = try XCTUnwrap(capturedInput)
        let owner = try XCTUnwrap(fixture.core.rumContextHandoffOwner)
        let receipt = try XCTUnwrap(captured.actionReceipt)
        XCTAssertTrue(receipt.owner === owner)
        XCTAssertTrue(owner.isValid)
        XCTAssertTrue(captured.hasPendingUserAction)
        XCTAssertEqual(captured.sceneIdentifier, fixture.scene.session.persistentIdentifier)
        let owned = try XCTUnwrap(captured.resolvedRUMContext(for: owner))
        XCTAssertEqual(owned.sessionID, before.sessionID)
        XCTAssertEqual(owned.viewID, before.viewID)
        let actionID = try XCTUnwrap(owned.userActionID)
        XCTAssertNil(fixture.monitor.currentExecutionContext)

        let beforeMutation = try fixture.capture()
        attach(beforeMutation, name: "inferred-before-representative-change-storage")
        guard beforeMutation[ProfilerFeature.name]?.flatMap(\.events).isEmpty == true else {
            throw OperationProfileStorageFixture.Failure.conditionNotReached
        }
        monitor.startView(key: "inferred-later-representative", name: "Inferred Later Representative")
        let later = try fixture.context()
        XCTAssertEqual(later.sessionID, owned.sessionID)
        XCTAssertNotEqual(later.viewID, owned.viewID)
        try await eventually {
            try fixture.capture()[ProfilerFeature.name]?.flatMap(\.events).isEmpty == false
        }
        let inventory = try fixture.capture()
        attach(inventory, name: "inferred-decisive-storage")
        attach(fixture.hostInventory(), name: "inferred-final-window-inventory")
        try fixture.verifyHost()
        XCTAssertTrue(controller.viewIfLoaded?.window === fixture.window)
        let rumRows = try rows(inventory[RUMFeature.name] ?? [])
        let steps = rumRows.filter {
            guard let vital = $0["vital"] as? [String: Any] else { return false }
            return vital["name"] as? String == "inferred-stored-operation"
                && vital["operation_key"] as? String == operationKey
                && vital["type"] as? String == "operation_step"
        }
        XCTAssertEqual(steps.count, 2)
        let startStep = try onlyStep(steps, type: "start")
        let endStep = try onlyStep(steps, type: "end")
        try assertStep(startStep, context: owned, phase: "start")
        try assertStep(endStep, context: owned, phase: "end")
        // The operation-step wire model has Session/view but no action field.
        for step in steps { XCTAssertNil(step["action"]) }
        let actions = rumRows.filter { $0["type"] as? String == "action" }
        let expectedAction = try XCTUnwrap(
            DefaultUIKitRUMActionsPredicate().rumAction(targetView: controller.button)
        )
        let selectedActions = actions.filter {
            (($0["action"] as? [String: Any])?["target"] as? [String: Any])?["name"] as? String
                == expectedAction.name
        }
        XCTAssertEqual(selectedActions.count, 1)
        let action = try XCTUnwrap(selectedActions.first)
        XCTAssertEqual((action["action"] as? [String: Any])?["id"] as? String, actionID)
        XCTAssertEqual((action["action"] as? [String: Any])?["type"] as? String, "tap")
        XCTAssertEqual((action["session"] as? [String: Any])?["id"] as? String, owned.sessionID)
        XCTAssertEqual((action["view"] as? [String: Any])?["id"] as? String, owned.viewID)
        XCTAssertEqual((action["view"] as? [String: Any])?["url"] as? String, owned.viewPath)
        let views = rumRows.filter { $0["type"] as? String == "view" }
        XCTAssertTrue(views.contains {
            ($0["view"] as? [String: Any])?["id"] as? String == owned.viewID
                && ($0["view"] as? [String: Any])?["url"] as? String == expectedView.path
        })

        let profileEvents = inventory[ProfilerFeature.name]?.flatMap(\.events) ?? []
        XCTAssertEqual(profileEvents.count, 1)
        let event = try XCTUnwrap(profileEvents.first)
        let profile = try object(event.data)
        XCTAssertEqual(profile[RUMCoreContext.IDs.sessionID] as? String, owned.sessionID)
        XCTAssertEqual(profile[RUMCoreContext.IDs.viewID] as? [String], [try XCTUnwrap(owned.viewID)])
        XCTAssertEqual(profile[RUMCoreContext.IDs.viewName] as? [String], [try XCTUnwrap(owned.viewName)])
        XCTAssertEqual(profile[RUMCoreContext.IDs.userActionID] as? String, actionID)
        let attachments = try JSONDecoder().decode(ProfileAttachments.self, from: XCTUnwrap(event.metadata))
        XCTAssertFalse(attachments.pprof.isEmpty)
        XCTAssertEqual(profile["attachments"] as? [String],
            [ProfileAttachments.Constants.pprofFilename, ProfileAttachments.Constants.rumEventsFilename])
        let attached = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: XCTUnwrap(attachments.rumEvents)) as? [[String: Any]])
        let startID = try XCTUnwrap((startStep["vital"] as? [String: Any])?["id"] as? String)
        let endID = try XCTUnwrap((endStep["vital"] as? [String: Any])?["id"] as? String)
        let selected = attached.filter { $0["id"] as? String == startID }
        XCTAssertEqual(selected.count, 1)
        let vital = try XCTUnwrap(selected.first)
        XCTAssertEqual(vital["name"] as? String, "inferred-stored-operation")
        XCTAssertEqual(vital["type"] as? String, "vital")
        for key in ["start_ns", "duration_ns"] {
            let value = try XCTUnwrap(vital[key] as? NSNumber).doubleValue
            XCTAssertTrue(value.isFinite)
            if key == "duration_ns" { XCTAssertGreaterThanOrEqual(value, 0) }
        }
        for key in ["session", "view", "action", "step_type"] { XCTAssertNil(vital[key]) }
        XCTAssertFalse(attached.contains { $0["id"] as? String == endID })
        XCTAssertEqual(profile[RUMCoreContext.IDs.vitalID] as? [String], [startID])
        XCTAssertEqual(profile[RUMCoreContext.IDs.vitalLabel] as? [String], ["inferred-stored-operation"])
        XCTAssertEqual(callbackCount, 1)
    }

    @MainActor
    private func settleAppLaunch(beforeProfilingIn fixture: OperationProfileStorageFixture) async throws {
        XCTAssertNil(fixture.core.get(feature: ProfilerFeature.self))
        try await eventually {
            fixture.drain()
            let inventory = try fixture.capture()
            let rumRows = try rows(inventory[RUMFeature.name] ?? [])
            return rumRows.contains {
                ($0["vital"] as? [String: Any])?["app_launch_metric"] as? String == "ttid"
            }
        }
        fixture.drain()
        attach(try fixture.capture(), name: "settled-app-launch-before-profiling")
    }

    @MainActor
    private func exerciseManualOperation(expectedOn: Bool) async throws {
        dd_profiler_stop()
        dd_profiler_destroy()
        dd_delete_profiling_defaults()
        try await eventually { OperationProfileStorageFixture.hostIsReady }
        let fixture = try OperationProfileStorageFixture(expectedOn: expectedOn)
        defer {
            attach(fixture.partialCapture, name: "partial-storage-before-terminal-read")
            do {
                let final = try fixture.capture()
                attach(final, name: "terminal-storage")
            } catch {
                XCTFail("Terminal storage capture was incomplete")
            }
            attach(fixture.partialCapture, name: "partial-storage-after-terminal-read")
            do { try fixture.stop() } catch { XCTFail("Owned directory cleanup failed") }
            fixture.destroyNativeProfiler()
        }
        if expectedOn {
            attach(try fixture.verifyReadOnlyCaptureControl(), name: "non-consuming-decoder-control")
        }
        attach(fixture.hostInventory(), name: "initial-window-inventory")
        try await settleAppLaunch(beforeProfilingIn: fixture)
        try fixture.enableProfiler()
        let monitor: RUMMonitorProtocol = fixture.monitor
        XCTAssertNil(fixture.monitor.currentExecutionContext)
        monitor.startView(key: "operation-start", name: "Operation Start")
        let start = try fixture.context()
        _ = try XCTUnwrap(start.viewID)
        dd_profiler_start()
        guard dd_profiler_get_status() == DD_PROFILER_STATUS_RUNNING else {
            throw OperationProfileStorageFixture.Failure.conditionNotReached
        }
        let operationKey = UUID().uuidString
        monitor.startOperation(name: "stored-operation", operationKey: operationKey,
            attributes: ["fixture_phase": "start"], options: ProfilingOptions(sampleRate: 100))
        fixture.drain()
        guard dd_profiler_get_status() == DD_PROFILER_STATUS_RUNNING else {
            throw OperationProfileStorageFixture.Failure.conditionNotReached
        }
        monitor.startView(key: "operation-end", name: "Operation End")
        let end = try fixture.context()
        _ = try XCTUnwrap(end.viewID)
        XCTAssertEqual(start.sessionID, end.sessionID)
        XCTAssertNotEqual(start.viewID, end.viewID)
        monitor.succeedOperation(name: "stored-operation", operationKey: operationKey,
            attributes: ["fixture_phase": "end"])
        fixture.drain()

        if expectedOn {
            guard try fixture.capture()[ProfilerFeature.name]?.flatMap(\.events).isEmpty == true else {
                throw OperationProfileStorageFixture.Failure.conditionNotReached
            }
            monitor.startView(key: "later-representative", name: "Later Representative")
            let later = try fixture.context()
            XCTAssertNotEqual(later.viewID, end.viewID)
        }

        try await eventually {
            try fixture.capture()[ProfilerFeature.name]?.flatMap(\.events).isEmpty == false
        }
        let inventory = try fixture.capture()
        attach(inventory, name: "decisive-storage")
        attach(fixture.hostInventory(), name: "final-window-inventory")
        try fixture.verifyHost()
        let rumRows = try rows(inventory[RUMFeature.name] ?? [])
        let steps = rumRows.filter {
            guard let vital = $0["vital"] as? [String: Any] else { return false }
            return vital["name"] as? String == "stored-operation"
                && vital["operation_key"] as? String == operationKey
                && vital["type"] as? String == "operation_step"
        }
        XCTAssertEqual(steps.count, 2)
        let startStep = try onlyStep(steps, type: "start")
        let endStep = try onlyStep(steps, type: "end")
        try assertStep(startStep, context: start, phase: "start")
        try assertStep(endStep, context: end, phase: "end")
        let profileEvents = inventory[ProfilerFeature.name]?.flatMap(\.events) ?? []
        XCTAssertEqual(profileEvents.count, 1)
        let event = try XCTUnwrap(profileEvents.first)
        let profile = try object(event.data)
        XCTAssertEqual(profile[RUMCoreContext.IDs.sessionID] as? String, end.sessionID)
        XCTAssertEqual(profile[RUMCoreContext.IDs.viewID] as? [String], [try XCTUnwrap(end.viewID)])
        XCTAssertEqual(profile[RUMCoreContext.IDs.viewName] as? [String], [try XCTUnwrap(end.viewName)])
        XCTAssertNil(profile[RUMCoreContext.IDs.userActionID])
        XCTAssertEqual(profile["family"] as? String, "ios")
        let tags = try XCTUnwrap(profile["tags_profiler"] as? String)
        XCTAssertTrue(tags.split(separator: ",").contains("service:operation-profile-fixture"))
        XCTAssertTrue(tags.split(separator: ",").contains("version:1.0"))
        XCTAssertTrue(tags.split(separator: ",").contains("operation:custom"))

        let metadata = try XCTUnwrap(event.metadata)
        let attachment = try JSONDecoder().decode(ProfileAttachments.self, from: metadata)
        XCTAssertFalse(attachment.pprof.isEmpty)
        XCTAssertEqual(profile["attachments"] as? [String],
            [ProfileAttachments.Constants.pprofFilename, ProfileAttachments.Constants.rumEventsFilename])
        let attached = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: XCTUnwrap(attachment.rumEvents)) as? [[String: Any]])
        let startVitalID = try XCTUnwrap((startStep["vital"] as? [String: Any])?["id"] as? String)
        let selected = attached.filter { $0["id"] as? String == startVitalID }
        XCTAssertEqual(selected.count, 1)
        let vital = try XCTUnwrap(selected.first)
        XCTAssertEqual(vital["type"] as? String, "vital")
        XCTAssertEqual(vital["name"] as? String, "stored-operation")
        let startNanoseconds = try XCTUnwrap(vital["start_ns"] as? NSNumber).doubleValue
        let durationNanoseconds = try XCTUnwrap(vital["duration_ns"] as? NSNumber).doubleValue
        XCTAssertTrue(startNanoseconds.isFinite)
        XCTAssertTrue(durationNanoseconds.isFinite)
        XCTAssertGreaterThanOrEqual(durationNanoseconds, 0)
        XCTAssertNil(vital["session"])
        XCTAssertNil(vital["view"])
        XCTAssertNil(vital["action"])
        XCTAssertNil(vital["step_type"])
        let endVitalID = try XCTUnwrap((endStep["vital"] as? [String: Any])?["id"] as? String)
        XCTAssertNotEqual(startVitalID, endVitalID)
        XCTAssertFalse(attached.contains { $0["id"] as? String == endVitalID })
        XCTAssertEqual(profile[RUMCoreContext.IDs.vitalID] as? [String], [startVitalID])
        XCTAssertEqual(profile[RUMCoreContext.IDs.vitalLabel] as? [String], ["stored-operation"])
    }

    @MainActor
    private func eventually(timeout: TimeInterval = 30, _ condition: @escaping () throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        var failure: Error?
        var completed = false
        let done = expectation(description: "Original storage or host condition becomes available")
        wait(until: {
            do {
                if try condition() { completed = true; return true }
                if Date() >= deadline {
                    failure = OperationProfileStorageFixture.Failure.conditionNotReached
                    return true
                }
                return false
            } catch {
                failure = error
                return true
            }
        }, andThenFulfill: done)
        await dd_fulfillment(for: [done], timeout: timeout + 1)
        if let failure { throw failure }
        guard completed else { throw OperationProfileStorageFixture.Failure.conditionNotReached }
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func rows(_ batches: [StoredOperationBatch]) throws -> [[String: Any]] {
        try batches.flatMap(\.events).map { try object($0.data) }
    }

    private func onlyStep(_ rows: [[String: Any]], type: String) throws -> [String: Any] {
        let selected = rows.filter { ($0["vital"] as? [String: Any])?["step_type"] as? String == type }
        XCTAssertEqual(selected.count, 1)
        return try XCTUnwrap(selected.first)
    }

    private func assertStep(_ row: [String: Any], context: RUMCoreContext, phase: String) throws {
        XCTAssertEqual((row["session"] as? [String: Any])?["id"] as? String, context.sessionID)
        XCTAssertEqual((row["view"] as? [String: Any])?["id"] as? String, context.viewID)
        XCTAssertEqual((row["view"] as? [String: Any])?["url"] as? String, context.viewPath)
        XCTAssertEqual((row["context"] as? [String: Any])?["fixture_phase"] as? String, phase)
    }

    private func attach<T: Encodable>(_ value: T, name: String) {
        do {
            let attachment = XCTAttachment(data: try JSONEncoder().encode(value),
                uniformTypeIdentifier: "public.json")
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        } catch { XCTFail("Evidence attachment encoding failed") }
    }

    private func attach(_ value: [[String: Any]], name: String) {
        do {
            let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: value),
                uniformTypeIdentifier: "public.json")
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        } catch { XCTFail("Window inventory attachment encoding failed") }
    }
}

#endif
