/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogRUM

class DisallowListTests: XCTestCase {
    // MARK: - Empty Patterns

    func testWhenNoPatternsAreConfigured_itDoesNotDisallowAnyURL() {
        // Given
        let disallowList = DisallowList([])

        // Then
        XCTAssertTrue(disallowList.isEmpty)
        XCTAssertFalse(disallowList.isDisallowed(url: URL(string: "https://example.com/")))
    }

    func testWhenURLIsNil_itDoesNotDisallowIt() {
        // Given
        let disallowList = DisallowList(["https://example.com/"])

        // Then
        XCTAssertFalse(disallowList.isDisallowed(url: nil))
    }

    // MARK: - Exact

    func testWhenExactPatternMatches_itDisallowsTheURL() {
        // Given
        let disallowList = DisallowList(["https://example.com/resource"])

        // Then
        XCTAssertTrue(disallowList.isDisallowed(url: URL(string: "https://example.com/resource")))
        XCTAssertFalse(disallowList.isDisallowed(url: URL(string: "https://example.com/resource/other")))
        XCTAssertFalse(disallowList.isDisallowed(url: URL(string: "https://example.com/")))
    }

    // MARK: - Wildcard

    func testWhenWildcardPatternMatches_itDisallowsTheURL() {
        // Given
        let disallowList = DisallowList(["https://example.com/*/private"])

        // Then
        XCTAssertTrue(disallowList.isDisallowed(url: URL(string: "https://example.com/foo/private")))
        XCTAssertTrue(disallowList.isDisallowed(url: URL(string: "https://example.com/foo/bar/private")))
        XCTAssertFalse(disallowList.isDisallowed(url: URL(string: "https://example.com/foo/private/extra")))
    }

    func testWhenWildcardPatternIsAtTheEnd_itDisallowsAnyURLWithThatPrefix() {
        // Given
        let disallowList = DisallowList(["https://example.com/private/*"])

        // Then
        XCTAssertTrue(disallowList.isDisallowed(url: URL(string: "https://example.com/private/resource")))
        XCTAssertTrue(disallowList.isDisallowed(url: URL(string: "https://example.com/private/")))
        XCTAssertFalse(disallowList.isDisallowed(url: URL(string: "https://example.com/public/resource")))
    }

    func testWhenWildcardPatternContainsLiteralRegexCharacters_itEscapesThemAsLiterals() {
        // Given
        let disallowList = DisallowList(["https://example.com/*.json"])

        // Then
        XCTAssertTrue(disallowList.isDisallowed(url: URL(string: "https://example.com/resource.json")))
        XCTAssertFalse(disallowList.isDisallowed(url: URL(string: "https://example.com/resourceXjson")))
    }

    func testWhenPatternContainsMultipleWildcards_itDisallowsMatchingURLs() {
        // Given
        let disallowList = DisallowList(["https://example.com/*/foo/*"])

        // Then
        XCTAssertTrue(disallowList.isDisallowed(url: URL(string: "https://example.com/bar/foo/baz")))
        XCTAssertTrue(disallowList.isDisallowed(url: URL(string: "https://example.com/a/b/foo/c")))
        XCTAssertFalse(disallowList.isDisallowed(url: URL(string: "https://example.com/bar/baz")))
    }

    func testWhenPatternMatchesDuplicatedPathSegments_itDisallowsBothVariants() {
        // Given - e.g. excluding operation endpoints across duplicated /api/v2 and /api/ui paths
        let disallowList = DisallowList(["https://example.com/api/*/operations/*"])

        // Then
        XCTAssertTrue(disallowList.isDisallowed(url: URL(string: "https://example.com/api/v2/operations/list")))
        XCTAssertTrue(disallowList.isDisallowed(url: URL(string: "https://example.com/api/ui/operations/123")))
        XCTAssertFalse(disallowList.isDisallowed(url: URL(string: "https://example.com/api/v2/users/list")))
    }

    // MARK: - Invalid Patterns

    func testWhenPatternIsBareWildcard_itIsIgnoredWithoutMatchingEveryURL() {
        // Given
        let disallowList = DisallowList(["*"])

        // Then
        XCTAssertTrue(disallowList.isEmpty)
        XCTAssertFalse(disallowList.isDisallowed(url: URL(string: "https://example.com/")))
    }

    func testWhenPatternIsOnlyWildcards_itIsIgnoredWithoutMatchingEveryURL() {
        // Given
        let disallowList = DisallowList(["**"])

        // Then
        XCTAssertTrue(disallowList.isEmpty)
        XCTAssertFalse(disallowList.isDisallowed(url: URL(string: "https://example.com/")))
    }

    // MARK: - Multiple Patterns

    func testWhenMultiplePatternsAreConfigured_itDisallowsURLsMatchingAny() {
        // Given
        let disallowList = DisallowList(
            [
                "https://a.com/",
                "https://b.com/private/*",
                "https://c.com/*/secret"
            ]
        )

        // Then
        XCTAssertTrue(disallowList.isDisallowed(url: URL(string: "https://a.com/")))
        XCTAssertTrue(disallowList.isDisallowed(url: URL(string: "https://b.com/private/resource")))
        XCTAssertTrue(disallowList.isDisallowed(url: URL(string: "https://c.com/foo/secret")))
        XCTAssertFalse(disallowList.isDisallowed(url: URL(string: "https://d.com/")))
    }
}
