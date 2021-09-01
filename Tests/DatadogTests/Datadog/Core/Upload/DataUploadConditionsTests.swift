/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class DataUploadConditionsTests: XCTestCase {
    private typealias Constants = DataUploadConditions.Constants

    func testItSaysToUploadOnCertainConditions() {
        `repeat`(times: 100) {
            assert(
                canPerformUploadReturns: true,
                forBattery: .mockWith(
                    status: BatteryStatus(
                        state: .mockRandom(), level: Constants.minBatteryLevel + 0.01, isLowPowerModeEnabled: false
                    )
                ),
                forNetwork: .mockWith(
                    networkConnectionInfo: .mockWith(reachability: .mockRandom(within: [.yes, .maybe]))
                )
            )
            assert(
                canPerformUploadReturns: true,
                forBattery: .mockWith(
                    status: BatteryStatus(
                        state: .mockRandom(within: [.charging, .full]), level: .random(in: 0...100), isLowPowerModeEnabled: false
                    )
                ),
                forNetwork: .mockWith(
                    networkConnectionInfo: .mockWith(reachability: .mockRandom(within: [.yes, .maybe]))
                )
            )
            assert(
                canPerformUploadReturns: true,
                forBattery: nil,
                forNetwork: .mockWith(
                    networkConnectionInfo: .mockWith(reachability: .mockRandom(within: [.yes, .maybe]))
                )
            )
        }
    }

    func testItSaysToNotUploadOnCertainConditions() {
        `repeat`(times: 100) {
            assert(
                canPerformUploadReturns: false,
                forBattery: .mockWith(
                    status: BatteryStatus(
                        state: .mockRandom(within: [.unplugged, .charging, .full]), level: .random(in: 0...100), isLowPowerModeEnabled: .random()
                    )
                ),
                forNetwork: .mockWith(
                    networkConnectionInfo: .mockWith(reachability: .no)
                )
            )
            assert(
                canPerformUploadReturns: false,
                forBattery: .mockWith(
                    status: BatteryStatus(
                        state: .mockRandom(within: [.unplugged, .charging, .full]), level: .random(in: 0...100), isLowPowerModeEnabled: .random()
                    )
                ),
                forNetwork: .mockWith(networkConnectionInfo: nil)
            )
            assert(
                canPerformUploadReturns: false,
                forBattery: .mockWith(
                    status: BatteryStatus(
                        state: .mockRandom(within: [.unplugged, .charging, .full]), level: .random(in: 0...100), isLowPowerModeEnabled: true
                    )
                ),
                forNetwork: .mockWith(
                    networkConnectionInfo: .mockWith(reachability: .mockRandom())
                )
            )
            assert(
                canPerformUploadReturns: false,
                forBattery: .mockWith(
                    status: BatteryStatus(
                        state: .unplugged, level: Constants.minBatteryLevel - 0.01, isLowPowerModeEnabled: .random()
                    )
                ),
                forNetwork: .mockWith(
                    networkConnectionInfo: .mockWith(reachability: .mockRandom())
                )
            )
            assert(
                canPerformUploadReturns: false,
                forBattery: nil,
                forNetwork: .mockWith(
                    networkConnectionInfo: .mockWith(reachability: .no)
                )
            )
        }
    }

    func testItSaysToUploadIfTheBatteryStatusIsUnknown() {
        `repeat`(times: 10) {
            assert(
                canPerformUploadReturns: true,
                forBattery: .mockWith(
                    status: BatteryStatus(
                        state: .unknown, level: .random(in: -100...100), isLowPowerModeEnabled: .random()
                    )
                ),
                forNetwork: .mockWith(
                    networkConnectionInfo: .mockWith(reachability: .mockRandom(within: [.yes, .maybe]))
                )
            )
        }
    }

    private func assert(
        canPerformUploadReturns value: Bool,
        forBattery battery: BatteryStatusProviderMock?,
        forNetwork network: NetworkConnectionInfoProviderMock,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let conditions = DataUploadConditions(batteryStatus: battery, networkConnectionInfo: network)
        let canPerformUpload = conditions.blockersForUpload().isEmpty
        XCTAssertEqual(
            value,
            canPerformUpload,
            "Expected `\(value)` but got `\(!value)` for:\n\(String(describing: battery?.current)) and\n\(String(describing: network.current))",
            file: file,
            line: line
        )
    }

    private func `repeat`(times: Int, block: () -> Void) {
        (0..<times).forEach { _ in block() }
    }
}
