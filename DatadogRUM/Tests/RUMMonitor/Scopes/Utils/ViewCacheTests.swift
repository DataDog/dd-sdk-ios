/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities

@testable import DatadogRUM

class ViewCacheTests: XCTestCase {
    func testRequestView_withReplay() {
        let dateProvider = RelativeDateProvider()
        let cache = ViewCache(dateProvider: DateProviderMock())

        let viewId: String = .mockRandom()
        cache.insert(
            id: viewId,
            timestamp: dateProvider.now.timeIntervalSince1970.toInt64Milliseconds,
            hasReplay: true
        )

        dateProvider.advance(bySeconds: 1)

        let timestamp = dateProvider.now.timeIntervalSince1970.toInt64Milliseconds
        XCTAssertEqual(cache.lastView(before: timestamp), viewId)
        XCTAssertEqual(cache.lastView(before: timestamp, hasReplay: true), viewId)
        XCTAssertNil(cache.lastView(before: timestamp, hasReplay: false))
    }

    func testRequestView_withoutReplay() {
        let dateProvider = RelativeDateProvider()
        let cache = ViewCache(dateProvider: DateProviderMock())

        let viewId: String = .mockRandom()
        cache.insert(
            id: viewId,
            timestamp: dateProvider.now.timeIntervalSince1970.toInt64Milliseconds,
            hasReplay: false
        )

        dateProvider.advance(bySeconds: 1)

        let timestamp = dateProvider.now.timeIntervalSince1970.toInt64Milliseconds
        XCTAssertEqual(cache.lastView(before: timestamp), viewId)
        XCTAssertEqual(cache.lastView(before: timestamp, hasReplay: false), viewId)
        XCTAssertNil(cache.lastView(before: timestamp, hasReplay: true))
    }

    func testPurge_whenExceedingCount() {
        let dateProvider = RelativeDateProvider()
        let capacity: Int = .mockRandom(min: 2, max: 30)
        let cache = ViewCache(dateProvider: dateProvider, capacity: capacity)

        let firstId: String = .mockRandom()
        cache.insert(
            id: firstId,
            timestamp: dateProvider.now.timeIntervalSince1970.toInt64Milliseconds,
            hasReplay: .mockRandom()
        )

        dateProvider.advance(bySeconds: 1)

        let timestamp = dateProvider.now.timeIntervalSince1970.toInt64Milliseconds
        XCTAssertEqual(cache.lastView(before: timestamp), firstId)

        for _ in (0..<capacity - 1) {
            dateProvider.advance(bySeconds: 1)
            cache.insert(
                id: .mockRandom(),
                timestamp: dateProvider.now.timeIntervalSince1970.toInt64Milliseconds,
                hasReplay: .mockRandom()
            )
        }

        XCTAssertEqual(cache.lastView(before: timestamp), firstId)

        dateProvider.advance(bySeconds: 1)
        cache.insert(
            id: .mockRandom(),
            timestamp: dateProvider.now.timeIntervalSince1970.toInt64Milliseconds,
            hasReplay: .mockRandom()
        )

        XCTAssertNil(cache.lastView(before: timestamp))
    }

    func testPurge_whenExceedingTTL() {
        let dateProvider = RelativeDateProvider()
        let cache = ViewCache(dateProvider: dateProvider, ttl: 30)

        let firstId: String = .mockRandom()
        cache.insert(
            id: firstId,
            timestamp: dateProvider.now.timeIntervalSince1970.toInt64Milliseconds,
            hasReplay: .mockRandom()
        )

        dateProvider.advance(bySeconds: 10)

        let timestamp = dateProvider.now.timeIntervalSince1970.toInt64Milliseconds
        XCTAssertEqual(cache.lastView(before: timestamp), firstId)

        dateProvider.advance(bySeconds: 30)

        cache.insert(
            id: .mockRandom(),
            timestamp: dateProvider.now.timeIntervalSince1970.toInt64Milliseconds,
            hasReplay: .mockRandom()
        )

        XCTAssertNil(cache.lastView(before: timestamp))
    }
}
