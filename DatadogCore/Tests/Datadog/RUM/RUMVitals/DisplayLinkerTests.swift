/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogRUM

final class DisplayLinkerTests: XCTestCase {
    private let mockNotificationCenter = NotificationCenter()

    func testWhenMainThreadOverheadGoesUp_itMeasuresLowerRefreshRate() throws {
        let displayLinker = DisplayLinker(notificationCenter: mockNotificationCenter)
        let reader = VitalRefreshRateReader()
        displayLinker.register(reader)
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
        XCTAssertGreaterThan(expectedHighFPS, expectedLowFPS, "It must measure higher FPS for lower main thread overhead (high overhead run count: \(highOverheadRunCount))")
    }

    func testAppStateHandlingForRefreshRateReader() {
        let displayLinker = DisplayLinker(notificationCenter: mockNotificationCenter)
        let reader = VitalRefreshRateReader()
        displayLinker.register(reader)
        let registrar = VitalPublisher(initialValue: VitalInfo())

        mockNotificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        mockNotificationCenter.post(name: UIApplication.willResignActiveNotification, object: nil)
        reader.register(registrar)

        XCTAssertFalse(reader.isActive)
        XCTAssertEqual(registrar.currentValue.sampleCount, 0)

        mockNotificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        wait(during: 0.1) {
            XCTAssertTrue(reader.isActive)
            XCTAssertGreaterThan(registrar.currentValue.sampleCount, 0)
        }
    }

    func testAppStateHandlingWithSeveralReaders() {
        let displayLinker = DisplayLinker(notificationCenter: mockNotificationCenter)
        let refreshRateReader = VitalRefreshRateReader()
        let viewHitchesReader = ViewHitchesReader()

        displayLinker.register(refreshRateReader)
        displayLinker.register(viewHitchesReader)

        wait(during: 0.1) {
            XCTAssertTrue(refreshRateReader.isActive)
            XCTAssertTrue(viewHitchesReader.isActive)
        }

        mockNotificationCenter.post(name: UIApplication.willResignActiveNotification, object: nil)

        wait(during: 0.1) {
            XCTAssertFalse(refreshRateReader.isActive)
            XCTAssertFalse(viewHitchesReader.isActive)
        }

        mockNotificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        wait(during: 0.1) {
            XCTAssertTrue(refreshRateReader.isActive)
            XCTAssertTrue(viewHitchesReader.isActive)
        }
    }

    func testDisplayLinkerRegistrationWithSeveralReaders() {
        let displayLinker = DisplayLinker(notificationCenter: mockNotificationCenter)
        let refreshRateReader = VitalRefreshRateReader()
        let viewHitchesReader = ViewHitchesReader()
        let mockReader = ViewHitchesMock()

        XCTAssertFalse(refreshRateReader.isActive)
        XCTAssertFalse(viewHitchesReader.isActive)
        XCTAssertFalse(mockReader.isActive)

        displayLinker.register(refreshRateReader)
        displayLinker.register(viewHitchesReader)
        displayLinker.register(mockReader)

        wait(during: 0.1) {
            XCTAssertTrue(refreshRateReader.isActive)
            XCTAssertTrue(viewHitchesReader.isActive)
            XCTAssertTrue(mockReader.isActive)
        }

        displayLinker.unregister(refreshRateReader)
        displayLinker.unregister(viewHitchesReader)
        displayLinker.unregister(mockReader)

        wait(during: 0.1) {
            XCTAssertFalse(refreshRateReader.isActive)
            XCTAssertFalse(viewHitchesReader.isActive)
            XCTAssertFalse(mockReader.isActive)
        }
    }
}
