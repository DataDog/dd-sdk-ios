/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import DatadogMachProfiler
import TestUtilities
@testable import DatadogProfiling

final class ProfilerFeatureTests: XCTestCase {
    private let requestBuilder: FeatureRequestBuilder = FeatureRequestBuilderMock()
    private let messageReceiver: FeatureMessageReceiver = NOPFeatureMessageReceiver()

    private var userDefaults: UserDefaults! //swiftlint:disable:this implicitly_unwrapped_optional
    private let suiteName = "ProfilerFeatureTests-\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        super.tearDown()
    }

    func testInit_setsIsEnabledFlagToTrue() {
        // Given
        XCTAssertNil(userDefaults.value(forKey: DD_PROFILING_IS_ENABLED_KEY))

        // When
        _ = ProfilerFeature(
            requestBuilder: requestBuilder,
            messageReceiver: messageReceiver,
            sampleRate: .maxSampleRate,
            userDefaults: userDefaults
        )

        // Then
        XCTAssertEqual(userDefaults.value(forKey: DD_PROFILING_IS_ENABLED_KEY) as? Bool, true)
    }

    func testInit_setsSampleRateValue() {
        // Given
        userDefaults.removeObject(forKey: DD_PROFILING_SAMPLE_RATE_KEY)
        let newSampleRate: SampleRate = 23

        // When
        _ = ProfilerFeature(
            requestBuilder: requestBuilder,
            messageReceiver: messageReceiver,
            sampleRate: newSampleRate,
            userDefaults: userDefaults
        )

        // Then
        XCTAssertEqual(userDefaults.value(forKey: DD_PROFILING_SAMPLE_RATE_KEY) as? SampleRate, newSampleRate)
    }

    func testInit_overridesPreviousSampleRate_whenNewSampleRateIsLower() {
        // Given
        let previousSampleRate: SampleRate = 80
        let lowerSampleRate: SampleRate = 20

        userDefaults.setValue(previousSampleRate, forKey: DD_PROFILING_SAMPLE_RATE_KEY)
        XCTAssertEqual(userDefaults.value(forKey: DD_PROFILING_SAMPLE_RATE_KEY) as? SampleRate, previousSampleRate)

        // When
        _ = ProfilerFeature(
            requestBuilder: requestBuilder,
            messageReceiver: messageReceiver,
            sampleRate: lowerSampleRate,
            userDefaults: userDefaults
        )

        // Then
        XCTAssertEqual(userDefaults.value(forKey: DD_PROFILING_SAMPLE_RATE_KEY) as? SampleRate, lowerSampleRate)
    }

    func testInit_keepsPreviousSampleRate_whenNewSampleRateIsHigher() {
        // Given
        let previousSampleRate: SampleRate = 20
        let higherSampleRate: SampleRate = 80

        userDefaults.setValue(previousSampleRate, forKey: DD_PROFILING_SAMPLE_RATE_KEY)
        XCTAssertEqual(userDefaults.value(forKey: DD_PROFILING_SAMPLE_RATE_KEY) as? SampleRate, previousSampleRate)

        // When
        _ = ProfilerFeature(
            requestBuilder: requestBuilder,
            messageReceiver: messageReceiver,
            sampleRate: higherSampleRate,
            userDefaults: userDefaults
        )

        // Then
        XCTAssertEqual(userDefaults.value(forKey: DD_PROFILING_SAMPLE_RATE_KEY) as? SampleRate, previousSampleRate)
    }

    func testInit_usesProvidedUserDefaultsInstance() {
        // Given
        let otherSuiteName = "ProfilerFeatureTests-other-\(UUID().uuidString)"
        let otherUserDefaults = UserDefaults(suiteName: otherSuiteName)!
        otherUserDefaults.removePersistentDomain(forName: otherSuiteName)

        otherUserDefaults.setValue(false, forKey: DD_PROFILING_IS_ENABLED_KEY)
        otherUserDefaults.setValue(SampleRate.maxSampleRate, forKey: DD_PROFILING_SAMPLE_RATE_KEY)

        // When
        _ = ProfilerFeature(
            requestBuilder: requestBuilder,
            messageReceiver: messageReceiver,
            sampleRate: 10,
            userDefaults: userDefaults
        )

        XCTAssertEqual(userDefaults.value(forKey: DD_PROFILING_IS_ENABLED_KEY) as? Bool, true)
        XCTAssertEqual(userDefaults.value(forKey: DD_PROFILING_SAMPLE_RATE_KEY) as? SampleRate, 10)

        // `otherUserDefaults` was not touched by ProfilerFeature
        XCTAssertEqual(otherUserDefaults.value(forKey: DD_PROFILING_IS_ENABLED_KEY) as? Bool, false)
        XCTAssertEqual(otherUserDefaults.value(forKey: DD_PROFILING_SAMPLE_RATE_KEY) as? SampleRate, SampleRate.maxSampleRate)
    }
}
