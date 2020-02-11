import XCTest
@testable import Datadog

class BatteryStatusProviderTests: XCTestCase {
    func testWhenInstantiated_itEnablesBatteryMonitoring() {
        let expectation = self.expectation(description: "call configuration block")

        let mobileDevice: MobileDevice = .mockWith(
            enableBatteryStatusMonitoring: { expectation.fulfill() }
        )

        _ = BatteryStatusProvider(mobileDevice: mobileDevice)

        waitForExpectations(timeout: 1, handler: nil)
    }

    func testWhenDeinitialized_itResetsBatteryMonitoring() {
        let expectation = self.expectation(description: "call configuration block")

        let mobileDevice: MobileDevice = .mockWith(
            resetBatteryStatusMonitoring: { expectation.fulfill() }
        )

        autoreleasepool {
            _ = BatteryStatusProvider(mobileDevice: mobileDevice)
        }

        waitForExpectations(timeout: 1, handler: nil)
    }

    // swiftlint:disable trailing_whitespace
    func testItReturnsCurrentBatteryStatus() {
        let mobileDevice: MobileDevice = .mockWith(
            currentBatteryStatus: {
                BatteryStatus(
                    state: .charging,
                    level: 0.5,
                    isLowPowerModeEnabled: false
                )
            }
        )

        let batteryStatusProvider = BatteryStatusProvider(mobileDevice: mobileDevice)

        XCTAssertEqual(batteryStatusProvider.current.state, .charging)
        XCTAssertEqual(batteryStatusProvider.current.level, 0.5)
        XCTAssertFalse(batteryStatusProvider.current.isLowPowerModeEnabled)
    }
    // swiftlint:enable trailing_whitespace
}
