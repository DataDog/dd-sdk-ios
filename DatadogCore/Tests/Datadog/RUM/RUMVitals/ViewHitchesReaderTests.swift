/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogRUM

final class ViewHitchesReaderTests: XCTestCase {
    /* View Hitches representation for 60FPS
     *
     * 0-------------------16ms------------------32ms----------------48ms
     * |        16ms        |        16ms        |        16ms        |
     *                                        Skipped
    */
    func testViewHitches_givenRenderLoopAt60FPS() {
        let reader = ViewHitchesReader()
        var frameInfoProvider = FrameInfoProviderMock(maximumDeviceFramesPerSecond: 60)

        // 1st frame
        frameInfoProvider.currentFrameTimestamp = 0
        frameInfoProvider.nextFrameTimestamp = 0.016
        reader.didUpdateFrame(link: frameInfoProvider)
        XCTAssertTrue(reader.hitchesDataModel.hitchesDuration == 0)
        XCTAssertTrue(reader.hitchesDataModel.hitches.count == 0)

        // 2nd frame
        frameInfoProvider.currentFrameTimestamp = 0.016
        frameInfoProvider.nextFrameTimestamp = 0.032
        reader.didUpdateFrame(link: frameInfoProvider)
        XCTAssertTrue(reader.hitchesDataModel.hitchesDuration == 0)
        XCTAssertTrue(reader.hitchesDataModel.hitches.count == 0)

        // 3rd frame
        frameInfoProvider.currentFrameTimestamp = 0.048
        frameInfoProvider.nextFrameTimestamp = 0.064
        reader.didUpdateFrame(link: frameInfoProvider)
        XCTAssertTrue(reader.hitchesDataModel.hitchesDuration == 0.016)
        XCTAssertTrue(reader.hitchesDataModel.hitches.count == 1)
    }

    /* View Hitches representation for 60FPS (acceptableLatency = 0.032 = 2 VSync)
     *
     * 0--------16ms--------32ms--------48ms--------64ms--------80ms--------96ms
     * |  16ms   |    16ms   |    16ms   |    16ms   |    16ms   |           |
     *                    Skipped                 Skipped     Skipped
    */
    func testViewHitches_givenRenderLoopAt60FPS_and2VSyncsOfAcceptableLatency() {
        let reader = ViewHitchesReader(acceptableLatency: 0.032)
        var frameInfoProvider = FrameInfoProviderMock(maximumDeviceFramesPerSecond: 60)

        // 1st frame
        frameInfoProvider.currentFrameTimestamp = 0
        frameInfoProvider.nextFrameTimestamp = 0.016
        reader.didUpdateFrame(link: frameInfoProvider)
        XCTAssertTrue(reader.hitchesDataModel.hitchesDuration == 0)
        XCTAssertTrue(reader.hitchesDataModel.hitches.count == 0)

        // 2nd frame
        frameInfoProvider.currentFrameTimestamp = 0.016
        frameInfoProvider.nextFrameTimestamp = 0.032
        reader.didUpdateFrame(link: frameInfoProvider)
        XCTAssertTrue(reader.hitchesDataModel.hitchesDuration == 0)
        XCTAssertTrue(reader.hitchesDataModel.hitches.count == 0)

        // 3rd frame
        frameInfoProvider.currentFrameTimestamp = 0.048
        frameInfoProvider.nextFrameTimestamp = 0.064
        reader.didUpdateFrame(link: frameInfoProvider)
        XCTAssertTrue(reader.hitchesDataModel.hitchesDuration == 0.016)
        XCTAssertTrue(reader.hitchesDataModel.hitches.count == 0)

        // 4th frame
        frameInfoProvider.currentFrameTimestamp = 0.096
        frameInfoProvider.nextFrameTimestamp = 0.112
        reader.didUpdateFrame(link: frameInfoProvider)
        XCTAssertTrue(reader.hitchesDataModel.hitchesDuration == 0.048)
        XCTAssertTrue(reader.hitchesDataModel.hitches.count == 1)
    }

