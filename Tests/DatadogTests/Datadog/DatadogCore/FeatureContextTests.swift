/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class FeatureContextTests: XCTestCase {
    func testV1FeatureContextSharing() throws {
        // Given
        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            consentProvider: .mockAny(),
            userInfoProvider: .mockAny(),
            performance: .mockAny(),
            httpClient: .mockAny(),
            encryption: nil,
            v1Context: .mockAny(),
            contextProvider: .mockAny()
        )

        defer { temporaryCoreDirectory.delete() }

        // When
        let attributes: FeatureMessageAttributes = ["key": "value"]
        core.set(feature: "test", attributes: attributes)

        // Then
        let testAttributes = try XCTUnwrap(core.v1Context.featuresAttributesProvider.attributes["test"])
        AssertDictionariesEqual(testAttributes.all(), attributes.all())
    }

    func testV2FeatureContextSharing() throws {
        // Given
        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            consentProvider: .mockAny(),
            userInfoProvider: .mockAny(),
            performance: .mockAny(),
            httpClient: .mockAny(),
            encryption: nil,
            v1Context: .mockAny(),
            contextProvider: .mockAny()
        )

        defer { temporaryCoreDirectory.delete() }

        // When
        let attributes: FeatureMessageAttributes = ["key": "value"]
        core.set(feature: "test", attributes: attributes)

        // Then

        let context = core.contextProvider.read()
        let testAttributes = try XCTUnwrap(context.featuresAttributes["test"])
        AssertDictionariesEqual(testAttributes.all(), attributes.all())
    }
}
