/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogProfiler

internal struct MockInstrumentConfiguration: InstrumentConfiguration {
    let instrument: MockInstrument

    func createInstrument(with profilerConfiguration: ProfilerConfiguration) -> Any {
        return instrument
    }
}

internal class MockInstrument: Instrument {
    let instrumentName: String
    let uploadResult: InstrumentUploadResult

    init(instrumentName: String, uploadResult: InstrumentUploadResult) {
        self.instrumentName = instrumentName
        self.uploadResult = uploadResult
    }

    var setUpExpectation: XCTestExpectation? = nil
    var startExpectation: XCTestExpectation? = nil
    var stopExpectation: XCTestExpectation? = nil
    var uploadResultExpectation: XCTestExpectation? = nil
    var tearDownExpectation: XCTestExpectation? = nil

    func setUp(measurementDuration: TimeInterval) { setUpExpectation?.fulfill() }
    func start() { startExpectation?.fulfill() }
    func stop() { stopExpectation?.fulfill() }
    func uploadResults(completion: @escaping (InstrumentUploadResult) -> Void) {
        uploadResultExpectation?.fulfill()
        mainQueue.asyncAfter(deadline: .now() + 0.1) { completion(self.uploadResult) }
    }
    func tearDown() { tearDownExpectation?.fulfill() }
}

final class ProfilerTests: XCTestCase {
    private let measurementDuration: TimeInterval = 1

    func testWhenAllInstrumentsSucceed() {
        let testEndExpectation = self.expectation(description: "Profiler completed")

        // Given
        let instruments: [MockInstrument] = [
            MockInstrument(instrumentName: "Instrument 1", uploadResult: .success),
            MockInstrument(instrumentName: "Instrument 2", uploadResult: .success),
            MockInstrument(instrumentName: "Instrument 3", uploadResult: .success),
        ]

        // When
        runProfiler(with: instruments) { profilerResult in
            // Then
            switch profilerResult {
            case .success(let summary):
                XCTAssertEqual(summary, ["Instrument 1 - OK", "Instrument 2 - OK", "Instrument 3 - OK"])
            case .failure:
                XCTFail("Expected `.success()`")
            }
            testEndExpectation.fulfill()
        }

        waitForExpectations(timeout: measurementDuration * 2)
    }

    func testWhenSomeInstrumentsFail() {
        let testEndExpectation = self.expectation(description: "Profiler completed")

        // Given
        let instruments: [MockInstrument] = [
            MockInstrument(instrumentName: "Instrument 1", uploadResult: .success),
            MockInstrument(instrumentName: "Instrument 2", uploadResult: .error("2nd instrument error")),
            MockInstrument(instrumentName: "Instrument 3", uploadResult: .error("3rd instrument error")),
            MockInstrument(instrumentName: "Instrument 4", uploadResult: .success),
        ]

        // When
        runProfiler(with: instruments) { profilerResult in
            // Then
            switch profilerResult {
            case .failure(let summary):
                XCTAssertEqual(
                    summary,
                    [
                        "Instrument 1 - OK",
                        "Instrument 2 - error: 2nd instrument error",
                        "Instrument 3 - error: 3rd instrument error",
                        "Instrument 4 - OK",
                    ]
                )
            case .success:
                XCTFail("Expected `.failure()`")
            }
            testEndExpectation.fulfill()
        }

        waitForExpectations(timeout: measurementDuration * 2)
    }

    private func runProfiler(with instruments: [MockInstrument], completion: (ProfileUploadResult) -> Void) {
        let setUpExpectation = self.expectation(description: "Instrument: setUpExpectation")
        let startExpectation = self.expectation(description: "Instrument: startExpectation")
        let stopExpectation = self.expectation(description: "Instrument: stopExpectation")
        let uploadResultExpectation = self.expectation(description: "Instrument: uploadResultExpectation")
        let tearDownExpectation = self.expectation(description: "Instrument: tearDownExpectation")
        let profilerTearDownExpectation = self.expectation(description: "Profiler: tearDownExpectation")

        setUpExpectation.expectedFulfillmentCount = instruments.count
        startExpectation.expectedFulfillmentCount = instruments.count
        stopExpectation.expectedFulfillmentCount = instruments.count
        uploadResultExpectation.expectedFulfillmentCount = instruments.count
        tearDownExpectation.expectedFulfillmentCount = instruments.count

        for instrument in instruments {
            instrument.setUpExpectation = setUpExpectation
            instrument.startExpectation = startExpectation
            instrument.stopExpectation = stopExpectation
            instrument.uploadResultExpectation = uploadResultExpectation
            instrument.tearDownExpectation = tearDownExpectation
        }

        let instrumentConfigurations: [InstrumentConfiguration] = instruments.map { MockInstrumentConfiguration(instrument: $0) }
        var result: ProfileUploadResult?

        // Given
        Profiler.setUp(
            with: ProfilerConfiguration(apiKey: "api-key"),
            instruments: instrumentConfigurations,
            expectedMeasurementDuration: measurementDuration
        )
        wait(for: [setUpExpectation], timeout: 1)

        // When
        Profiler.instance?.start(stopAndTearDownAutomatically: {
            result = $0
            profilerTearDownExpectation.fulfill()
        })
        wait(
            for: [startExpectation, stopExpectation, uploadResultExpectation, tearDownExpectation, profilerTearDownExpectation],
            timeout: measurementDuration * 2,
            enforceOrder: true
        )

        // Then
        completion(result!)
    }
}
