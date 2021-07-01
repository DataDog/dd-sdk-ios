/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class VitalInfoSamplerTests: XCTestCase {
    func testItDoesSamplePeriodically() {
        let mockCPUReader = SamplingBasedVitalReaderMock()
        let mockMemoryReader = SamplingBasedVitalReaderMock()
        let mockRefreshRateReader = ContinuousVitalReaderMock()

        let sampler = VitalInfoSampler(
            cpuReader: mockCPUReader,
            memoryReader: mockMemoryReader,
            refreshRateReader: mockRefreshRateReader,
            frequency: 0.1
        )

        mockCPUReader.vitalData = 123.0
        mockMemoryReader.vitalData = 321.0
        mockRefreshRateReader.vitalInfo = {
            var info = VitalInfo()
            info.addSample(666.0)
            return info
        }()

        let expectation = expectation(description: "sampling expectation")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }

        waitForExpectations(timeout: 0.5) { _ in
            XCTAssertEqual(sampler.cpu.meanValue, 123.0)
            XCTAssertGreaterThan(sampler.cpu.sampleCount, 1)
            XCTAssertEqual(sampler.memory.meanValue, 321.0)
            XCTAssertGreaterThan(sampler.memory.sampleCount, 1)
            XCTAssertEqual(sampler.refreshRate.meanValue, 666.0)
        }
    }
}
