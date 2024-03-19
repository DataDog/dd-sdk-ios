/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
@testable import DatadogCore

private struct RemoteFeatureMock: DatadogRemoteFeature {
    static let name: String = "remote-feature-mock"

    var requestBuilder: FeatureRequestBuilder = FeatureRequestBuilderMock()
    var messageReceiver: FeatureMessageReceiver = NOPFeatureMessageReceiver()
}

private struct FeatureMock: DatadogFeature {
    static let name: String = "feature-mock"

    var messageReceiver: FeatureMessageReceiver = NOPFeatureMessageReceiver()
}

class DatadogCore_FeatureDirectoriesTests: XCTestCase {
    private var core: DatadogCore! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        temporaryCoreDirectory.create()
        core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .mockRandom(),
            performance: .mockRandom(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            maxBatchesPerUpload: .mockRandom(min: 1, max: 100),
            backgroundTasksEnabled: .mockAny()
        )
    }

    override func tearDown() {
        core.flushAndTearDown()
        core = nil
        temporaryCoreDirectory.delete()
        super.tearDown()
    }

    func testWhenRegisteringRemoteFeature_itCreatesFeatureDirectories() throws {
        // When
        try core.register(feature: RemoteFeatureMock())

        // Then
        let featureDirectory = try temporaryCoreDirectory.coreDirectory.subdirectory(path: RemoteFeatureMock.name)
        XCTAssertNoThrow(try featureDirectory.subdirectory(path: "v2"), "Authorized data directory must exist")
        XCTAssertNoThrow(try featureDirectory.subdirectory(path: "intermediate-v2"), "Intermediate data directory must exist")
    }

    func testWhenRegisteringFeature_itDoesNotCreateFeatureDirectories() throws {
        // When
        try core.register(feature: FeatureMock())

        // Then
        XCTAssertThrowsError(
            try temporaryCoreDirectory.coreDirectory.subdirectory(path: FeatureMock.name),
            "Feature directory must not exist"
        )
    }
}
