/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

@testable import Datadog
import XCTest

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

class RUMEventOutputMock: RUMEventOutput {
    func write<DM: RUMDataModel>(rumEvent: RUMEvent<DM>) {}
}

// MARK: - RUMCommand Mocks

extension RUMCommand {
    static func mockAny() -> RUMCommand {
        return .addUserAction(userAction: .tap, attributes: nil)
    }
}

// MARK: - RUMScope Mocks

extension RUMScopeDependencies {
    static func mockAny() -> RUMScopeDependencies {
        return mockWith()
    }

    static func mockWith(
        dateProvider: DateProvider = SystemDateProvider(),
        eventBuilder: RUMEventBuilder = RUMEventBuilder(
            userInfoProvider: .mockAny(),
            networkConnectionInfoProvider: nil,
            carrierInfoProvider: nil
        ),
        eventOutput: RUMEventOutput = RUMEventOutputMock()
    ) -> RUMScopeDependencies {
        return RUMScopeDependencies(
            dateProvider: dateProvider,
            eventBuilder: eventBuilder,
            eventOutput: eventOutput
        )
    }
}

extension RUMApplicationScope {
    static func mockAny() -> RUMApplicationScope {
        return mockWith()
    }

    static func mockWith(
        rumApplicationID: String = .mockAny(),
        dependencies: RUMScopeDependencies = .mockAny()
    ) -> RUMApplicationScope {
        return RUMApplicationScope(
            rumApplicationID: rumApplicationID,
            dependencies: dependencies
        )
    }
}

/// `RUMScope` recording processed commands.
class RUMScopeMock: RUMScope {
    private let queue = DispatchQueue(label: "com.datadoghq.RUMScopeMock")
    private var expectation: XCTestExpectation?
    private var commands: [RUMCommand] = []

    func waitAndReturnProcessedCommands(
        count: UInt,
        timeout: TimeInterval,
        file: StaticString = #file,
        line: UInt = #line
    ) -> [RUMCommand] {
        precondition(expectation == nil, "The `RUMScopeMock` is already waiting on `waitAndReturnProcessedCommands`.")
        let expectation = XCTestExpectation(description: "Receive \(count) RUMCommands.")

        if count > 0 {
            expectation.expectedFulfillmentCount = Int(count)
        } else {
            expectation.isInverted = true
        }

        queue.sync {
            self.expectation = expectation
            self.commands.forEach { _ in expectation.fulfill() } // fulfill already recorded
        }

        XCTWaiter().wait(for: [expectation], timeout: timeout)

        return queue.sync { self.commands }
    }

    // MARK: - RUMScope

    let context = RUMContext(
        rumApplicationID: .mockAny(),
        sessionID: UUID(),
        activeViewID: nil,
        activeViewURI: nil,
        activeUserActionID: nil
    )

    func process(command: RUMCommand) -> Bool {
        queue.async {
            self.commands.append(command)
            self.expectation?.fulfill()
        }
        return true
    }
}

// MARK: - Utilities

extension RUMCommand: Equatable {
    public static func == (_ lhs: RUMCommand, _ rhs: RUMCommand) -> Bool {
        return String(describing: lhs) == String(describing: rhs)
    }
}
