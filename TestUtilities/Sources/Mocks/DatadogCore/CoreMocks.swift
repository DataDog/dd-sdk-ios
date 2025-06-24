/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal
import Foundation

#if SPM_BUILD
import DatadogPrivate
#endif
@testable import DatadogCore
@testable import DatadogLogs

// MARK: - Configuration Mocks

extension Datadog.Configuration: AnyMockable {
    public static func mockAny() -> Datadog.Configuration { .mockWith() }

    public static func mockWith(
        clientToken: String = .mockAny(),
        env: String = .mockAny(),
        site: DatadogSite = .us1,
        service: String? = .mockAny(),
        bundle: Bundle = .main,
        batchSize: BatchSize = .medium,
        uploadFrequency: UploadFrequency = .average,
        proxyConfiguration: [AnyHashable: Any]? = nil,
        encryption: DataEncryption? = nil,
        serverDateProvider: ServerDateProvider? = nil
    ) -> Self {
        .init(
            clientToken: clientToken,
            env: env,
            site: site,
            service: service,
            bundle: bundle,
            batchSize: batchSize,
            uploadFrequency: uploadFrequency,
            proxyConfiguration: proxyConfiguration,
            encryption: encryption,
            serverDateProvider: serverDateProvider
        )
    }
}

typealias BatchSize = Datadog.Configuration.BatchSize

extension BatchSize: RandomMockable {
    public static func mockRandom() -> Self {
        allCases.randomElement()!
    }
}

typealias UploadFrequency = Datadog.Configuration.UploadFrequency

extension UploadFrequency: RandomMockable {
    public static func mockRandom() -> Self {
        allCases.randomElement()!
    }
}

extension Datadog.Configuration.BatchProcessingLevel: RandomMockable {
    public static func mockRandom() -> Self {
        allCases.randomElement()!
    }
}

public struct DataEncryptionMock: DataEncryption {
    let enc: (Data) throws -> Data
    let dec: (Data) throws -> Data

    public init(
        encrypt: @escaping (Data) throws -> Data = { $0 },
        decrypt: @escaping (Data) throws -> Data = { $0 }
    ) {
        enc = encrypt
        dec = decrypt
    }

    public func encrypt(data: Data) throws -> Data { try enc(data) }
    public func decrypt(data: Data) throws -> Data { try dec(data) }
}

public class ServerDateProviderMock: ServerDateProvider {
    private var update: (TimeInterval) -> Void = { _ in }

    public var offset: TimeInterval = .zero {
        didSet { update(offset) }
    }

    public init() {}

    public func synchronize(update: @escaping (TimeInterval) -> Void) {
        self.update = update
    }
}

// MARK: - PerformancePreset Mocks

public struct StoragePerformanceMock: StoragePerformancePreset {
    public var maxFileSize: UInt32
    public var maxDirectorySize: UInt32
    public var maxFileAgeForWrite: TimeInterval
    public var minFileAgeForRead: TimeInterval
    public var maxFileAgeForRead: TimeInterval
    public var maxObjectsInFile: Int
    public var maxObjectSize: UInt32

    public init(
        maxFileSize: UInt32,
        maxDirectorySize: UInt32,
        maxFileAgeForWrite: TimeInterval,
        minFileAgeForRead: TimeInterval,
        maxFileAgeForRead: TimeInterval,
        maxObjectsInFile: Int,
        maxObjectSize: UInt32
    ) {
        self.maxFileSize = maxFileSize
        self.maxDirectorySize = maxDirectorySize
        self.maxFileAgeForWrite = maxFileAgeForWrite
        self.minFileAgeForRead = minFileAgeForRead
        self.maxFileAgeForRead = maxFileAgeForRead
        self.maxObjectsInFile = maxObjectsInFile
        self.maxObjectSize = maxObjectSize
    }

    public static let noOp = StoragePerformanceMock(
        maxFileSize: 0,
        maxDirectorySize: 0,
        maxFileAgeForWrite: 0,
        minFileAgeForRead: 0,
        maxFileAgeForRead: 0,
        maxObjectsInFile: 0,
        maxObjectSize: 0
    )

    public static let readAllFiles = StoragePerformanceMock(
        maxFileSize: .max,
        maxDirectorySize: .max,
        maxFileAgeForWrite: 0,
        minFileAgeForRead: -1, // make all files eligible for read
        maxFileAgeForRead: .distantFuture, // make all files eligible for read
        maxObjectsInFile: .max,
        maxObjectSize: .max
    )

    public static let writeEachObjectToNewFileAndReadAllFiles = StoragePerformanceMock(
        maxFileSize: .max,
        maxDirectorySize: .max,
        maxFileAgeForWrite: 0, // always return new file for writing
        minFileAgeForRead: readAllFiles.minFileAgeForRead,
        maxFileAgeForRead: readAllFiles.maxFileAgeForRead,
        maxObjectsInFile: 1, // write each data to new file
        maxObjectSize: .max
    )
}

