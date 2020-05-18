/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import XCTest
@testable import Datadog

/*
A collection of SDK object mocks.
It follows the mocking conventions described in `FoundationMocks.swift`.
 */

// MARK: - Primitive types

extension String {
    /// Returns string being a valid name of the file managed by `FilesOrchestrator`.
    static func mockAnyFileName() -> String {
        return Date.mockAny().toFileName
    }
}

// MARK: - Date and time

/// `DateProvider` mock returning consecutive dates in custom intervals, starting from given reference date.
class RelativeDateProvider: DateProvider {
    private(set) var date: Date
    internal let timeInterval: TimeInterval
    private let queue = DispatchQueue(label: "queue-RelativeDateProvider-\(UUID().uuidString)")

    init(using date: Date = Date()) {
        self.date = date
        self.timeInterval = 0
    }

    init(startingFrom referenceDate: Date = Date(), advancingBySeconds timeInterval: TimeInterval = 0) {
        self.date = referenceDate
        self.timeInterval = timeInterval
    }

    /// Returns current date and advances next date by `timeInterval`.
    func currentDate() -> Date {
        defer {
            queue.async {
                self.date.addTimeInterval(self.timeInterval)
            }
        }
        return queue.sync {
            return date
        }
    }

    /// Pushes time forward by given number of seconds.
    func advance(bySeconds seconds: TimeInterval) {
        queue.async {
            self.date = self.date.addingTimeInterval(seconds)
        }
    }
}

// MARK: - PerformancePreset

extension PerformancePreset {
    /// Mocks performance preset which results with no writes and no uploads.
    static func mockNoOp() -> PerformancePreset {
        return .mockWith(
            maxBatchSize: 0,
            maxSizeOfLogsDirectory: 0,
            maxFileAgeForWrite: 0,
            minFileAgeForRead: 0,
            maxFileAgeForRead: 0,
            maxLogsPerBatch: 0,
            maxLogSize: 0,
            initialLogsUploadDelay: .distantFuture,
            defaultLogsUploadDelay: .distantFuture,
            minLogsUploadDelay: .distantFuture,
            maxLogsUploadDelay: .distantFuture,
            logsUploadDelayDecreaseFactor: 1
        )
    }

    /// Mocks performance preset which optimizes read / write / upload time for fast unit tests execution.
    static func mockUnitTestsPerformancePreset() -> PerformancePreset {
        return PerformancePreset(
            // persistence
            maxBatchSize: .max, // unlimited
            maxSizeOfLogsDirectory: .max, // unlimited
            maxFileAgeForWrite: 0, // write each data to new file
            minFileAgeForRead: -1, // read all files
            maxFileAgeForRead: .distantFuture, // read all files
            maxLogsPerBatch: 1, // write each data to new file
            maxLogSize: .max, // unlimited

            // upload
            initialLogsUploadDelay: 0.05,
            defaultLogsUploadDelay: 0.05,
            minLogsUploadDelay: 0.05,
            maxLogsUploadDelay: 0.05,
            logsUploadDelayDecreaseFactor: 1
        )
    }

    /// Partial mock for performance preset optimized for different write / reads / upload use cases in unit tests.
    static func mockWith(
        maxBatchSize: UInt64 = .mockAny(),
        maxSizeOfLogsDirectory: UInt64 = .mockAny(),
        maxFileAgeForWrite: TimeInterval = .mockAny(),
        minFileAgeForRead: TimeInterval = .mockAny(),
        maxFileAgeForRead: TimeInterval = .mockAny(),
        maxLogsPerBatch: Int = .mockAny(),
        maxLogSize: UInt64 = .mockAny(),
        initialLogsUploadDelay: TimeInterval = .mockAny(),
        defaultLogsUploadDelay: TimeInterval = .mockAny(),
        minLogsUploadDelay: TimeInterval = .mockAny(),
        maxLogsUploadDelay: TimeInterval = .mockAny(),
        logsUploadDelayDecreaseFactor: Double = .mockAny()
    ) -> PerformancePreset {
        return PerformancePreset(
            maxBatchSize: maxBatchSize,
            maxSizeOfLogsDirectory: maxSizeOfLogsDirectory,
            maxFileAgeForWrite: maxFileAgeForWrite,
            minFileAgeForRead: minFileAgeForRead,
            maxFileAgeForRead: maxFileAgeForRead,
            maxLogsPerBatch: maxLogsPerBatch,
            maxLogSize: maxLogSize,
            initialLogsUploadDelay: initialLogsUploadDelay,
            defaultLogsUploadDelay: defaultLogsUploadDelay,
            minLogsUploadDelay: minLogsUploadDelay,
            maxLogsUploadDelay: maxLogsUploadDelay,
            logsUploadDelayDecreaseFactor: logsUploadDelayDecreaseFactor
        )
    }
}

