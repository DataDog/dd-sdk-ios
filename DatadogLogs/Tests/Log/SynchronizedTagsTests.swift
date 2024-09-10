/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogLogs

final class SynchronizedTagsTests: XCTestCase {
    func testAddTag() {
        let synchronizedTags = SynchronizedTags(tags: [])
        synchronizedTags.addTag("tag1")

        let tags = synchronizedTags.getTags()
        XCTAssertTrue(tags.contains("tag1"))
        XCTAssertEqual(tags.count, 1)
    }

    func testRemoveTag() {
        let synchronizedTags = SynchronizedTags(tags: ["tag1", "tag2"])
        synchronizedTags.removeTag("tag1")

        let tags = synchronizedTags.getTags()
        XCTAssertFalse(tags.contains("tag1"))
        XCTAssertTrue(tags.contains("tag2"))
        XCTAssertEqual(tags.count, 1)
    }

    func testRemoveTagsWithPredicate() {
        let synchronizedTags = SynchronizedTags(tags: ["tag1", "tag2", "tag3", "tag4"])
        synchronizedTags.removeTags { $0.contains("2") || $0.contains("4") }

        let tags = synchronizedTags.getTags()
        XCTAssertFalse(tags.contains("tag2"))
        XCTAssertFalse(tags.contains("tag4"))
        XCTAssertTrue(tags.contains("tag1"))
        XCTAssertTrue(tags.contains("tag3"))
        XCTAssertEqual(tags.count, 2)
    }

    func testGetTags() {
        let initialTags: Set<String> = ["tag1", "tag2"]
        let synchronizedTags = SynchronizedTags(tags: initialTags)

        let tags = synchronizedTags.getTags()
        XCTAssertEqual(tags, initialTags)
    }

    func testThreadSafety() {
        let synchronizedTags = SynchronizedTags(tags: [])

        callConcurrently(
            closures: [
                { idx in synchronizedTags.addTag("tag\(idx)") },
                { idx in synchronizedTags.removeTag("unknown-tag\(idx)") },
                { idx in synchronizedTags.removeTags(where: { _ in false }) },
                { _ in _ = synchronizedTags.getTags() },
            ],
            iterations: 1_000
        )

        XCTAssertEqual(synchronizedTags.getTags().count, 1_000)
    }
}
