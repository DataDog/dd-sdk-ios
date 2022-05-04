/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import UIKit
@testable import Datadog

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
}