// MARK: - Files orchestration

extension WritableFileConditions {
    /// Write conditions causing `FilesOrchestrator` to always pick the same file for writting.
    static func mockWriteToSingleFile() -> WritableFileConditions {
        return WritableFileConditions(
            performance: .mockWith(
                maxBatchSize: .max,
                maxSizeOfLogsDirectory: .max,
                maxFileAgeForWrite: .distantFuture,
                maxLogsPerBatch: .max,
                maxLogSize: .max
            )
        )
    }

    /// Write conditions causing `FilesOrchestrator` to create new file for each write.
    static func mockWriteToNewFileEachTime() -> WritableFileConditions {
        return WritableFileConditions(
            performance: .mockWith(
                maxBatchSize: .max,
                maxSizeOfLogsDirectory: .max,
                maxFileAgeForWrite: .distantFuture,
                maxLogsPerBatch: 1,
                maxLogSize: .max
            )
        )
    }
}

extension ReadableFileConditions {
    /// Read conditions causing `FilesOrchestrator` to pick all files for reading, no matter of their creation time.
    static func mockReadAllFiles() -> ReadableFileConditions {
        return ReadableFileConditions(
            performance: .mockWith(
                minFileAgeForRead: -1,
                maxFileAgeForRead: .distantFuture
            )
        )
    }
}

extension FilesOrchestrator {
    /// Mocks `FilesOrchestrator` which always returns the same file for `getWritableFile()`.
    static func mockWriteToSingleFile(in directory: Directory) -> FilesOrchestrator {
        return FilesOrchestrator(
            directory: directory,
            writeConditions: .mockWriteToSingleFile(),
            readConditions: ReadableFileConditions(performance: .mockUnitTestsPerformancePreset()),
            dateProvider: SystemDateProvider()
        )
    }

    /// Mocks `FilesOrchestrator` which does not perform age classification for `getReadableFile()`.
    static func mockReadAllFiles(in directory: Directory) -> FilesOrchestrator {
        return FilesOrchestrator(
            directory: directory,
            writeConditions: WritableFileConditions(performance: .mockUnitTestsPerformancePreset()),
            readConditions: .mockReadAllFiles(),
            dateProvider: SystemDateProvider()
        )
    }
}

extension FileWriter {
    /// Mocks `FileWriter` writting data to single file with given name.
    static func mockWrittingToSingleFile(
        in directory: Directory,
        on queue: DispatchQueue
    ) -> FileWriter {
        return FileWriter(
            orchestrator: .mockWriteToSingleFile(in: directory),
            queue: queue
        )
    }
}

// MARK: - HTTP

extension HTTPHeaders {
    static func mockAny() -> HTTPHeaders {
        return HTTPHeaders(appName: .mockAny(), appVersion: .mockAny(), device: .mockAny())
    }
}

// MARK: - System

extension MobileDevice {
    static func mockAny() -> MobileDevice {
        return .mockWith()
    }

    static func mockWith(
        model: String = .mockAny(),
        osName: String = .mockAny(),
        osVersion: String = .mockAny(),
        enableBatteryStatusMonitoring: @escaping () -> Void = {},
        resetBatteryStatusMonitoring: @escaping () -> Void = {},
        currentBatteryStatus: @escaping () -> BatteryStatus = { .mockAny() }
    ) -> MobileDevice {
        return MobileDevice(
            model: model,
            osName: osName,
            osVersion: osVersion,
            enableBatteryStatusMonitoring: enableBatteryStatusMonitoring,
            resetBatteryStatusMonitoring: resetBatteryStatusMonitoring,
            currentBatteryStatus: currentBatteryStatus
        )
    }
}

extension BatteryStatus.State {
    static func mockRandom(within cases: [BatteryStatus.State] = [.unknown, .unplugged, .charging, .full]) -> BatteryStatus.State {
        return cases.randomElement()!
    }
}

extension BatteryStatus {
    static func mockAny() -> BatteryStatus {
        return mockWith()
    }

    static func mockWith(
        state: State = .charging,
        level: Float = 0.5,
        isLowPowerModeEnabled: Bool = false
    ) -> BatteryStatus {
        return BatteryStatus(state: state, level: level, isLowPowerModeEnabled: isLowPowerModeEnabled)
    }
}

