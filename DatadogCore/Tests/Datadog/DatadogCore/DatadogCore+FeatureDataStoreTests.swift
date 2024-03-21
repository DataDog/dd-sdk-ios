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
}

private struct FeatureBMock: DatadogRemoteFeature {
    static let name: String = "feature-b"
    var requestBuilder: FeatureRequestBuilder = FeatureRequestBuilderMock()
    var messageReceiver: FeatureMessageReceiver = NOPFeatureMessageReceiver()
}

class DatadogCore_FeatureDataStoreTests: XCTestCase {
    func testGivenTwoFeaturesRegistered_whenWritingToTheirDataStore_eachStoreIsUnique() throws {
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
        defer {
            core.flushAndTearDown()
            temporaryCoreDirectory.delete()
        }

        // Given
        try core.register(feature: FeatureAMock())
        try core.register(feature: FeatureBMock())

        // When
        let scopeA = try XCTUnwrap(core.scope(for: FeatureAMock.name))
        let scopeB = try XCTUnwrap(core.scope(for: FeatureBMock.name))

        let commonKey = "key"
        scopeA.dataStore.setValue("feature A data".utf8Data, forKey: commonKey)
        scopeB.dataStore.setValue("feature B data".utf8Data, forKey: commonKey)

        // Then
        var dataInA: Data?
        var dataInB: Data?
        scopeA.dataStore.value(forKey: commonKey) { dataInA = $0.data() }
        scopeB.dataStore.value(forKey: commonKey) { dataInB = $0.data() }

        (scopeA.dataStore as? FeatureDataStore)?.flush()
        (scopeB.dataStore as? FeatureDataStore)?.flush()

        XCTAssertEqual(dataInA?.utf8String, "feature A data")
        XCTAssertEqual(dataInB?.utf8String, "feature B data")
    }

    func testGivenFeatureRegisteredToTwoCoreInstances_whenWritingToDataStore_eachInstanceIsUnique() throws {
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
        defer {
            core1.flushAndTearDown()
            core2.flushAndTearDown()
            coreDirectory1.delete()
            coreDirectory2.delete()
        }

        // Given
        try core1.register(feature: FeatureAMock())
        try core2.register(feature: FeatureAMock())

        // When
        let scope1 = try XCTUnwrap(core1.scope(for: FeatureAMock.name))
        let scope2 = try XCTUnwrap(core2.scope(for: FeatureAMock.name))

        let commonKey = "key"
        scope1.dataStore.setValue("feature data in core 1".utf8Data, forKey: commonKey)
        scope2.dataStore.setValue("feature data in core 2".utf8Data, forKey: commonKey)

        // Then
        var dataIn1: Data?
        var dataIn2: Data?
        scope1.dataStore.value(forKey: commonKey) { dataIn1 = $0.data() }
        scope2.dataStore.value(forKey: commonKey) { dataIn2 = $0.data() }

        (scope1.dataStore as? FeatureDataStore)?.flush()
        (scope2.dataStore as? FeatureDataStore)?.flush()

        XCTAssertEqual(dataIn1?.utf8String, "feature data in core 1")
        XCTAssertEqual(dataIn2?.utf8String, "feature data in core 2")
    }
}