    /* View Hitches representation for 60FPS (hangThreshold = 0.1)
     *
     * 0--------48ms--------96ms--------144ms-------192ms--------240ms------288ms
     * |  48ms   |    48ms   |    48ms   |    48ms   |    48ms   |    48ms   |
     *                    Skipped                 Skipped     Skipped
    */
    func testViewHitches_givenRenderLoopAt60FPS_andHangThreshold() {
        let reader = ViewHitchesReader(hangThreshold: 0.1)
        var frameInfoProvider = FrameInfoProviderMock(maximumDeviceFramesPerSecond: 60)

        // 1st frame
        frameInfoProvider.currentFrameTimestamp = 0
        frameInfoProvider.nextFrameTimestamp = 0.048
        reader.didUpdateFrame(link: frameInfoProvider)
        XCTAssertTrue(reader.hitchesDataModel.hitchesDuration == 0)
        XCTAssertTrue(reader.hitchesDataModel.hitches.count == 0)

        // 2nd frame
        frameInfoProvider.currentFrameTimestamp = 0.048
        frameInfoProvider.nextFrameTimestamp = 0.096
        reader.didUpdateFrame(link: frameInfoProvider)
        XCTAssertTrue(reader.hitchesDataModel.hitchesDuration == 0)
        XCTAssertTrue(reader.hitchesDataModel.hitches.count == 0)

        // 3rd frame
        frameInfoProvider.currentFrameTimestamp = 0.144
        frameInfoProvider.nextFrameTimestamp = 0.192
        reader.didUpdateFrame(link: frameInfoProvider)
        XCTAssertEqual(reader.hitchesDataModel.hitchesDuration, 0.048, accuracy: 0.001)
        XCTAssertTrue(reader.hitchesDataModel.hitches.count == 0)

        // 4th frame
        frameInfoProvider.currentFrameTimestamp = 0.288
        frameInfoProvider.nextFrameTimestamp = 0.336
        reader.didUpdateFrame(link: frameInfoProvider)
        XCTAssertEqual(reader.hitchesDataModel.hitchesDuration, 0.144, accuracy: 0.001)
        XCTAssertTrue(reader.hitchesDataModel.hitches.count == 1)
    }

    /* View Hitches representation for 120FPS
     *
     * 0----------8ms---------16ms--------24ms--------32ms
     * |    8ms    |    8ms    |    8ms    |    8ms    |
     *                                  Skipped
    */
    func testViewHitches_givenRenderLoopAt120FPS() {
        let reader = ViewHitchesReader()
        var frameInfoProvider = FrameInfoProviderMock(maximumDeviceFramesPerSecond: 120)

        // 1st frame
        frameInfoProvider.currentFrameTimestamp = 0
        frameInfoProvider.nextFrameTimestamp = 0.008
        reader.didUpdateFrame(link: frameInfoProvider)
        XCTAssertTrue(reader.hitchesDataModel.hitchesDuration == 0)
        XCTAssertTrue(reader.hitchesDataModel.hitches.count == 0)

        // 2nd frame
        frameInfoProvider.currentFrameTimestamp = 0.008
        frameInfoProvider.nextFrameTimestamp = 0.016
        reader.didUpdateFrame(link: frameInfoProvider)
        XCTAssertTrue(reader.hitchesDataModel.hitchesDuration == 0)
        XCTAssertTrue(reader.hitchesDataModel.hitches.count == 0)

        // 3rd frame
        frameInfoProvider.currentFrameTimestamp = 0.016
        frameInfoProvider.nextFrameTimestamp = 0.024
        reader.didUpdateFrame(link: frameInfoProvider)
        XCTAssertTrue(reader.hitchesDataModel.hitchesDuration == 0)
        XCTAssertTrue(reader.hitchesDataModel.hitches.count == 0)

        // 4th frame
        frameInfoProvider.currentFrameTimestamp = 0.032
        frameInfoProvider.nextFrameTimestamp = 0.04
        reader.didUpdateFrame(link: frameInfoProvider)
        XCTAssertTrue(reader.hitchesDataModel.hitchesDuration == 0.008)
        XCTAssertTrue(reader.hitchesDataModel.hitches.count == 1)
    }

