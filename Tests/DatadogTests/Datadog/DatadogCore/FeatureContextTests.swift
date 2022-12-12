/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class FeatureContextTests: XCTestCase {
    func testV2FeatureContextSharing() throws {
        // Given
        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .granted,
            userInfoProvider: .mockAny(),
            performance: .mockAny(),
            httpClient: .mockAny(),
            encryption: nil,
            v1Context: .mockAny(),
            contextProvider: .mockAny(),
            applicationVersion: .mockAny()
        )

        defer { temporaryCoreDirectory.delete() }

        // When
        let attributes: FeatureBaggage = ["key": "value"]
        core.set(feature: "test", attributes: { attributes })

        // Then
        let context = core.contextProvider.read()
        let testAttributes = try XCTUnwrap(context.featuresAttributes["test"])
        AssertDictionariesEqual(testAttributes.all(), attributes.all())
    }
}
