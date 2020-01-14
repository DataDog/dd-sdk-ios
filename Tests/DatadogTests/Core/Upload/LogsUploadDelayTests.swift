import XCTest
@testable import Datadog

class DataUploadDelayTests: XCTestCase {
    func testWhenNotModified_itReturnsDefaultDelay() {
        var delay = LogsUploadStrategy.defaultLogsUploadDelay
        XCTAssertEqual(delay.nextUploadDelay(), LogsUploadStrategy.Constants.defaultLogsUploadDelay)
        XCTAssertEqual(delay.nextUploadDelay(), LogsUploadStrategy.Constants.defaultLogsUploadDelay)
    }

    func testWhenDecreasing_itGoesDownToMinimumDelay() {
        var delay = LogsUploadStrategy.defaultLogsUploadDelay
        var previousValue: TimeInterval = delay.nextUploadDelay()

        while previousValue != LogsUploadStrategy.Constants.minLogsUploadDelay {
            delay.decrease()

            let nextValue = delay.nextUploadDelay()
            XCTAssertEqual(
                nextValue / previousValue,
                LogsUploadStrategy.Constants.logsUploadDelayDecreaseFactor,
                accuracy: 0.1
            )
            XCTAssertLessThanOrEqual(nextValue, max(previousValue, LogsUploadStrategy.Constants.minLogsUploadDelay))

            previousValue = nextValue
        }
    }

    func testWhenIncreasedOnce_itReturnsMaximumDelayOnceThenGoesBackToDefaultDelay() {
        var delay = LogsUploadStrategy.defaultLogsUploadDelay
        delay.decrease()
        delay.increaseOnce()

        XCTAssertEqual(delay.nextUploadDelay(), LogsUploadStrategy.Constants.maxLogsUploadDelay)
        XCTAssertEqual(delay.nextUploadDelay(), LogsUploadStrategy.Constants.defaultLogsUploadDelay)
        XCTAssertEqual(delay.nextUploadDelay(), LogsUploadStrategy.Constants.defaultLogsUploadDelay)
    }
}
