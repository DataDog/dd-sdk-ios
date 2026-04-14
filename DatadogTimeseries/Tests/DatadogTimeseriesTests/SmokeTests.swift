import XCTest
@testable import DatadogTimeseries

final class SmokeTests: XCTestCase {
    func testPackageCompiles() {
        let sample = Sample(timestamp: 1_000_000_000, value: 42.0)
        XCTAssertEqual(sample.timestamp, 1_000_000_000)
        XCTAssertEqual(sample.value, 42.0)
    }
}
