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
            timestamp: dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds,
            hasReplay: true
        )

        dateProvider.advance(bySeconds: 1)

        let timestamp = dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds
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
            timestamp: dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds,
            hasReplay: false
        )

        dateProvider.advance(bySeconds: 1)

        let timestamp = dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds
        XCTAssertEqual(cache.lastView(before: timestamp), viewId)
        XCTAssertEqual(cache.lastView(before: timestamp, hasReplay: false), viewId)
        XCTAssertNil(cache.lastView(before: timestamp, hasReplay: true))
    }

    func testRequestViewFromScene_itDoesNotUseNewerViewFromAnotherScene() {
        let dateProvider = RelativeDateProvider()
        let cache = ViewCache(dateProvider: DateProviderMock())
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")

        cache.insert(
            id: "view-A",
            timestamp: dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds,
            hasReplay: true,
            sceneIdentifier: sceneA
        )
        dateProvider.advance(bySeconds: 1)
        cache.insert(
            id: "view-B",
            timestamp: dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds,
            hasReplay: true,
            sceneIdentifier: sceneB
        )
        dateProvider.advance(bySeconds: 1)
        let timestamp = dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds

        XCTAssertEqual(cache.lastView(before: timestamp, hasReplay: true), "view-B")
        XCTAssertEqual(
            cache.lastView(before: timestamp, hasReplay: true, sceneIdentifier: sceneA),
            "view-A"
        )
        XCTAssertEqual(
            cache.lastView(before: timestamp, hasReplay: true, sceneIdentifier: sceneB),
            "view-B"
        )
    }

    func testRequestViewWithoutScene_whenLegacyAndSceneBucketsExist_itFailsClosed() {
        let dateProvider = RelativeDateProvider()
        let cache = ViewCache(dateProvider: dateProvider)
        cache.insert(
            id: "legacy-view",
            timestamp: dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds
        )
        dateProvider.advance(bySeconds: 1)
        cache.insert(
            id: "scene-view",
            timestamp: dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds,
            sceneIdentifier: RUMSceneIdentifier(rawValue: "scene-A")
        )
        dateProvider.advance(bySeconds: 1)

        XCTAssertNil(
            cache.lastView(
                before: dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds,
                allowAmbiguousScene: false
            )
        )
    }

    func testViewOwnership_distinguishesSceneLegacyAndUnknownViews() {
        let dateProvider = RelativeDateProvider()
        let cache = ViewCache(dateProvider: dateProvider)
        let scene = RUMSceneIdentifier(rawValue: "scene-A")

        cache.insert(
            id: "legacy-view",
            timestamp: dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds
        )
        cache.insert(
            id: "scene-view",
            timestamp: dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds,
            sceneIdentifier: scene
        )

        XCTAssertEqual(cache.ownership(forViewID: "legacy-view"), .legacy)
        XCTAssertEqual(cache.ownership(forViewID: "scene-view"), .scene(scene))
        XCTAssertEqual(cache.ownership(forViewID: "missing-view"), .unknown)
    }

    func testPurge_whenExceedingCount() {
        let dateProvider = RelativeDateProvider()
        let capacity: Int = .mockRandom(min: 2, max: 30)
        let cache = ViewCache(dateProvider: dateProvider, capacity: capacity)

        let firstId: String = .mockRandom()
        cache.insert(
            id: firstId,
            timestamp: dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds,
            hasReplay: .mockRandom()
        )

        dateProvider.advance(bySeconds: 1)

        let timestamp = dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds
        XCTAssertEqual(cache.lastView(before: timestamp), firstId)

        for _ in (0..<capacity - 1) {
            dateProvider.advance(bySeconds: 1)
            cache.insert(
                id: .mockRandom(),
                timestamp: dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds,
                hasReplay: .mockRandom()
            )
        }

        XCTAssertEqual(cache.lastView(before: timestamp), firstId)

        dateProvider.advance(bySeconds: 1)
        cache.insert(
            id: .mockRandom(),
            timestamp: dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds,
            hasReplay: .mockRandom()
        )

        XCTAssertNil(cache.lastView(before: timestamp))
    }

    func testPurge_whenOneSceneExceedsCapacity_itRetainsHistoryFromOtherScenes() {
        let dateProvider = RelativeDateProvider()
        let cache = ViewCache(dateProvider: dateProvider, capacity: 4)
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")

        func insert(_ id: String, scene: RUMSceneIdentifier) {
            cache.insert(
                id: id,
                timestamp: dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds,
                sceneIdentifier: scene
            )
            dateProvider.advance(bySeconds: 1)
        }

        insert("view-A1", scene: sceneA)
        insert("view-A2", scene: sceneA)
        insert("view-B1", scene: sceneB)
        insert("view-B2", scene: sceneB)
        insert("view-B3", scene: sceneB)
        insert("view-B4", scene: sceneB)

        XCTAssertEqual(cache.sceneIdentifier(forViewID: "view-A1"), sceneA)
        XCTAssertEqual(cache.sceneIdentifier(forViewID: "view-A2"), sceneA)
        XCTAssertEqual(
            cache.lastView(
                before: dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds,
                sceneIdentifier: sceneA
            ),
            "view-A2"
        )
    }

    func testPurge_whenExceedingTTL() {
        let dateProvider = RelativeDateProvider()
        let cache = ViewCache(dateProvider: dateProvider, ttl: 30)

        let firstId: String = .mockRandom()
        cache.insert(
            id: firstId,
            timestamp: dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds,
            hasReplay: .mockRandom()
        )

        dateProvider.advance(bySeconds: 10)

        let timestamp = dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds
        XCTAssertEqual(cache.lastView(before: timestamp), firstId)
        cache.markInactive(id: firstId)

        dateProvider.advance(bySeconds: 31)

        XCTAssertNil(cache.lastView(before: timestamp))
    }

    func testPurge_whenActiveSceneExceedsTTL_itRetainsItUntilItStops() {
        let dateProvider = RelativeDateProvider()
        let cache = ViewCache(dateProvider: dateProvider, ttl: 30)
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let viewA = "view-A"
        cache.insert(
            id: viewA,
            timestamp: dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds,
            sceneIdentifier: sceneA
        )

        dateProvider.advance(bySeconds: 40)
        cache.insert(
            id: "view-B",
            timestamp: dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds,
            sceneIdentifier: RUMSceneIdentifier(rawValue: "scene-B")
        )

        XCTAssertEqual(cache.sceneIdentifier(forViewID: viewA), sceneA)

        cache.markInactive(id: viewA)
        XCTAssertEqual(cache.sceneIdentifier(forViewID: viewA), sceneA)

        dateProvider.advance(bySeconds: 29)
        cache.insert(
            id: "view-C",
            timestamp: dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds,
            sceneIdentifier: RUMSceneIdentifier(rawValue: "scene-C")
        )
        XCTAssertEqual(cache.sceneIdentifier(forViewID: viewA), sceneA)

        dateProvider.advance(bySeconds: 2)
        XCTAssertNil(cache.sceneIdentifier(forViewID: viewA))
    }

    func testPurge_whenSceneNavigatesRepeatedly_itDoesNotRenewOlderInactiveViews() {
        let dateProvider = RelativeDateProvider()
        let cache = ViewCache(dateProvider: dateProvider, ttl: 30)
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        cache.insert(
            id: "view-A1",
            timestamp: dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds,
            sceneIdentifier: scene
        )

        dateProvider.advance(bySeconds: 1)
        cache.insert(
            id: "view-A2",
            timestamp: dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds,
            sceneIdentifier: scene
        )

        dateProvider.advance(bySeconds: 20)
        cache.insert(
            id: "view-A3",
            timestamp: dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds,
            sceneIdentifier: scene
        )

        dateProvider.advance(bySeconds: 11)
        XCTAssertNil(cache.sceneIdentifier(forViewID: "view-A1"))
        XCTAssertEqual(cache.sceneIdentifier(forViewID: "view-A2"), scene)
    }
}