    /* View Hitches representation for dynamic frame rate
     *
     * 0----------8ms----------------------------33ms---------43ms
     * |    8ms    |             25ms             |    10ms    |
    */
    func testViewHitches_givenAdaptiveSyncDisplay() {
        let reader = ViewHitchesReader()
        var frameInfoProvider = FrameInfoProviderMock(maximumDeviceFramesPerSecond: 120)

        // 1st frame
        frameInfoProvider.currentFrameTimestamp = 0
        frameInfoProvider.nextFrameTimestamp = 0.008
        reader.didUpdateFrame(link: frameInfoProvider)
        XCTAssertTrue(reader.hitchesDataModel.hitchesDuration == 0)
        XCTAssertTrue(reader.hitchesDataModel.hitches.count == 0)

        // 2nd frame
        frameInfoProvider.currentFrameTimestamp = 0.008
        frameInfoProvider.nextFrameTimestamp = 0.033
        reader.didUpdateFrame(link: frameInfoProvider)
        XCTAssertTrue(reader.hitchesDataModel.hitchesDuration == 0)
        XCTAssertTrue(reader.hitchesDataModel.hitches.count == 0)

        // 3rd frame
        frameInfoProvider.currentFrameTimestamp = 0.033
        frameInfoProvider.nextFrameTimestamp = 0.043
        reader.didUpdateFrame(link: frameInfoProvider)
        XCTAssertTrue(reader.hitchesDataModel.hitchesDuration == 0)
        XCTAssertTrue(reader.hitchesDataModel.hitches.count == 0)

        // 4th frame
        frameInfoProvider.currentFrameTimestamp = 0.043
        frameInfoProvider.nextFrameTimestamp = 0.051
        reader.didUpdateFrame(link: frameInfoProvider)
        XCTAssertTrue(reader.hitchesDataModel.hitchesDuration == 0)
        XCTAssertTrue(reader.hitchesDataModel.hitches.count == 0)
    }

    /* View Hitches representation for dynamic frame rate
     *
     * 0----------8ms----------------------------33ms---------41ms
     * |    8ms    |             25ms             |     8ms    |
     *                                         skipped
    */
    func testViewHitches_givenAdaptiveSyncDisplayWithViewHitches() {
        let reader = ViewHitchesReader()
        var frameInfoProvider = FrameInfoProviderMock(maximumDeviceFramesPerSecond: 120)

        // 1st frame
        frameInfoProvider.currentFrameTimestamp = 0
        frameInfoProvider.nextFrameTimestamp = 0.008
        reader.didUpdateFrame(link: frameInfoProvider)
        XCTAssertTrue(reader.hitchesDataModel.hitchesDuration == 0)
        XCTAssertTrue(reader.hitchesDataModel.hitches.count == 0)

        // 2nd frame
        frameInfoProvider.currentFrameTimestamp = 0.008
        frameInfoProvider.nextFrameTimestamp = 0.033
        reader.didUpdateFrame(link: frameInfoProvider)
        XCTAssertTrue(reader.hitchesDataModel.hitchesDuration == 0)
        XCTAssertTrue(reader.hitchesDataModel.hitches.count == 0)

        // 3rd frame
        frameInfoProvider.currentFrameTimestamp = 0.041
        frameInfoProvider.nextFrameTimestamp = 0.049
        reader.didUpdateFrame(link: frameInfoProvider)
        XCTAssertTrue(reader.hitchesDataModel.hitchesDuration == 0.008)
        XCTAssertTrue(reader.hitchesDataModel.hitches.count == 1)
    }

    /* View Hitches representation for dynamic frame rate
     *
     * 0----------8ms---------16ms--------24ms--------32ms
     * |   6ms   |   6ms   |   6ms   |   6ms   |
     *
    */
    func testViewHitches_givenAdaptiveSyncDisplayWithQuickerThanExpectedFrames() {
        let reader = ViewHitchesReader()
        var frameInfoProvider = FrameInfoProviderMock(maximumDeviceFramesPerSecond: 120)

        // 1st frame
        frameInfoProvider.currentFrameTimestamp = 0
        frameInfoProvider.nextFrameTimestamp = 0.008
        reader.didUpdateFrame(link: frameInfoProvider)
        XCTAssertTrue(reader.hitchesDataModel.hitchesDuration == 0)
        XCTAssertTrue(reader.hitchesDataModel.hitches.count == 0)

        // 2nd frame
        frameInfoProvider.currentFrameTimestamp = 0.006
        frameInfoProvider.nextFrameTimestamp = 0.014
        reader.didUpdateFrame(link: frameInfoProvider)
        XCTAssertTrue(reader.hitchesDataModel.hitchesDuration == 0)
        XCTAssertTrue(reader.hitchesDataModel.hitches.count == 0)

        // 3rd frame
        frameInfoProvider.currentFrameTimestamp = 0.012
        frameInfoProvider.nextFrameTimestamp = 0.020
        reader.didUpdateFrame(link: frameInfoProvider)
        XCTAssertTrue(reader.hitchesDataModel.hitchesDuration == 0)
        XCTAssertTrue(reader.hitchesDataModel.hitches.count == 0)
    }
}
