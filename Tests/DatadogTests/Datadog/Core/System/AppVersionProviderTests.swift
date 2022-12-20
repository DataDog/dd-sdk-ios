/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import Datadog

class AppVersionProviderTests: XCTestCase {
    func testItReadsInitialValueFromConfiguration() {
        // Given
        let randomVersion: String = .mockRandom()
        let configuration: CoreConfiguration = .mockWith(applicationVersion: randomVersion)

        // When
        let provider = AppVersionProvider(configuration: configuration)

        // Then
        XCTAssertEqual(provider.value, randomVersion)
    }

    func testWhenValueChanges_itProvidesNewValue() {
        // Given
        let provider = AppVersionProvider(configuration: .mockWith(applicationVersion: .mockRandom()))

        // When
        let randomVersion: String = .mockRandom()
        provider.value = randomVersion

        // Then
        XCTAssertEqual(provider.value, randomVersion)
    }
}
