/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities
@testable import DatadogCore

private struct FeatureAMock: DatadogRemoteFeature {
    static let name: String = "feature-a"
    var requestBuilder: FeatureRequestBuilder = FeatureRequestBuilderMock()
    var messageReceiver: FeatureMessageReceiver = NOPFeatureMessageReceiver()
    var performanceOverride: DatadogInternal.PerformancePresetOverride?
}

private struct FeatureBMock: DatadogRemoteFeature {
    static let name: String = "feature-b"
    var requestBuilder: FeatureRequestBuilder = FeatureRequestBuilderMock()
    var messageReceiver: FeatureMessageReceiver = NOPFeatureMessageReceiver()
    var performanceOverride: DatadogInternal.PerformancePresetOverride?
}

class DatadogCore_FeatureDataStoreTests: XCTestCase {
    func testGivenTwoFeaturesRegistered_whenWritingToTheirDataStore_eachStoreIsUnique() async throws {
        let core = DatadogCore(
            directory: temporaryCoreDirectory.create(),
            dateProvider: SystemDateProvider(),
            initialConsent: .mockRandom(),
            performance: .mockRandom(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            maxBatchesPerUpload: .mockAny(),
            backgroundTasksEnabled: .mockAny()
        )

        // Given
        try core.register(feature: FeatureAMock())
        try core.register(feature: FeatureBMock())

        // When
        let scopeA = core.scope(for: FeatureAMock.self)
        let scopeB = core.scope(for: FeatureBMock.self)

        let commonKey = "key"
        scopeA.dataStore.setValue("feature A data".utf8Data, forKey: commonKey)
        scopeB.dataStore.setValue("feature B data".utf8Data, forKey: commonKey)

        // Then
        (scopeA.dataStore as? FeatureDataStore)?.flush()
        (scopeB.dataStore as? FeatureDataStore)?.flush()

        let resultA = await scopeA.dataStore.value(forKey: commonKey)
        let resultB = await scopeB.dataStore.value(forKey: commonKey)

        XCTAssertEqual(resultA.data()?.utf8String, "feature A data")
        XCTAssertEqual(resultB.data()?.utf8String, "feature B data")

        await core.flushAndTearDown()
        temporaryCoreDirectory.delete()
    }

    func testGivenFeatureRegisteredToTwoCoreInstances_whenWritingToDataStore_eachInstanceIsUnique() async throws {
        let coreDirectory1 = temporaryUniqueCoreDirectory().create()
        let coreDirectory2 = temporaryUniqueCoreDirectory().create()
        let core1 = DatadogCore(
            directory: coreDirectory1,
            dateProvider: SystemDateProvider(),
            initialConsent: .mockRandom(),
            performance: .mockRandom(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            maxBatchesPerUpload: .mockAny(),
            backgroundTasksEnabled: .mockAny()
        )
        let core2 = DatadogCore(
            directory: coreDirectory2,
            dateProvider: SystemDateProvider(),
            initialConsent: .mockRandom(),
            performance: .mockRandom(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            maxBatchesPerUpload: .mockAny(),
            backgroundTasksEnabled: .mockAny()
        )

        // Given
        try core1.register(feature: FeatureAMock())
        try core2.register(feature: FeatureAMock())

        // When
        let scope1 = core1.scope(for: FeatureAMock.self)
        let scope2 = core2.scope(for: FeatureAMock.self)

        let commonKey = "key"
        scope1.dataStore.setValue("feature data in core 1".utf8Data, forKey: commonKey)
        scope2.dataStore.setValue("feature data in core 2".utf8Data, forKey: commonKey)

        // Then
        (scope1.dataStore as? FeatureDataStore)?.flush()
        (scope2.dataStore as? FeatureDataStore)?.flush()

        let result1 = await scope1.dataStore.value(forKey: commonKey)
        let result2 = await scope2.dataStore.value(forKey: commonKey)

        XCTAssertEqual(result1.data()?.utf8String, "feature data in core 1")
        XCTAssertEqual(result2.data()?.utf8String, "feature data in core 2")

        await core1.flushAndTearDown()
        await core2.flushAndTearDown()
        coreDirectory1.delete()
        coreDirectory2.delete()
    }
}