extension StoragePerformanceMock {
    public init(other: StoragePerformancePreset) {
        maxFileSize = other.maxFileSize
        maxDirectorySize = other.maxDirectorySize
        maxFileAgeForWrite = other.maxFileAgeForWrite
        minFileAgeForRead = other.minFileAgeForRead
        maxFileAgeForRead = other.maxFileAgeForRead
        maxObjectsInFile = other.maxObjectsInFile
        maxObjectSize = other.maxObjectSize
    }
}

extension PerformancePreset: AnyMockable, RandomMockable {
    public static func mockAny() -> Self {
        PerformancePreset(batchSize: .medium, uploadFrequency: .average, bundleType: .iOSApp, batchProcessingLevel: .medium)
    }

    public static func mockRandom() -> Self {
        PerformancePreset(batchSize: .mockRandom(), uploadFrequency: .mockRandom(), bundleType: .mockRandom(), batchProcessingLevel: .mockRandom())
    }

    public static func combining(storagePerformance storage: StoragePerformanceMock, uploadPerformance upload: UploadPerformanceMock) -> Self {
        PerformancePreset(
            maxFileSize: storage.maxFileSize,
            maxDirectorySize: storage.maxDirectorySize,
            maxFileAgeForWrite: storage.maxFileAgeForWrite,
            minFileAgeForRead: storage.minFileAgeForRead,
            maxFileAgeForRead: storage.maxFileAgeForRead,
            maxObjectsInFile: storage.maxObjectsInFile,
            maxObjectSize: storage.maxObjectSize,
            initialUploadDelay: upload.initialUploadDelay,
            minUploadDelay: upload.minUploadDelay,
            maxUploadDelay: upload.maxUploadDelay,
            uploadDelayChangeRate: upload.uploadDelayChangeRate,
            maxBatchesPerUpload: upload.maxBatchesPerUpload
        )
    }
}

extension FeatureStorage {
    public static func mockNoOp(directories: FeatureDirectories) -> FeatureStorage {
        return FeatureStorage(
            featureName: .mockAny(),
            queue: DispatchQueue(label: "nop"),
            directories: directories,
            authorizedFilesOrchestrator: NOPFilesOrchestrator(),
            unauthorizedFilesOrchestrator: NOPFilesOrchestrator(),
            encryption: nil,
            telemetry: NOPTelemetry()
        )
    }
}

extension FeatureUpload {
    public static func mockNoOp() -> FeatureUpload {
        return FeatureUpload(uploader: NOPDataUploadWorker())
    }
}

extension Reader {
    public func markBatchAsRead(_ batch: Batch) {
        // We can ignore `reason` in most tests (used for sending metric), so we provide this convenience variant.
        markBatchAsRead(batch, reason: .flushed)
    }
}

extension FilesOrchestratorType {
    public func delete(readableFile: ReadableFile) {
        // We can ignore `deletionReason` in most tests (used for sending metric), so we provide this convenience variant.
        delete(readableFile: readableFile, deletionReason: .flushed)
    }
}

public class NOPReader: Reader {
    public func readFiles(limit: Int) -> [ReadableFile] { [] }
    public func readBatch(from file: ReadableFile) -> Batch? { nil }
    public func markBatchAsRead(_ batch: Batch, reason: BatchDeletedMetric.RemovalReason) {}
}

internal class NOPFilesOrchestrator: FilesOrchestratorType {
    struct NOPFile: WritableFile, ReadableFile {
        var name: String = .mockAny()
        func size() throws -> UInt64 { .mockAny() }
        func append(data: Data) throws {}
        func stream() throws -> InputStream { InputStream() }
        func delete() throws { }
    }

    var performance: StoragePerformancePreset { StoragePerformanceMock.noOp }

    func getWritableFile(writeSize: UInt64) throws -> WritableFile { NOPFile() }
    func getReadableFiles(excludingFilesNamed excludedFileNames: Set<String>, limit: Int) -> [ReadableFile] { [] }
    func delete(readableFile: ReadableFile, deletionReason: BatchDeletedMetric.RemovalReason) { }

    var ignoreFilesAgeWhenReading = false
    var trackName: String = "nop"
}

extension DataFormat {
    public static func mockAny() -> DataFormat {
        return mockWith()
    }

    public static func mockWith(
        prefix: String = .mockAny(),
        suffix: String = .mockAny(),
        separator: Character = .mockAny()
    ) -> DataFormat {
        return DataFormat(
            prefix: prefix,
            suffix: suffix,
            separator: separator
        )
    }
}

