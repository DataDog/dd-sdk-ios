/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

@testable import Datadog

// MARK: - Configuration Mocks

extension Datadog.Configuration {
    static func mockAny() -> Datadog.Configuration {
        return .mockWith()
    }

    static func mockWith(
        clientToken: String = .mockAny(),
        environment: String = .mockAny(),
        loggingEnabled: Bool = false,
        tracingEnabled: Bool = false,
        logsEndpoint: LogsEndpoint = .us,
        tracesEndpoint: TracesEndpoint = .us,
        serviceName: String? = .mockAny()
    ) -> Datadog.Configuration {
        return Datadog.Configuration(
            clientToken: clientToken,
            environment: environment,
            loggingEnabled: loggingEnabled,
            tracingEnabled: tracingEnabled,
            logsEndpoint: logsEndpoint,
            tracesEndpoint: tracesEndpoint,
            serviceName: serviceName
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
        logsUploadURLWithClientToken: URL = .mockAny(),
        tracesUploadURLWithClientToken: URL = .mockAny()
    ) -> Datadog.ValidConfiguration {
        return Datadog.ValidConfiguration(
            applicationName: applicationName,
            applicationVersion: applicationVersion,
            applicationBundleIdentifier: applicationBundleIdentifier,
            serviceName: serviceName,
            environment: environment,
            logsUploadURLWithClientToken: logsUploadURLWithClientToken,
            tracesUploadURLWithClientToken: tracesUploadURLWithClientToken
        )
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

// MARK: - PerformancePreset Mocks

struct StoragePerformanceMock: StoragePerformancePreset {
    let maxFileSize: UInt64
    let maxDirectorySize: UInt64
    let maxFileAgeForWrite: TimeInterval
    let minFileAgeForRead: TimeInterval
    let maxFileAgeForRead: TimeInterval
    let maxObjectsInFile: Int
    let maxObjectSize: UInt64

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
        maxFileAgeForWrite: 0, // always return new file for writting
        minFileAgeForRead: readAllFiles.minFileAgeForRead,
        maxFileAgeForRead: readAllFiles.maxFileAgeForRead,
        maxObjectsInFile: 1, // write each data to new file
        maxObjectSize: .max
    )
}

struct UploadPerformanceMock: UploadPerformancePreset {
    let initialUploadDelay: TimeInterval
    let defaultUploadDelay: TimeInterval
    let minUploadDelay: TimeInterval
    let maxUploadDelay: TimeInterval
    let uploadDelayDecreaseFactor: Double

    static let noOp = UploadPerformanceMock(
        initialUploadDelay: .distantFuture,
        defaultUploadDelay: .distantFuture,
        minUploadDelay: .distantFuture,
        maxUploadDelay: .distantFuture,
        uploadDelayDecreaseFactor: 1
    )

    static let veryQuick = UploadPerformanceMock(
        initialUploadDelay: 0.05,
        defaultUploadDelay: 0.05,
        minUploadDelay: 0.05,
        maxUploadDelay: 0.05,
        uploadDelayDecreaseFactor: 1
    )
}

extension PerformancePreset {
    static func combining(storagePerformance storage: StoragePerformanceMock, uploadPerformance upload: UploadPerformanceMock) -> PerformancePreset {
        PerformancePreset(
            maxFileSize: storage.maxFileSize,
            maxDirectorySize: storage.maxDirectorySize,
            maxFileAgeForWrite: storage.maxFileAgeForWrite,
            minFileAgeForRead: storage.minFileAgeForRead,
            maxFileAgeForRead: storage.maxFileAgeForRead,
            maxObjectsInFile: storage.maxObjectsInFile,
            maxObjectSize: storage.maxObjectSize,
            initialUploadDelay: upload.initialUploadDelay,
            defaultUploadDelay: upload.defaultUploadDelay,
            minUploadDelay: upload.minUploadDelay,
            maxUploadDelay: upload.maxUploadDelay,
            uploadDelayDecreaseFactor: upload.uploadDelayDecreaseFactor
        )
    }
}

// MARK: - Features Common Mocks

extension DataFormat {
    static func mockAny() -> DataFormat {
        return mockWith()
    }

    static func mockWith(
        prefix: String = .mockAny(),
        suffix: String = .mockAny(),
        separator: String = .mockAny()
    ) -> DataFormat {
        return DataFormat(
            prefix: prefix,
            suffix: suffix,
            separator: separator
        )
    }
}

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

extension UploadURLProvider {
    static func mockAny() -> UploadURLProvider {
        return UploadURLProvider(
            urlWithClientToken: URL(string: "https://app.example.com/v2/api?abc-def-ghi")!,
            queryItemProviders: []
        )
    }
}

extension HTTPClient {
    static func mockAny() -> HTTPClient {
        return HTTPClient(session: URLSession())
    }
}

extension HTTPHeaders {
    static func mockAny() -> HTTPHeaders {
        return HTTPHeaders(headers: [])
    }
}

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

extension EncodableValue {
    static func mockAny() -> EncodableValue {
        return EncodableValue(String.mockAny())
    }
}

// MARK: - Global Dependencies Mocks

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
