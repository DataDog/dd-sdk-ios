/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
@testable import DatadogCore

class DataUploadConditionsTests: XCTestCase {
    private typealias Constants = DataUploadConditions.Constants

    func testItSaysToUploadOnCertainConditions() {
        `repeat`(times: 100) {
            assert(
                canPerformUploadReturns: true,
                forBattery: BatteryStatus(
                    state: .mockRandom(), level: Constants.minBatteryLevel + 0.01
                ),
                isLowPowerModeEnabled: false,
                allowsConstrainedNetworkAccess: true,
                forNetwork: .mockWith(reachability: .mockRandom(within: [.yes, .maybe]))
            )
            assert(
                canPerformUploadReturns: true,
                forBattery: BatteryStatus(
                    state: .mockRandom(within: [.charging, .full]), level: .random(in: 0...100)
                ),
                isLowPowerModeEnabled: false,
                allowsConstrainedNetworkAccess: true,
                forNetwork: .mockWith(reachability: .mockRandom(within: [.yes, .maybe]))
            )
            assert(
                canPerformUploadReturns: true,
                forBattery: nil,
                isLowPowerModeEnabled: false,
                allowsConstrainedNetworkAccess: true,
                forNetwork: .mockWith(reachability: .mockRandom(within: [.yes, .maybe]))
            )
        }
    }

    func testItSaysToNotUploadOnCertainConditions() {
        `repeat`(times: 100) {
            assert(
                canPerformUploadReturns: false,
                forBattery: BatteryStatus(
                    state: .mockRandom(within: [.unplugged, .charging, .full]), level: .random(in: 0...100)
                ),
                isLowPowerModeEnabled: .random(),
                allowsConstrainedNetworkAccess: true,
                forNetwork: .mockWith(reachability: .no)
            )
            assert(
                canPerformUploadReturns: false,
                forBattery: BatteryStatus(
                    state: .mockRandom(within: [.unplugged, .charging, .full]), level: .random(in: 0...100)
                ),
                isLowPowerModeEnabled: true,
                allowsConstrainedNetworkAccess: true,
                forNetwork: .mockWith(reachability: .mockRandom())
            )
            assert(
                canPerformUploadReturns: false,
                forBattery: BatteryStatus(
                    state: .unplugged, level: Constants.minBatteryLevel - 0.01
                ),
                isLowPowerModeEnabled: .random(),
                allowsConstrainedNetworkAccess: true,
                forNetwork: .mockWith(reachability: .mockRandom())
            )
            assert(
                canPerformUploadReturns: false,
                forBattery: nil,
                isLowPowerModeEnabled: .random(),
                allowsConstrainedNetworkAccess: true,
                forNetwork: .mockWith(reachability: .no)
            )
        }
    }

    func testItSaysToUploadIfTheBatteryStatusIsUnknown() {
        `repeat`(times: 10) {
            assert(
                canPerformUploadReturns: true,
                forBattery: BatteryStatus(state: .unknown, level: .random(in: -100...100)),
                isLowPowerModeEnabled: .random(),
                allowsConstrainedNetworkAccess: true,
                forNetwork: .mockWith(reachability: .mockRandom(within: [.yes, .maybe]))
            )
        }
    }
    
    func testItSaysToUploadIfNetworkIsNotConstrained() {
        assert(
            canPerformUploadReturns: true,
            forBattery: nil,
            isLowPowerModeEnabled: false,
            allowsConstrainedNetworkAccess: true,
            forNetwork: .mockWith(reachability: .yes, isConstrained: false)
        )
        
        assert(
            canPerformUploadReturns: true,
            forBattery: nil,
            isLowPowerModeEnabled: false,
            allowsConstrainedNetworkAccess: false,
            forNetwork: .mockWith(reachability: .yes, isConstrained: false)
        )
    }
    
    func testItSaysToUploadIfNetworkIsConstrained() {
        assert(
            canPerformUploadReturns: true,
            forBattery: nil,
            isLowPowerModeEnabled: false,
            allowsConstrainedNetworkAccess: true,
            forNetwork: .mockWith(reachability: .yes, isConstrained: true)
        )
    }
    
    func testItSaysToNotUploadIfNetworkIsConstrained() {
        assert(
            canPerformUploadReturns: false,
            forBattery: nil,
            isLowPowerModeEnabled: false,
            allowsConstrainedNetworkAccess: false,
            forNetwork: .mockWith(reachability: .yes, isConstrained: true)
        )
    }

    private func assert(
        canPerformUploadReturns value: Bool,
        forBattery battery: BatteryStatus?,
        isLowPowerModeEnabled: Bool,
        allowsConstrainedNetworkAccess: Bool,
        forNetwork network: NetworkConnectionInfo,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let context: DatadogContext = .mockWith(networkConnectionInfo: network, batteryStatus: battery, isLowPowerModeEnabled: isLowPowerModeEnabled)
        let conditions = DataUploadConditions(allowsConstrainedNetworkAccess: allowsConstrainedNetworkAccess)
        let canPerformUpload = conditions.blockersForUpload(with: context).isEmpty
        XCTAssertEqual(
            value,
            canPerformUpload,
            "Expected `\(value)` but got `\(!value)` for:\n\(String(describing: battery)) and\n\(String(describing: network))",
            file: file,
            line: line
        )
    }

    private func `repeat`(times: Int, block: () -> Void) {
        (0..<times).forEach { _ in block() }
    }
}
