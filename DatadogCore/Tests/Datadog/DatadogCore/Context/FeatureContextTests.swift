/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities
@testable import DatadogCore

class FeatureContextTests: XCTestCase {
    func testV2FeatureContextSharing() throws {
        // Given
        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .granted,
            performance: .mockAny(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            backgroundTasksEnabled: .mockAny()
        )

        defer { temporaryCoreDirectory.delete() }

        // When
        let attributes = ["key": "value"]
        core.set(baggage: attributes, forKey: "test")

        // Then
        let context = core.contextProvider.read()
        let testBaggage = try XCTUnwrap(context.baggages["test"])
        try DDAssertDictionariesEqual(
            testBaggage.decode(type: [String: String].self),
            attributes
        )
    }
}
