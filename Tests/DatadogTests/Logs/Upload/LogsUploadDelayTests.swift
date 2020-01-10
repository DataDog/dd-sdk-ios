import XCTest
@testable import Datadog

class LogsUploadDelayTests: XCTestCase {
    func testWhenNotModified_itReturnsDefaultDelay() {
        var delay = LogsUploadDelay.default
        XCTAssertEqual(delay.nextUploadDelay(), LogsFileStrategy.Constants.defaultLogsUploadDelay)
        XCTAssertEqual(delay.nextUploadDelay(), LogsFileStrategy.Constants.defaultLogsUploadDelay)
    }

    func testWhenDecreasing_itGoesDownToMinimumDelay() {
        var delay = LogsUploadDelay.default
        var previousValue: TimeInterval = delay.nextUploadDelay()

        while previousValue != LogsFileStrategy.Constants.minLogsUploadDelay {
            delay.decrease()

            let nextValue = delay.nextUploadDelay()
            XCTAssertEqual(
                nextValue / previousValue,
                LogsFileStrategy.Constants.logsUploadDelayDecreaseFactor,
                accuracy: 0.1
            )
            XCTAssertLessThanOrEqual(nextValue, max(previousValue, LogsFileStrategy.Constants.minLogsUploadDelay))

            previousValue = nextValue
        }
    }

    func testWhenIncreasedOnce_itReturnsMaximumDelayOnceThenGoesBackToDefaultDelay() {
        var delay = LogsUploadDelay.default
        delay.decrease()
        delay.increaseOnce()

        XCTAssertEqual(delay.nextUploadDelay(), LogsFileStrategy.Constants.maxLogsUploadDelay)
        XCTAssertEqual(delay.nextUploadDelay(), LogsFileStrategy.Constants.defaultLogsUploadDelay)
        XCTAssertEqual(delay.nextUploadDelay(), LogsFileStrategy.Constants.defaultLogsUploadDelay)
    }
}
