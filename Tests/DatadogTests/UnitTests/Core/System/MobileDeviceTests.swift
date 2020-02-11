import XCTest
@testable import Datadog

class MobileDeviceTests: XCTestCase {
    #if canImport(UIKit)
    func testWhenRunningOnMobile_itReturnsDevice() {
        XCTAssertNotNil(MobileDevice.current)
    }
    #else
    func testWhenRunningOnOtherPlatforms_itReturnsNil() {
        XCTAssertNil(MobileDevice.current)
    }
    #endif
}
