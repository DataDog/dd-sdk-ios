import XCTest
@testable import Datadog

class HTTPHeadersTests: XCTestCase {
    func testWhenRunningOnMobileDevice_itCreatesExpectedHeaders() {
        let headers = HTTPHeaders(
            appContext: .mockWith(
                bundleVersion: "1.0.0",
                executableName: "app-name",
                mobileDevice: .mockWith(model: "iPhone", osName: "iOS", osVersion: "13.3.1")
            )
        )

        XCTAssertEqual(
            headers.all,
            [
            "Content-Type": "application/json",
            "User-Agent": "app-name/1.0.0 CFNetwork (iPhone; iOS/13.3.1)"
            ]
        )
    }

    func testWhenRunningOnOtherDevice_itCreatesExpectedHeaders() {
        let headers = HTTPHeaders(
            appContext: .mockWith(mobileDevice: nil)
        )

        XCTAssertEqual(
            headers.all,
            ["Content-Type": "application/json",]
        )
    }
}