class NOPDataUploadWorker: DataUploadWorkerType {
    func flushSynchronously() {}
    func cancelSynchronously() {}
}

public  class DataUploaderMock: DataUploaderType {
    let uploadStatuses: [DataUploadStatus]

    /// Notifies on each started upload.
    public var onUpload: ((DataUploadStatus?) throws -> Void)?

    /// Tracks uploaded events.
    public private(set) var uploadedEvents: [Event] = []

    public convenience init(uploadStatus: DataUploadStatus, onUpload: ((DataUploadStatus?) -> Void)? = nil) {
        self.init(uploadStatuses: [uploadStatus], onUpload: onUpload)
    }

    public init(uploadStatuses: [DataUploadStatus], onUpload: ((DataUploadStatus?) -> Void)? = nil) {
        self.uploadStatuses = uploadStatuses
        self.onUpload = onUpload
    }

    public func upload(
        events: [DatadogInternal.Event],
        context: DatadogInternal.DatadogContext,
        previous: DataUploadStatus?) throws -> DataUploadStatus {
            uploadedEvents += events
            try onUpload?(previous)
            let attempt: UInt
            if let previous = previous {
                attempt = previous.attempt + 1
            } else {
                attempt = 0
            }
            return uploadStatuses[Int(attempt)]
    }
}

extension DataUploadStatus: RandomMockable {
    public static func mockRandom() -> DataUploadStatus {
        return DataUploadStatus(
            needsRetry: .random(),
            responseCode: .mockRandom(),
            userDebugDescription: .mockRandom(),
            error: nil,
            attempt: .mockRandom()
        )
    }

    public static func mockWith(
        needsRetry: Bool = .mockAny(),
        responseCode: Int = .mockAny(),
        userDebugDescription: String = .mockAny(),
        error: DataUploadError? = nil,
        attempt: UInt = 0
    ) -> DataUploadStatus {
        return DataUploadStatus(
            needsRetry: needsRetry,
            responseCode: responseCode,
            userDebugDescription: userDebugDescription,
            error: error,
            attempt: attempt
        )
    }
}

extension BatteryStatus.State {
    public static func mockRandom(within cases: [BatteryStatus.State] = [.unknown, .unplugged, .charging, .full]) -> BatteryStatus.State {
        return cases.randomElement()!
    }
}

class MockHostsSanitizer: HostsSanitizing {
    private(set) var sanitizations = [(hosts: Set<String>, warningMessage: String)]()
    func sanitized(hosts: Set<String>, warningMessage: String) -> Set<String> {
        sanitizations.append((hosts: hosts, warningMessage: warningMessage))
        return hosts
    }

    func sanitized(
        hostsWithTracingHeaderTypes: [String: Set<TracingHeaderType>],
        warningMessage: String
    ) -> [String: Set<TracingHeaderType>] {
        sanitizations.append((hosts: Set(hostsWithTracingHeaderTypes.keys), warningMessage: warningMessage))
        return hostsWithTracingHeaderTypes
    }
}

public class AppLaunchHandlerMock: AppLaunchHandling {
    /// Indicates whether the application was prewarmed by the system.
    public let isActivePrewarm: Bool
    /// The timestamp when the application process was launched.
    public let launchDate: Date
    /// The time interval between the app process launch and the `UIApplication.didBecomeActiveNotification`.
    /// Returns `nil` if the notification has not yet been received.
    public var timeToDidBecomeActive: TimeInterval?
    /// Stores the callback to be invoked when the application becomes active.
    private var didBecomeActiveCallback: UIApplicationDidBecomeActiveCallback?

    public init(
        launchDate: Date,
        timeToDidBecomeActive: TimeInterval?,
        isActivePrewarm: Bool
    ) {
        self.launchDate = launchDate
        self.timeToDidBecomeActive = timeToDidBecomeActive
        self.isActivePrewarm = isActivePrewarm
    }

    public func setApplicationDidBecomeActiveCallback(_ callback: @escaping UIApplicationDidBecomeActiveCallback) {
        guard timeToDidBecomeActive == nil else {
            // The app is already active; do nothing as per the interface contract.
            return
        }
        didBecomeActiveCallback = callback
    }

    /// Simulates the application becoming active.
    ///
    /// This method can be called in tests to simulate the `UIApplication.didBecomeActiveNotification`.
    /// If a callback has been set before activation, it will be invoked.
    ///
    /// - Parameter timeInterval: The time interval from launch to activation.
    public func simulateDidBecomeActive(timeInterval: TimeInterval) {
        guard timeToDidBecomeActive == nil else {
            return
        }

        timeToDidBecomeActive = timeInterval
        didBecomeActiveCallback?(timeInterval)
    }
}
