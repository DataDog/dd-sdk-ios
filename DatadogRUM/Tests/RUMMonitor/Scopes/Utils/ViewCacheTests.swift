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

        dateProvider.advance(bySeconds: 30)

        cache.insert(
            id: .mockRandom(),
            timestamp: dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds,
            hasReplay: .mockRandom()
        )

        XCTAssertNil(cache.lastView(before: timestamp))
    }

    func testMultiSceneOwnership_distinguishesSceneLegacyAndUnknownIDs() {
        let clock = RelativeDateProvider(using: Date(timeIntervalSince1970: 1_000))
        let cache = ViewCache(dateProvider: clock, isMultiSceneTrackingEnabled: true)
        let scene = RUMSceneIdentifier(rawValue: "scene-a")
        let start = clock.now.timeIntervalSince1970.dd.toInt64Milliseconds
        cache.insert(id: "scene-view", timestamp: start, sceneIdentifier: scene)
        cache.insert(id: "legacy-view", timestamp: start + 1)

        XCTAssertEqual(cache.ownership(forViewID: "scene-view"), .scene(scene))
        XCTAssertEqual(cache.ownership(forViewID: "legacy-view"), .legacy)
        XCTAssertEqual(cache.ownership(forViewID: "unknown-view"), .unknown)
    }

    func testMultiSceneNavigation_keepsPeerActiveAndRetainsStoppedViewForFullTTL() {
        let clock = RelativeDateProvider(using: Date(timeIntervalSince1970: 1_000))
        let cache = ViewCache(dateProvider: clock, ttl: 30, isMultiSceneTrackingEnabled: true)
        let sceneA = RUMSceneIdentifier(rawValue: "scene-a")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-b")
        let start = clock.now.timeIntervalSince1970.dd.toInt64Milliseconds
        cache.insert(id: "a-old", timestamp: start, isActive: true, sceneIdentifier: sceneA)
        cache.insert(id: "b", timestamp: start, isActive: true, sceneIdentifier: sceneB)
        clock.advance(bySeconds: 100)
        cache.insert(id: "a-new", timestamp: clock.now.timeIntervalSince1970.dd.toInt64Milliseconds, isActive: true, sceneIdentifier: sceneA)

        clock.advance(bySeconds: 30)
        XCTAssertEqual(cache.ownership(forViewID: "a-old"), .scene(sceneA))
        XCTAssertEqual(cache.ownership(forViewID: "b"), .scene(sceneB))
        clock.advance(bySeconds: 1)
        XCTAssertEqual(cache.ownership(forViewID: "a-old"), .unknown)
        XCTAssertEqual(cache.ownership(forViewID: "a-new"), .scene(sceneA))
        XCTAssertEqual(cache.ownership(forViewID: "b"), .scene(sceneB))
    }

    func testMultiSceneCapacity_keepsQuietSceneHistoryBesideBusyScene() {
        let clock = RelativeDateProvider(using: Date(timeIntervalSince1970: 1_000))
        let cache = ViewCache(dateProvider: clock, capacity: 4, isMultiSceneTrackingEnabled: true)
        let sceneA = RUMSceneIdentifier(rawValue: "scene-a")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-b")
        let start = clock.now.timeIntervalSince1970.dd.toInt64Milliseconds
        cache.insert(id: "b-old", timestamp: start, sceneIdentifier: sceneB)
        cache.insert(id: "b-active", timestamp: start + 1, isActive: true, sceneIdentifier: sceneB)
        for index in 0..<10 {
            cache.insert(id: "a-\(index)", timestamp: start + Int64(index) + 2, isActive: true, sceneIdentifier: sceneA)
        }

        XCTAssertEqual(cache.ownership(forViewID: "b-old"), .scene(sceneB))
        XCTAssertEqual(cache.ownership(forViewID: "b-active"), .scene(sceneB))
        XCTAssertEqual(cache.ownership(forViewID: "a-9"), .scene(sceneA))
        XCTAssertEqual(cache.ownership(forViewID: "a-8"), .scene(sceneA))
        XCTAssertEqual(cache.ownership(forViewID: "a-7"), .unknown)
    }

    func testMultiSceneSingleBucket_preservesNewestOrderingAndReplayFilter() {
        let clock = RelativeDateProvider(using: Date(timeIntervalSince1970: 1_000))
        let cache = ViewCache(dateProvider: clock, capacity: 2, isMultiSceneTrackingEnabled: true)
        let scene = RUMSceneIdentifier(rawValue: "scene-a")
        let start = clock.now.timeIntervalSince1970.dd.toInt64Milliseconds
        cache.insert(id: "old", timestamp: start, hasReplay: true, sceneIdentifier: scene)
        cache.insert(id: "replay", timestamp: start + 1, hasReplay: true, sceneIdentifier: scene)
        cache.insert(id: "newest", timestamp: start + 2, hasReplay: false, sceneIdentifier: scene)

        XCTAssertEqual(cache.lastView(before: start + 3), "newest")
        XCTAssertEqual(cache.lastView(before: start + 3, hasReplay: true), "replay")
        XCTAssertEqual(cache.ownership(forViewID: "old"), .unknown)
    }

    func testDefaultMode_sceneMetadataDoesNotEnablePeerRetention() {
        let clock = RelativeDateProvider(using: Date(timeIntervalSince1970: 1_000))
        let cache = ViewCache(dateProvider: clock, capacity: 2)
        let sceneA = RUMSceneIdentifier(rawValue: "scene-a")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-b")
        let start = clock.now.timeIntervalSince1970.dd.toInt64Milliseconds
        cache.insert(id: "b", timestamp: start, isActive: true, sceneIdentifier: sceneB)
        cache.insert(id: "a-old", timestamp: start + 1, isActive: true, sceneIdentifier: sceneA)
        cache.insert(id: "a-new", timestamp: start + 2, isActive: true, sceneIdentifier: sceneA)

        XCTAssertEqual(cache.ownership(forViewID: "b"), .unknown)
        clock.advance(bySeconds: 200)
        XCTAssertEqual(cache.ownership(forViewID: "a-old"), .scene(sceneA))
        XCTAssertEqual(cache.ownership(forViewID: "a-new"), .scene(sceneA))
    }

    func testMultiSceneZeroCapacity_discardsEvenActiveOwners() {
        let clock = RelativeDateProvider(using: Date(timeIntervalSince1970: 1_000))
        let cache = ViewCache(dateProvider: clock, capacity: 0, isMultiSceneTrackingEnabled: true)
        cache.insert(id: "a", timestamp: clock.now.timeIntervalSince1970.dd.toInt64Milliseconds, isActive: true, sceneIdentifier: .init(rawValue: "scene-a"))

        XCTAssertEqual(cache.ownership(forViewID: "a"), .unknown)
    }

    func testMultiSceneCapacity_pinsAllLiveOwnersBeforeHistory() {
        let clock = RelativeDateProvider(using: Date(timeIntervalSince1970: 1_000))
        let cache = ViewCache(dateProvider: clock, capacity: 1, isMultiSceneTrackingEnabled: true)
        let start = clock.now.timeIntervalSince1970.dd.toInt64Milliseconds
        cache.insert(id: "a", timestamp: start, isActive: true, sceneIdentifier: .init(rawValue: "scene-a"))
        cache.insert(id: "b", timestamp: start + 1, isActive: true, sceneIdentifier: .init(rawValue: "scene-b"))
        cache.insert(id: "history", timestamp: start + 2, sceneIdentifier: .init(rawValue: "scene-c"))

        XCTAssertEqual(cache.ownership(forViewID: "a"), .scene(.init(rawValue: "scene-a")))
        XCTAssertEqual(cache.ownership(forViewID: "b"), .scene(.init(rawValue: "scene-b")))
        XCTAssertEqual(cache.ownership(forViewID: "history"), .unknown)
    }
}
