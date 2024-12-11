/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
@testable import DatadogSessionReplay

class RecordingTriggerTests: XCTestCase {
    // swiftlint:disable implicitly_unwrapped_optional
    var recordingTrigger: RecordingTrigger!
    // swiftlint:enable implicitly_unwrapped_optional

    override func setUpWithError() throws {
        recordingTrigger = try RecordingTrigger()
    }

    override func tearDownWithError() throws {
        recordingTrigger = nil
    }

    func testStartAndStopRecordingTriggers() {
        var didTriggerCalledCount = 0
        recordingTrigger.startWatchingTriggers {
            didTriggerCalledCount += 1
        }

        XCTAssertEqual(didTriggerCalledCount, 0)

        randomTrigger()

        XCTAssertEqual(didTriggerCalledCount, 1)

        recordingTrigger.stopWatchingTriggers()

        XCTAssertEqual(didTriggerCalledCount, 1)

        randomTrigger()

        XCTAssertEqual(didTriggerCalledCount, 1)
    }

    private func randomTrigger() {
        switch Int.random(in: 0...3) {
        case 0:
            UIApplication.shared.sendEvent(UIEvent())
        case 1:
            UIView().layoutSubviews()
        case 2:
            UIGraphicsBeginImageContextWithOptions(CGSize(width: 1, height: 1), false, 0.0)
            if let context = UIGraphicsGetCurrentContext() {
                CALayer().draw(in: context)
            }
            UIGraphicsEndImageContext()
        case 3:
            CALayer().setNeedsDisplay()
        default:
            break
        }
    }
}
#endif
