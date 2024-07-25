/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import UIKit
@testable import DatadogRUM

class VitalRefreshRateReaderTests: XCTestCase {
    private let mockNotificationCenter = NotificationCenter()

    func testWhenMainThreadOverheadGoesUp_itMeasuresLowerRefreshRate() throws {
        let reader = VitalRefreshRateReader(notificationCenter: mockNotificationCenter)
        let targetSamplesCount = 30

        /// Runs given work on the main thread until `condition` is met, then calls `completion`.
        func run(mainThreadWork: @escaping () -> Void, until condition: @escaping () -> Bool, completion: @escaping () -> Void) {
            if !condition() {
                mainThreadWork()
                DispatchQueue.main.async { // schedule to next runloop
                    run(mainThreadWork: mainThreadWork, until: condition, completion: completion)
                }
            } else {
                completion()
            }
        }

        /// Records `targetSamplesCount` samples into `measure` by running given work on the main thread.
        func record(_ measure: VitalPublisher, mainThreadWork: @escaping () -> Void) {
            let completion = expectation(description: "Complete measurement")
            reader.register(measure)

            run(
                mainThreadWork: mainThreadWork,
                until: { measure.currentValue.sampleCount >= targetSamplesCount },
                completion: {
                    reader.unregister(measure)
                    completion.fulfill()
                }
            )

            let result = XCTWaiter().wait(for: [completion], timeout: 10)

            switch result {
            case .completed:
                break // all good
            case .timedOut:
                XCTFail("VitalRefreshRateReader exceededed timeout with \(measure.currentValue.sampleCount)/\(targetSamplesCount) recorded samples")
            default:
                XCTFail("XCTWaiter unexpected failure: \(result)")
            }
        }

        // Given
        let lowOverhead = { /* no-op */ } // no overhead in succeeding runloop runs
        let lowOverheadMeasure = VitalPublisher(initialValue: VitalInfo())

        var highOverheadRunCount = 0
        let highOverhead = { highOverheadRunCount += 1; Thread.sleep(forTimeInterval: 0.02) } // 0.02 overhead in succeeding runloop runs
        let highOverheadMeasure = VitalPublisher(initialValue: VitalInfo())

        // When
        record(lowOverheadMeasure, mainThreadWork: lowOverhead)
        record(highOverheadMeasure, mainThreadWork: highOverhead)

        // Then
        let expectedHighFPS = try XCTUnwrap(lowOverheadMeasure.currentValue.meanValue)
        let expectedLowFPS = try XCTUnwrap(highOverheadMeasure.currentValue.meanValue)
        XCTAssertGreaterThan(expectedHighFPS, expectedLowFPS, "It must measure higher FPS for lower main thread overhead (hight overhead run count: \(highOverheadRunCount))")
    }

    func testAppStateHandling() {
        let reader = VitalRefreshRateReader(notificationCenter: mockNotificationCenter)
        let registrar = VitalPublisher(initialValue: VitalInfo())

        mockNotificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        mockNotificationCenter.post(name: UIApplication.willResignActiveNotification, object: nil)
        reader.register(registrar)

        let expectation1 = expectation(description: "async expectation for first observer")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            expectation1.fulfill()
        }

        waitForExpectations(timeout: 1.0) { _ in }
        XCTAssertEqual(registrar.currentValue.sampleCount, 0)

        mockNotificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        let expectation2 = expectation(description: "async expectation for second observer")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            expectation2.fulfill()
        }

        waitForExpectations(timeout: 1.0) { _ in }
        XCTAssertGreaterThan(registrar.currentValue.sampleCount, 0)
    }

    /* Rate representation
     *
     * 0-------------------16ms------------------32ms----------------48ms
     * |        16ms        |        16ms        |        16ms        |
     *                                        Skipped
    */
    func testFramesPerSecond_given60HzFixedRateDisplay() {
        let reader = VitalRefreshRateReader(notificationCenter: mockNotificationCenter)
        var frameInfoProvider = FrameInfoProviderMock(maximumDeviceFramesPerSecond: 60)

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
        let reader = VitalRefreshRateReader(notificationCenter: mockNotificationCenter)
        var frameInfoProvider = FrameInfoProviderMock(maximumDeviceFramesPerSecond: 120)

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
        let reader = VitalRefreshRateReader(notificationCenter: mockNotificationCenter)
        var frameInfoProvider = FrameInfoProviderMock(maximumDeviceFramesPerSecond: 120)

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
        let reader = VitalRefreshRateReader(notificationCenter: mockNotificationCenter)
        var frameInfoProvider = FrameInfoProviderMock(maximumDeviceFramesPerSecond: 120)

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
        let reader = VitalRefreshRateReader(notificationCenter: mockNotificationCenter)
        var frameInfoProvider = FrameInfoProviderMock(maximumDeviceFramesPerSecond: 120)

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

struct FrameInfoProviderMock: FrameInfoProvider {
    var maximumDeviceFramesPerSecond: Int = 60
    var currentFrameTimestamp: CFTimeInterval = 0
    var nextFrameTimestamp: CFTimeInterval = 0
}
