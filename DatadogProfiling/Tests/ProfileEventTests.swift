/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)
import XCTest
import DatadogInternal
import TestUtilities

@testable import DatadogProfiling

class ProfileEventTests: XCTestCase {
    func testEncoding() {
        let additionalAttribues = mockRandomAttributes()

        let event = ProfileEvent(
            family: "family",
            runtime: "runtime",
            version: "version",
            start: .mockAny(),
            end: .mockAny(),
            attachments: ["attachment"],
            tags: "tag:tag",
            additionalAttributes: additionalAttribues
        )

        let expected: [String: Encodable] = [
            "family": "family",
            "runtime": "runtime",
            "version": "version",
            "start": Date.mockAny(),
            "end": Date.mockAny(),
            "attachments": ["attachment"],
            "tags_profiler": "tag:tag",
        ].merging(additionalAttribues, uniquingKeysWith: { $1 })

        DDAssertJSONEqual(event, expected)
    }
}
#endif // !os(watchOS)
