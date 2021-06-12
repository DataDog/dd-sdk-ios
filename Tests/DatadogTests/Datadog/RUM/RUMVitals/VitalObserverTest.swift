/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import Datadog

class VitalObserverTest: XCTestCase {
    func testItUpdatesVitalInfoOnFirstValue() {
        let randomOldValue = Double.random(in: -65_536.0...65_536.0)
        let randomValue = Double.random(in: -65_536.0...65_536.0)
        let notifyExpectation = expectation(description: "Notify vital info")
        let mockListener = VitalListenerMock()
        let testedObserver = VitalObserver(listener: mockListener)
        mockListener.onVitalInfoUpdate = { vitalInfo in
            XCTAssertEqual(vitalInfo.minValue, randomValue)
            XCTAssertEqual(vitalInfo.maxValue, randomValue)
            XCTAssertEqual(vitalInfo.meanValue, randomValue)
            XCTAssertEqual(vitalInfo.sampleCount, 1)
            notifyExpectation.fulfill()
        }

        // When
        testedObserver.onValueChanged(oldValue: randomOldValue, newValue: randomValue)

        // Then
        wait(for: [notifyExpectation], timeout: 0.5, enforceOrder: true)
    }

    func testItUpdatesVitalInfoOnMultipleValue() {
        let randomOldValue = Double.random(in: -65_536.0...65_536.0)
        let randomValue1 = Double.random(in: -65_536.0...65_536.0)
        let randomValue2 = Double.random(in: -65_536.0...65_536.0)
        let randomValue3 = Double.random(in: -65_536.0...65_536.0)
        let notifyExpectation1 = expectation(description: "Notify vital info 1")
        let notifyExpectation2 = expectation(description: "Notify vital info 2")
        let notifyExpectation3 = expectation(description: "Notify vital info 3")
        let mockListener = VitalListenerMock()
        let testedObserver = VitalObserver(listener: mockListener)

        // When
        mockListener.onVitalInfoUpdate = { vitalInfo in
            XCTAssertEqual(vitalInfo.minValue, randomValue1)
            XCTAssertEqual(vitalInfo.maxValue, randomValue1)
            XCTAssertEqual(vitalInfo.meanValue, randomValue1)
            XCTAssertEqual(vitalInfo.sampleCount, 1)
            notifyExpectation1.fulfill()
        }
        testedObserver.onValueChanged(oldValue: randomOldValue, newValue: randomValue1)
        mockListener.onVitalInfoUpdate = { vitalInfo in
            XCTAssertEqual(vitalInfo.minValue, min(randomValue1, randomValue2))
            XCTAssertEqual(vitalInfo.maxValue, max(randomValue1, randomValue2))
            XCTAssertEqual(vitalInfo.meanValue, (randomValue1 + randomValue2) / 2.0)
            XCTAssertEqual(vitalInfo.sampleCount, 2)
            notifyExpectation2.fulfill()
        }
        testedObserver.onValueChanged(oldValue: randomValue1, newValue: randomValue2)
        mockListener.onVitalInfoUpdate = { vitalInfo in
            XCTAssertEqual(vitalInfo.minValue, min(randomValue1, min(randomValue2, randomValue3)))
            XCTAssertEqual(vitalInfo.maxValue, max(randomValue1, max(randomValue2, randomValue3)))
            XCTAssertEqual(vitalInfo.meanValue, (randomValue1 + randomValue2 + randomValue3) / 3.0)
            XCTAssertEqual(vitalInfo.sampleCount, 3)
            notifyExpectation3.fulfill()
        }
        testedObserver.onValueChanged(oldValue: randomValue2, newValue: randomValue3)

        // Then
        wait(for: [notifyExpectation1, notifyExpectation2, notifyExpectation3], timeout: 0.5, enforceOrder: true)
    }
}
