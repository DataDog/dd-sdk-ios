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

/// Cross-SDK test vectors for `DeterministicSampler` — derived from dd-trace-go via browser SDK sampler.spec.ts.
final class KnuthFactorTests: XCTestCase {
    /// Vectors that must produce `true` (sampled).
    func testCrossSDKVectors_itReturnsSampledTrue() {
        XCTAssertTrue(DeterministicSampler(seed: 5_577_006_791_947_779_410, samplingRate: 94.0509).sample(), "Vector 1: expected sampled=true")
        XCTAssertTrue(DeterministicSampler(seed: 15_352_856_648_520_921_629, samplingRate: 43.7714).sample(), "Vector 2: expected sampled=true")
        XCTAssertTrue(DeterministicSampler(seed: 3_916_589_616_287_113_937, samplingRate: 68.6823).sample(), "Vector 3: expected sampled=true")
        XCTAssertTrue(DeterministicSampler(seed: 894_385_949_183_117_216, samplingRate: 30.0912).sample(), "Vector 4: expected sampled=true")
        XCTAssertTrue(DeterministicSampler(seed: 12_156_940_908_066_221_323, samplingRate: 46.889).sample(), "Vector 5: expected sampled=true")
    }

    /// Vectors that must produce `false` (not sampled).
    func testCrossSDKVectors_itReturnsSampledFalse() {
        XCTAssertFalse(DeterministicSampler(seed: 9_828_766_684_487_745_566, samplingRate: 15.6519).sample(), "Vector 6: expected sampled=false")
        XCTAssertFalse(DeterministicSampler(seed: 4_751_997_750_760_398_084, samplingRate: 81.364).sample(), "Vector 7: expected sampled=false")
        XCTAssertFalse(DeterministicSampler(seed: 11_199_607_447_739_267_382, samplingRate: 38.0657).sample(), "Vector 8: expected sampled=false")
        XCTAssertFalse(DeterministicSampler(seed: 6_263_450_610_539_110_790, samplingRate: 21.8553).sample(), "Vector 9: expected sampled=false")
        XCTAssertFalse(DeterministicSampler(seed: 1_874_068_156_324_778_273, samplingRate: 36.0871).sample(), "Vector 10: expected sampled=false")
    }

    /// Boundary: rate 100.0 must always return true.
    func testBoundaryRates_itReturnsTrueForRate100() {
        XCTAssertTrue(DeterministicSampler(seed: 0, samplingRate: 100.0).sample(), "rate=100.0 must always be sampled")
        XCTAssertTrue(DeterministicSampler(seed: UInt64.max, samplingRate: 100.0).sample(), "rate=100.0 must always be sampled regardless of seed")
    }

    /// Boundary: rate 0.0 must always return false.
    func testBoundaryRates_itReturnsFalseForRate0() {
        XCTAssertFalse(DeterministicSampler(seed: 0, samplingRate: 0.0).sample(), "rate=0.0 must never be sampled")
        XCTAssertFalse(DeterministicSampler(seed: UInt64.max, samplingRate: 0.0).sample(), "rate=0.0 must never be sampled regardless of seed")
    }

    /// Determinism: same seed and rate must always return the same result.
    func testDeterminism_sameInputsAlwaysReturnSameResult() {
        let seed: UInt64 = 5_577_006_791_947_779_410
        let sampleRate: SampleRate = 50.0
        XCTAssertEqual(
            DeterministicSampler(seed: seed, samplingRate: sampleRate).sample(),
            DeterministicSampler(seed: seed, samplingRate: sampleRate).sample(),
            "Same inputs must produce same output"
        )
    }
}
