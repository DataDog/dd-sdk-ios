import XCTest
@testable import Datadog

class DataUploadConditionsTests: XCTestCase {
    private typealias Constants = DataUploadConditions.Constants

    func testItSaysToUploadOnCertainConditions() {
        randomize(times: 100) {
            assert(
                canPerformUploadReturns: true,
                forBattery: .mockWith(
                    status: BatteryStatus(
                        state: .mockRandom(), level: Constants.minBatteryLevel + 1, isLowPowerModeEnabled: false
                    )
                ),
                forNetwork: .mockWith(reachability: .mockRandom(within: [.yes, .maybe]))
            )
            assert(
                canPerformUploadReturns: true,
                forBattery: .mockWith(
                    status: BatteryStatus(
                        state: .mockRandom(within: [.charging, .full]), level: .random(in: 0...100), isLowPowerModeEnabled: false
                    )
                ),
                forNetwork: .mockWith(reachability: .mockRandom(within: [.yes, .maybe]))
            )
            assert(
                canPerformUploadReturns: true,
                forBattery: nil,
                forNetwork: .mockWith(reachability: .mockRandom(within: [.yes, .maybe]))
            )
        }
    }

    func testItSaysToNotUploadOnCertainConditions() {
        randomize(times: 100) {
            assert(
                canPerformUploadReturns: false,
                forBattery: .mockWith(
                    status: BatteryStatus(
                        state: .mockRandom(), level: .random(in: 0...100), isLowPowerModeEnabled: .random()
                    )
                ),
                forNetwork: .mockWith(reachability: .no)
            )
            assert(
                canPerformUploadReturns: false,
                forBattery: .mockWith(
                    status: BatteryStatus(
                        state: .mockRandom(), level: .random(in: 0...100), isLowPowerModeEnabled: true
                    )
                ),
                forNetwork: .mockWith(reachability: .mockRandom())
            )
            assert(
                canPerformUploadReturns: false,
                forBattery: .mockWith(
                    status: BatteryStatus(
                        state: .mockRandom(within: [.unknown, .unplugged]), level: Constants.minBatteryLevel - 1, isLowPowerModeEnabled: .random()
                    )
                ),
                forNetwork: .mockWith(reachability: .mockRandom())
            )
            assert(
                canPerformUploadReturns: false,
                forBattery: nil,
                forNetwork: .mockWith(reachability: .no)
            )
        }
    }

    private func assert(
        canPerformUploadReturns value: Bool,
        forBattery battery: BatteryStatusProviderMock?,
        forNetwork network: NetworkStatusProviderMock,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let conditions = DataUploadConditions(batteryStatus: battery, networkStatus: network)
        XCTAssertEqual(
            value,
            conditions.canPerformUpload(),
            "Expected `\(value)` but got `\(!value)` for:\n\(String(describing: battery?.current)) and\n\(String(describing: network.current))",
            file: file,
            line: line
        )
    }

    private func randomize(times: Int, block: () -> Void) {
        (0..<times).forEach { _ in block() }
    }
}
