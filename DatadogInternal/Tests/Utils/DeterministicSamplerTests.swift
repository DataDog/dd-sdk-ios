/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogInternal

 class DeterministicSamplerTests: XCTestCase {
     private let measurements = 0..<128

     func testWhenInitWithNotSampled_itAlwaysReturnsNotSampled() {
         // Given
         let fakeSampleRate = Float.random(in: 0.0..<100.0)
         let sampler = DeterministicSampler(shouldSample: false, samplingRate: fakeSampleRate)

         // When
         var notSampledCount = 0
         measurements.forEach { _ in
             notSampledCount += sampler.sample() ? 0 : 1
         }

         // Then
         XCTAssertEqual(notSampledCount, measurements.count)
     }

     func testWhenInitWithIsSampled_itAlwaysReturnsIsSampled() {
         // Given
         let fakeSampleRate = Float.random(in: 0.0..<100.0)
         let sampler = DeterministicSampler(shouldSample: true, samplingRate: fakeSampleRate)

         // When
         var isSampledCount = 0
         measurements.forEach { _ in
             isSampledCount += sampler.sample() ? 1 : 0
         }

         // Then
         XCTAssertEqual(isSampledCount, measurements.count)
     }

     func testWithHardcodedTraceId_itReturnsExpectedDecision() {
         XCTAssertEqual(DeterministicSampler(baseId: 4_815_162_342, samplingRate: 55.9).sample(), false)
         XCTAssertEqual(DeterministicSampler(baseId: 4_815_162_342, samplingRate: 56.0).sample(), true)

         XCTAssertEqual(DeterministicSampler(baseId: 1_415_926_535_897_932_384, samplingRate: 90.5).sample(), false)
         XCTAssertEqual(DeterministicSampler(baseId: 1_415_926_535_897_932_384, samplingRate: 90.6).sample(), true)

         XCTAssertEqual(DeterministicSampler(baseId: 718_281_828_459_045_235, samplingRate: 7.4).sample(), false)
         XCTAssertEqual(DeterministicSampler(baseId: 718_281_828_459_045_235, samplingRate: 7.5).sample(), true)

         XCTAssertEqual(DeterministicSampler(baseId: 41_421_356_237_309_504, samplingRate: 32.1).sample(), false)
         XCTAssertEqual(DeterministicSampler(baseId: 41_421_356_237_309_504, samplingRate: 32.2).sample(), true)

         XCTAssertEqual(DeterministicSampler(baseId: 6_180_339_887_498_948_482, samplingRate: 68.2).sample(), false)
         XCTAssertEqual(DeterministicSampler(baseId: 6_180_339_887_498_948_482, samplingRate: 68.3).sample(), true)
     }
 }
