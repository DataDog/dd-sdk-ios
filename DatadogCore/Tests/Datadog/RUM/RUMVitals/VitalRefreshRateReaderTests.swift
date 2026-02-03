/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import TestUtilities
import UIKit
import XCTest

@testable import DatadogRUM

final class VitalRefreshRateReaderTests: XCTestCase {
    /* Rate representation
     *
     * 0-------------------16ms------------------32ms----------------48ms
     * |        16ms        |        16ms        |        16ms        |
     *                                        Skipped
    */
    func testFramesPerSecond_given60HzFixedRateDisplay() {
        let reader = VitalRefreshRateReader()
        let frameInfoProvider = FrameInfoProviderMock(target: self, selector: .noOp)

        // first frame recorded
        frameInfoProvider.currentFrameTimestamp = 0
        frameInfoProvider.nextFrameTimestamp = 0.016
        let firstFps = reader.framesPerSecond(provider: frameInfoProvider)
        XCTAssertNil(firstFps)

        // second frame recorded
        frameInfoProvider.currentFrameTimestamp = 0.016
        frameInfoProvider.nextFrameTimestamp = 0.032
        let secondFps = reader.framesPerSecond(provider: frameInfoProvider)
        XCTAssertEqual(secondFps, 62.5) // fractional value due to low precision of timestamps

        // third frame recorded
        frameInfoProvider.currentFrameTimestamp = 0.048
        let thirdFps = reader.framesPerSecond(provider: frameInfoProvider)
        XCTAssertEqual(thirdFps, 31.25) // fractional value due to low precision of timestamps
    }

    /* Rate representation
     *
     * 0----------8ms---------16ms--------24ms--------32ms
     * |    8ms    |    8ms    |    8ms    |    8ms    |
     *                                  Skipped
    */
    func testFramesPerSecond_given120HzFixedRateDisplay_normalizesTo60Hz() {
        let reader = VitalRefreshRateReader()
        let frameInfoProvider = FrameInfoProviderMock(target: self, selector: .noOp)
        frameInfoProvider.maximumDeviceFramesPerSecond = 120

        // first frame recorded
        frameInfoProvider.currentFrameTimestamp = 0
        frameInfoProvider.nextFrameTimestamp = 0.008
        let firstFps = reader.framesPerSecond(provider: frameInfoProvider)
        XCTAssertNil(firstFps)

        // second frame recorded
        frameInfoProvider.currentFrameTimestamp = 0.008
        frameInfoProvider.nextFrameTimestamp = 0.016
        let secondFps = reader.framesPerSecond(provider: frameInfoProvider)
        XCTAssertEqual(secondFps, 60)

        // third frame recorded
        frameInfoProvider.currentFrameTimestamp = 0.016
        frameInfoProvider.nextFrameTimestamp = 0.024
        let thirdFps = reader.framesPerSecond(provider: frameInfoProvider)
        XCTAssertEqual(thirdFps, 60)

        // fourth frame recorded
        frameInfoProvider.currentFrameTimestamp = 0.032
        let fourthFps = reader.framesPerSecond(provider: frameInfoProvider)
        XCTAssertEqual(fourthFps, 30)
    }

    /* Rate representation
     *
     * 0----------8ms----------------------------33ms---------43ms
     * |    8ms    |             25ms             |    10ms    |
    */
    func testFramesPerSecond_givenAdaptiveSyncDisplay() {
        let reader = VitalRefreshRateReader()
        let frameInfoProvider = FrameInfoProviderMock(target: self, selector: .noOp)
        frameInfoProvider.maximumDeviceFramesPerSecond = 120

        // first frame recorded
        frameInfoProvider.currentFrameTimestamp = 0
        frameInfoProvider.nextFrameTimestamp = 0.008
        let firstFps = reader.framesPerSecond(provider: frameInfoProvider)
        XCTAssertNil(firstFps)

        // second frame recorded
        frameInfoProvider.currentFrameTimestamp = 0.008
        frameInfoProvider.nextFrameTimestamp = 0.033
        let secondFps = reader.framesPerSecond(provider: frameInfoProvider)
        XCTAssertEqual(secondFps, 60)

        // third frame recorded
        frameInfoProvider.currentFrameTimestamp = 0.033
        frameInfoProvider.nextFrameTimestamp = 0.043
        let thirdFps = reader.framesPerSecond(provider: frameInfoProvider)
        XCTAssertEqual(thirdFps, 60)

        // fourth frame recorded
        frameInfoProvider.currentFrameTimestamp = 0.043
        let fourthFps = reader.framesPerSecond(provider: frameInfoProvider)
        XCTAssertEqual(fourthFps, 60)
    }

    /* Rate representation
     *
     * 0----------8ms----------------------------33ms---------43ms
     * |    8ms    |             25ms             |    10ms    |
     *                                         skipped
    */
    func testFramesPerSecond_givenAdaptiveSyncDisplayWithFreezingFrames() {
        let reader = VitalRefreshRateReader()
        let frameInfoProvider = FrameInfoProviderMock(target: self, selector: .noOp)
        frameInfoProvider.maximumDeviceFramesPerSecond = 120

        // first frame recorded
        frameInfoProvider.currentFrameTimestamp = 0
        frameInfoProvider.nextFrameTimestamp = 0.008
        let firstFps = reader.framesPerSecond(provider: frameInfoProvider)
        XCTAssertNil(firstFps)

        // second frame recorded
        frameInfoProvider.currentFrameTimestamp = 0.008
        frameInfoProvider.nextFrameTimestamp = 0.033
        let secondFps = reader.framesPerSecond(provider: frameInfoProvider)
        XCTAssertEqual(secondFps, 60)

        // third frame recorded
        frameInfoProvider.currentFrameTimestamp = 0.043
        let thirdFps = reader.framesPerSecond(provider: frameInfoProvider)
        XCTAssertEqual(thirdFps, 42.85714285714286)
    }

    /* Rate representation
     *
     * 0----------8ms---------16ms--------24ms--------32ms
     * |   6ms   |   6ms   |   6ms   |   6ms   |
     *
    */
    func testFramesPerSecond_givenAdaptiveSyncDisplayWithQuickerThanExpectedFrames() {
        let reader = VitalRefreshRateReader()
        let frameInfoProvider = FrameInfoProviderMock(target: self, selector: .noOp)
        frameInfoProvider.maximumDeviceFramesPerSecond = 120

        // first frame recorded
        frameInfoProvider.currentFrameTimestamp = 0
        frameInfoProvider.nextFrameTimestamp = 0.008
        let firstFps = reader.framesPerSecond(provider: frameInfoProvider)
        XCTAssertNil(firstFps)

        // second frame recorded
        frameInfoProvider.currentFrameTimestamp = 0.006
        frameInfoProvider.nextFrameTimestamp = 0.014
        let secondFps = reader.framesPerSecond(provider: frameInfoProvider)
        XCTAssertEqual(secondFps, 60)

        // third frame recorded
        frameInfoProvider.currentFrameTimestamp = 0.012
        let thirdFps = reader.framesPerSecond(provider: frameInfoProvider)
        XCTAssertEqual(thirdFps, 60)
    }
}
