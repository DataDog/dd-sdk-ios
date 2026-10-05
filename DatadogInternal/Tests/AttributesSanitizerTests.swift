/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogInternal

final class AttributesSanitizerTests: XCTestCase {
    func testSanitizeKeysWhenSanitizedKeyCollidesWithExistingKey() {
        // Given
        let sanitizer = AttributesSanitizer(featureName: "test")
        let sanitizedKey = "a.b.c.d.e.f.g.h.i.j_k"
        let attributes = [
            "a.b.c.d.e.f.g.h.i.j.k": 1,
            sanitizedKey: 2
        ]

        // When
        let sanitizedAttributes = sanitizer.sanitizeKeys(for: attributes)

        // Then
        XCTAssertEqual(sanitizedAttributes, [sanitizedKey: 2])
    }
}
