/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogLogs
@testable import DatadogCore

// MARK: - Configuration Mocks

extension Datadog.Configuration {
    static func mockAny() -> Datadog.Configuration { .mockWith() }

    static func mockWith(
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

extension BatchSize: CaseIterable {
    public static var allCases: [Self] { [.small, .medium, .large] }

    static func mockRandom() -> Self {
        allCases.randomElement()!
    }
}

typealias UploadFrequency = Datadog.Configuration.UploadFrequency

extension UploadFrequency: CaseIterable {
    public static var allCases: [Self] { [.frequent, .average, .rare] }

    static func mockRandom() -> Self {
        allCases.randomElement()!
    }
}

extension BundleType: CaseIterable {
    public static var allCases: [Self] { [.iOSApp, iOSAppExtension] }
}

struct DataEncryptionMock: DataEncryption {
    let enc: (Data) throws -> Data
    let dec: (Data) throws -> Data

    init(
        encrypt: @escaping (Data) throws -> Data = { $0 },
        decrypt: @escaping (Data) throws -> Data = { $0 }
    ) {
        enc = encrypt
        dec = decrypt
    }

    func encrypt(data: Data) throws -> Data { try enc(data) }
    func decrypt(data: Data) throws -> Data { try dec(data) }
}

class ServerDateProviderMock: ServerDateProvider {
    private var update: (TimeInterval) -> Void = { _ in }

    var offset: TimeInterval = .zero {
        didSet { update(offset) }
    }

    func synchronize(update: @escaping (TimeInterval) -> Void) {
        self.update = update
    }
}

// MARK: - PerformancePreset Mocks

struct StoragePerformanceMock: StoragePerformancePreset {
    var maxFileSize: UInt64
    var maxDirectorySize: UInt64
    var maxFileAgeForWrite: TimeInterval
    var minFileAgeForRead: TimeInterval
    var maxFileAgeForRead: TimeInterval
    var maxObjectsInFile: Int
    var maxObjectSize: UInt64

    static let noOp = StoragePerformanceMock(
        maxFileSize: 0,
        maxDirectorySize: 0,
        maxFileAgeForWrite: 0,
        minFileAgeForRead: 0,
        maxFileAgeForRead: 0,
        maxObjectsInFile: 0,
        maxObjectSize: 0
    )

    static let readAllFiles = StoragePerformanceMock(
        maxFileSize: .max,
        maxDirectorySize: .max,
        maxFileAgeForWrite: 0,
        minFileAgeForRead: -1, // make all files eligible for read
        maxFileAgeForRead: .distantFuture, // make all files eligible for read
        maxObjectsInFile: .max,
        maxObjectSize: .max
    )

    static let writeEachObjectToNewFileAndReadAllFiles = StoragePerformanceMock(
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
    init(other: StoragePerformancePreset) {
        maxFileSize = other.maxFileSize
        maxDirectorySize = other.maxDirectorySize
        maxFileAgeForWrite = other.maxFileAgeForWrite
        minFileAgeForRead = other.minFileAgeForRead
        maxFileAgeForRead = other.maxFileAgeForRead
        maxObjectsInFile = other.maxObjectsInFile
        maxObjectSize = other.maxObjectSize
    }
}

struct UploadPerformanceMock: UploadPerformancePreset {
    var initialUploadDelay: TimeInterval
    var minUploadDelay: TimeInterval
    var maxUploadDelay: TimeInterval
    var uploadDelayChangeRate: Double

    static let noOp = UploadPerformanceMock(
        initialUploadDelay: .distantFuture,
        minUploadDelay: .distantFuture,
        maxUploadDelay: .distantFuture,
        uploadDelayChangeRate: 0
    )

    /// Optimized for performing very fast uploads in unit tests.
    static let veryQuick = UploadPerformanceMock(
        initialUploadDelay: 0.05,
        minUploadDelay: 0.05,
        maxUploadDelay: 0.05,
        uploadDelayChangeRate: 0
    )

    /// Optimized for performing very fast first upload and then changing to unrealistically long intervals.
    static let veryQuickInitialUpload = UploadPerformanceMock(
        initialUploadDelay: 0.05,
        minUploadDelay: 60,
        maxUploadDelay: 60,
        uploadDelayChangeRate: 60 / 0.05
    )
}

extension UploadPerformanceMock {
    init(other: UploadPerformancePreset) {
        initialUploadDelay = other.initialUploadDelay
        minUploadDelay = other.minUploadDelay
        maxUploadDelay = other.maxUploadDelay
        uploadDelayChangeRate = other.uploadDelayChangeRate
    }
}

extension PerformancePreset: AnyMockable, RandomMockable {
    public static func mockAny() -> Self {
        PerformancePreset(batchSize: .medium, uploadFrequency: .average, bundleType: .iOSApp)
    }

    public static func mockRandom() -> Self {
        PerformancePreset(batchSize: .mockRandom(), uploadFrequency: .mockRandom(), bundleType: .mockRandom())
    }

    static func combining(storagePerformance storage: StoragePerformanceMock, uploadPerformance upload: UploadPerformanceMock) -> Self {
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
            uploadDelayChangeRate: upload.uploadDelayChangeRate
        )
    }
}

extension FeatureStorage {
    static func mockNoOp() -> FeatureStorage {
        return FeatureStorage(
            featureName: .mockAny(),
            queue: DispatchQueue(label: "nop"),
            directories: temporaryFeatureDirectories,
            authorizedFilesOrchestrator: NOPFilesOrchestrator(),
            unauthorizedFilesOrchestrator: NOPFilesOrchestrator(),
            encryption: nil,
            telemetry: NOPTelemetry()
        )
    }
}

extension FeatureUpload {
    static func mockNoOp() -> FeatureUpload {
        return FeatureUpload(uploader: NOPDataUploadWorker())
    }
}

extension Reader {
    func markBatchAsRead(_ batch: Batch) {
        // We can ignore `reason` in most tests (used for sending metric), so we provide this convenience variant.
        markBatchAsRead(batch, reason: .flushed)
    }
}

extension FilesOrchestratorType {
    func delete(readableFile: ReadableFile) {
        // We can ignore `deletionReason` in most tests (used for sending metric), so we provide this convenience variant.
        delete(readableFile: readableFile, deletionReason: .flushed)
    }
}

class NOPReader: Reader {
    func readFiles(limit: Int) -> [ReadableFile] { [] }
    func readBatch(from file: ReadableFile) -> Batch? { nil }
    func markBatchAsRead(_ batch: Batch, reason: BatchDeletedMetric.RemovalReason) {}
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
    static func mockAny() -> DataFormat {
        return mockWith()
    }

    static func mockWith(
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

internal class DataUploaderMock: DataUploaderType {
    let uploadStatus: DataUploadStatus

    /// Notifies on each started upload.
    var onUpload: (() throws -> Void)?

    /// Tracks uploaded events.
    private(set) var uploadedEvents: [Event] = []

    init(uploadStatus: DataUploadStatus, onUpload: (() -> Void)? = nil) {
        self.uploadStatus = uploadStatus
        self.onUpload = onUpload
    }

    func upload(events: [Event], context: DatadogContext) throws -> DataUploadStatus {
        uploadedEvents += events
        try onUpload?()
        return uploadStatus
    }
}

extension DataUploadStatus: RandomMockable {
    public static func mockRandom() -> DataUploadStatus {
        return DataUploadStatus(
            needsRetry: .random(),
            responseCode: .mockRandom(),
            userDebugDescription: .mockRandom(),
            error: nil
        )
    }

    static func mockWith(
        needsRetry: Bool = .mockAny(),
        responseCode: Int = .mockAny(),
        userDebugDescription: String = .mockAny(),
        error: DataUploadError? = nil
    ) -> DataUploadStatus {
        return DataUploadStatus(
            needsRetry: needsRetry,
            responseCode: responseCode,
            userDebugDescription: userDebugDescription,
            error: error
        )
    }
}

extension BatteryStatus.State {
    static func mockRandom(within cases: [BatteryStatus.State] = [.unknown, .unplugged, .charging, .full]) -> BatteryStatus.State {
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
