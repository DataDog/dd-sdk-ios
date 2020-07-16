/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

@testable import Datadog

extension RUMFeature {
    /// Mocks feature instance which performs no writes and no uploads.
    static func mockNoOp(temporaryDirectory: Directory) -> RUMFeature {
        return RUMFeature(
            directory: temporaryDirectory,
            configuration: .mockAny(),
            performance: .combining(storagePerformance: .noOp, uploadPerformance: .noOp),
            mobileDevice: .mockAny(),
            httpClient: .mockAny(),
            dateProvider: SystemDateProvider(),
            userInfoProvider: .mockAny(),
            networkConnectionInfoProvider: NetworkConnectionInfoProviderMock.mockWith(
                networkConnectionInfo: .mockWith(
                    reachability: .no // so it doesn't meet the upload condition
                )
            ),
            carrierInfoProvider: CarrierInfoProviderMock.mockAny()
        )
    }

    /// Mocks feature instance which performs uploads to given `ServerMock` with performance optimized for fast delivery in unit tests.
    static func mockWorkingFeatureWith(
        server: ServerMock,
        directory: Directory,
        configuration: Datadog.ValidConfiguration = .mockAny(),
        performance: PerformancePreset = .combining(
            storagePerformance: .writeEachObjectToNewFileAndReadAllFiles,
            uploadPerformance: .veryQuick
        ),
        mobileDevice: MobileDevice = .mockWith(
            currentBatteryStatus: {
                // Mock full battery, so it doesn't rely on battery condition for the upload
                return BatteryStatus(state: .full, level: 1, isLowPowerModeEnabled: false)
            }
        ),
        dateProvider: DateProvider = SystemDateProvider(),
        userInfoProvider: UserInfoProvider = .mockAny(),
        networkConnectionInfoProvider: NetworkConnectionInfoProviderType = NetworkConnectionInfoProviderMock.mockWith(
            networkConnectionInfo: .mockWith(
                reachability: .yes, // so it always meets the upload condition
                availableInterfaces: [.wifi],
                supportsIPv4: true,
                supportsIPv6: true,
                isExpensive: true,
                isConstrained: false // so it always meets the upload condition
            )
        ),
        carrierInfoProvider: CarrierInfoProviderType = CarrierInfoProviderMock.mockAny()
    ) -> RUMFeature {
        return RUMFeature(
            directory: directory,
            configuration: configuration,
            performance: performance,
            mobileDevice: mobileDevice,
            httpClient: HTTPClient(session: server.urlSession),
            dateProvider: dateProvider,
            userInfoProvider: userInfoProvider,
            networkConnectionInfoProvider: networkConnectionInfoProvider,
            carrierInfoProvider: carrierInfoProvider
        )
    }
}

// MARK: - RUM Event Mocks

struct RUMDataModelMock: RUMDataModel, Equatable {
    let attribute: String
}

// MARK: - Component Mocks

extension RUMEventBuilder {
    static func mockAny() -> RUMEventBuilder {
        return mockWith()
    }

    static func mockWith(
        userInfoProvider: UserInfoProvider = .mockAny(),
        networkConnectionInfoProvider: NetworkConnectionInfoProviderType = NetworkConnectionInfoProviderMock.mockAny(),
        carrierInfoProvider: CarrierInfoProviderType = CarrierInfoProviderMock.mockAny()
    ) -> RUMEventBuilder {
        return RUMEventBuilder(
            userInfoProvider: userInfoProvider,
            networkConnectionInfoProvider: networkConnectionInfoProvider,
            carrierInfoProvider: carrierInfoProvider
        )
    }
}

/// `RUMScope` recording processed commands.
class RUMScopeMock: RUMScope {
    let context = RUMContext(
        rumApplicationID: .mockAny(),
        sessionID: UUID(),
        activeViewID: nil,
        activeViewURI: nil,
        activeUserActionID: nil
    )

    var recordedCommands: [RUMCommand] = []

    func process(command: RUMCommand) -> Bool {
        recordedCommands.append(command)
        return false
    }
}

class RUMEventOutputMock: RUMEventOutput {
    func write<DM: RUMDataModel>(rumEvent: RUMEvent<DM>) {}
}

// MARK: - Utilities

extension RUMCommand: Equatable {
    public static func == (_ lhs: RUMCommand, _ rhs: RUMCommand) -> Bool {
        return String(describing: lhs) == String(describing: rhs)
    }
}
