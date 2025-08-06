/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogInternal

 final class DeterministicSamplerTests: XCTestCase {
     func testWithHardcodedTraceId_itReturnsExpectedDecision() {
         XCTAssertEqual(DeterministicSampler(seed: 4_815_162_342, samplingRate: 55.9).sample(), false)
         XCTAssertEqual(DeterministicSampler(seed: 4_815_162_342, samplingRate: 56.0).sample(), true)

         XCTAssertEqual(DeterministicSampler(seed: 1_415_926_535_897_932_384, samplingRate: 90.5).sample(), false)
         XCTAssertEqual(DeterministicSampler(seed: 1_415_926_535_897_932_384, samplingRate: 90.6).sample(), true)

         XCTAssertEqual(DeterministicSampler(seed: 718_281_828_459_045_235, samplingRate: 7.4).sample(), false)
         XCTAssertEqual(DeterministicSampler(seed: 718_281_828_459_045_235, samplingRate: 7.5).sample(), true)

         XCTAssertEqual(DeterministicSampler(seed: 41_421_356_237_309_504, samplingRate: 32.1).sample(), false)
         XCTAssertEqual(DeterministicSampler(seed: 41_421_356_237_309_504, samplingRate: 32.2).sample(), true)

         XCTAssertEqual(DeterministicSampler(seed: 6_180_339_887_498_948_482, samplingRate: 68.2).sample(), false)
         XCTAssertEqual(DeterministicSampler(seed: 6_180_339_887_498_948_482, samplingRate: 68.3).sample(), true)
     }
 }