struct BatteryStatusProviderMock: BatteryStatusProviderType {
    let current: BatteryStatus

    static func mockWith(status: BatteryStatus) -> BatteryStatusProviderMock {
        return BatteryStatusProviderMock(current: status)
    }
}

extension NetworkConnectionInfo.Reachability {
    static func mockAny() -> NetworkConnectionInfo.Reachability {
        return .maybe
    }

    static func mockRandom(
        within cases: [NetworkConnectionInfo.Reachability] = [.yes, .no, .maybe]
    ) -> NetworkConnectionInfo.Reachability {
        return cases.randomElement()!
    }
}

extension NetworkConnectionInfo {
    static func mockAny() -> NetworkConnectionInfo {
        return mockWith()
    }

    static func mockWith(
        reachability: NetworkConnectionInfo.Reachability = .mockAny(),
        availableInterfaces: [NetworkConnectionInfo.Interface] = [.wifi],
        supportsIPv4: Bool = true,
        supportsIPv6: Bool = true,
        isExpensive: Bool = true,
        isConstrained: Bool = true
    ) -> NetworkConnectionInfo {
        return NetworkConnectionInfo(
            reachability: reachability,
            availableInterfaces: availableInterfaces,
            supportsIPv4: supportsIPv4,
            supportsIPv6: supportsIPv6,
            isExpensive: isExpensive,
            isConstrained: isConstrained
        )
    }
}

class NetworkConnectionInfoProviderMock: NetworkConnectionInfoProviderType {
    private let queue = DispatchQueue(label: "com.datadoghq.NetworkConnectionInfoProviderMock")
    private var _current: NetworkConnectionInfo?

    init(networkConnectionInfo: NetworkConnectionInfo?) {
        _current = networkConnectionInfo
    }

    func set(current: NetworkConnectionInfo?) {
        queue.async { self._current = current }
    }

    // MARK: - NetworkConnectionInfoProviderType

    var current: NetworkConnectionInfo? {
        queue.sync { _current }
    }

    // MARK: - Mocking

    static func mockAny() -> NetworkConnectionInfoProviderMock {
        return mockWith()
    }

    static func mockWith(
        networkConnectionInfo: NetworkConnectionInfo? = .mockAny()
    ) -> NetworkConnectionInfoProviderMock {
        return NetworkConnectionInfoProviderMock(networkConnectionInfo: networkConnectionInfo)
    }
}

extension CarrierInfo.RadioAccessTechnology {
    static func mockAny() -> CarrierInfo.RadioAccessTechnology { .LTE }
}

extension CarrierInfo {
    static func mockAny() -> CarrierInfo {
        return mockWith()
    }

    static func mockWith(
        carrierName: String? = .mockAny(),
        carrierISOCountryCode: String? = .mockAny(),
        carrierAllowsVOIP: Bool = .mockAny(),
        radioAccessTechnology: CarrierInfo.RadioAccessTechnology = .mockAny()
    ) -> CarrierInfo {
        return CarrierInfo(
            carrierName: carrierName,
            carrierISOCountryCode: carrierISOCountryCode,
            carrierAllowsVOIP: carrierAllowsVOIP,
            radioAccessTechnology: radioAccessTechnology
        )
    }
}

class CarrierInfoProviderMock: CarrierInfoProviderType {
    private let queue = DispatchQueue(label: "com.datadoghq.CarrierInfoProviderMock")
    private var _current: CarrierInfo?

    init(carrierInfo: CarrierInfo?) {
        _current = carrierInfo
    }

    func set(current: CarrierInfo?) {
        queue.async { self._current = current }
    }

    // MARK: - CarrierInfoProviderType

    var current: CarrierInfo? {
        queue.sync { _current }
    }

    // MARK: - Mocking

    static func mockAny() -> CarrierInfoProviderMock {
        return mockWith()
    }

    static func mockWith(
        carrierInfo: CarrierInfo = .mockAny()
    ) -> CarrierInfoProviderMock {
        return CarrierInfoProviderMock(carrierInfo: carrierInfo)
    }
}

// MARK: - Persistence and Upload

extension UploadURLProvider {
    static func mockAny() -> UploadURLProvider {
        return UploadURLProvider(
            urlWithClientToken: URL(string: "https://app.example.com/v2/api?abc-def-ghi")!,
            dateProvider: RelativeDateProvider(using: Date.mockDecember15th2019At10AMUTC())
        )
    }
}

