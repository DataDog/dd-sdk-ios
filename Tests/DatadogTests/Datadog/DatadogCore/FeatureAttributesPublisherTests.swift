/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class FeatureAttributesPublisherTests: XCTestCase {
    func testEmptyInitialValue() throws {
        let publisher = FeatureAttributesPublisher()
        AssertDictionariesEqual(publisher.initialValue, [:])
    }

    func testPublishAttributes() throws {
        let expectation = expectation(description: "feature attributes publisher publishes data")

        // Given
        let publisher = FeatureAttributesPublisher()
        let attributes: FeatureAttributesPublisher.Value = .mockRandom()

        // When
        publisher.publish {
            // Then
            self.AssertDictionariesEqual($0, attributes)
            expectation.fulfill()
        }

        publisher.attributes = attributes

        // UserInfoPublisher publishes in sync
        waitForExpectations(timeout: 0)
    }
}