extension DataUploadDelay {
    /// Mocks constant delay returning given amount of seconds, no matter of `.decrease()` or `.increaseOnce()` calls.
    static func mockConstantDelay(of seconds: TimeInterval) -> DataUploadDelay {
        return DataUploadDelay(
            performance: .mockWith(
                initialLogsUploadDelay: seconds,
                defaultLogsUploadDelay: seconds,
                minLogsUploadDelay: seconds,
                maxLogsUploadDelay: seconds,
                logsUploadDelayDecreaseFactor: 1
            )
        )
    }
}

extension DataUploadConditions {
    static func mockAlwaysPerformingUpload() -> DataUploadConditions {
        return DataUploadConditions(
            batteryStatus: BatteryStatusProviderMock.mockWith(
                status: BatteryStatus(state: .full, level: 100, isLowPowerModeEnabled: false)
            ),
            networkConnectionInfo: NetworkConnectionInfoProviderMock(
                networkConnectionInfo: NetworkConnectionInfo(
                    reachability: .yes,
                    availableInterfaces: [.wifi],
                    supportsIPv4: true,
                    supportsIPv6: true,
                    isExpensive: false,
                    isConstrained: false
                )
            )
        )
    }
}

extension HTTPClient {
    static func mockAny() -> HTTPClient {
        return HTTPClient(session: URLSession())
    }
}

// MARK: - Integration

extension Datadog.Configuration {
    static func mockAny() -> Datadog.Configuration {
        return .mockWith()
    }

    static func mockWith(
        clientToken: String = .mockAny(),
        logsEndpoint: LogsEndpoint = .us,
        serviceName: String? = .mockAny(),
        environment: String = .mockAny()
    ) -> Datadog.Configuration {
        return Datadog.Configuration(
            clientToken: clientToken,
            logsEndpoint: logsEndpoint,
            serviceName: serviceName,
            environment: environment
        )
    }
}

extension Datadog.ValidConfiguration {
    static func mockAny() -> Datadog.ValidConfiguration {
        return mockWith()
    }

    static func mockWith(
        applicationName: String = .mockAny(),
        applicationVersion: String = .mockAny(),
        applicationBundleIdentifier: String = .mockAny(),
        serviceName: String = .mockAny(),
        environment: String = .mockAny(),
        logsUploadURLWithClientToken: URL = .mockAny()
    ) -> Datadog.ValidConfiguration {
        return Datadog.ValidConfiguration(
            applicationName: applicationName,
            applicationVersion: applicationVersion,
            applicationBundleIdentifier: applicationBundleIdentifier,
            serviceName: serviceName,
            environment: environment,
            logsUploadURLWithClientToken: logsUploadURLWithClientToken
        )
    }
}

/// Mock which can be used to intercept messages printed by `developerLogger` or
/// `userLogger` by overwritting `Datadog.consolePrint` function:
///
///     let printFunction = PrintFunctionMock()
///     consolePrint = printFunction.print
///
class PrintFunctionMock {
    private(set) var printedMessage: String?

    func print(message: String) {
        printedMessage = message
    }
}

extension AppContext {
    static func mockAny() -> AppContext {
        return mockWith()
    }

    static func mockWith(
        bundleType: BundleType = .iOSApp,
        bundleIdentifier: String? = .mockAny(),
        bundleVersion: String? = .mockAny(),
        bundleName: String? = .mockAny()
    ) -> AppContext {
        return AppContext(
            bundleType: bundleType,
            bundleIdentifier: bundleIdentifier,
            bundleVersion: bundleVersion,
            bundleName: bundleName
        )
    }
}

extension UserInfo {
    static func mockAny() -> UserInfo {
        return mockEmpty()
    }

    static func mockEmpty() -> UserInfo {
        return UserInfo(id: nil, name: nil, email: nil)
    }
}

extension UserInfoProvider {
    static func mockAny() -> UserInfoProvider {
        return mockWith()
    }

    static func mockWith(userInfo: UserInfo = .mockAny()) -> UserInfoProvider {
        let provider = UserInfoProvider()
        provider.value = userInfo
        return provider
    }
}

/// `LogOutput` recording received logs.
class LogOutputMock: LogOutput {
    struct RecordedLog: Equatable {
        let level: LogLevel
        let message: String
    }

    var recordedLog: RecordedLog? = nil

    func writeLogWith(level: LogLevel, message: String, attributes: [String: Encodable], tags: Set<String>) {
        recordedLog = RecordedLog(level: level, message: message)
    }
}
