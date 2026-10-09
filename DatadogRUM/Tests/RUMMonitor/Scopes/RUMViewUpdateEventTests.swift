/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
@testable import DatadogRUM
import TestUtilities

/// Tests the roundtrip invariant for `RUMViewEvent.update(from:)`:
/// for any two view events A and B, `A.apply(update: A.update(from: B))` must equal B
/// for every field that the update path diffs or forwards.
///
/// The key structural guarantee: when a new field is added to `RUMViewEvent`, the compiler forces
/// `update(from:)` to be updated (it uses `RUMViewUpdateEvent.init` which lists all fields), and
/// `mockRandom()` to be updated (it uses `RUMViewEvent.init`). The `apply(update:)` extension in
/// `TestUtilities/Sources/Matchers/RUMViewEvent+Merge.swift` mirrors this: it explicitly calls
/// `RUMViewEvent.init(...)` and `RUMViewEvent.View.init(...)`, so any new field that isn't handled
/// there also fails to compile.
class RUMViewUpdateEventTests: XCTestCase {
    func testRoundtrip_allDiffableFieldsAreReconstructed() throws {
        for _ in 0..<100 {
            // Slow frames are merged by `start` instead of replaced, so unrelated random lists
            // can't be reconstructed. They are covered by the `testSlowFrames_*` tests below.
            let base = RUMViewEvent.mockRandomWith(slowFrames: nil)
            let target = RUMViewEvent.mockRandomWith(slowFrames: nil)
            let update = base.update(from: target)
            let reconstructed = base.apply(update: update)
            DDAssertJSONEqual(reconstructed, target)
        }
    }

    /// `dd`, `application`, and `session` are always forwarded wholesale from `event`, never
    /// diffed against `self`.
    func testUpdate_ddApplicationAndSessionAreForwardedWholesaleNotDiffed() throws {
        let base = RUMViewEvent.mockRandom()
        let target = RUMViewEvent.mockRandom()
        let update = base.update(from: target)

        // Values come from `target` (the new event), not `base` — proving these are forwarded
        // from `event`, not accidentally left as `self`'s own value.
        XCTAssertEqual(update.dd.documentVersion, target.dd.documentVersion)
        XCTAssertEqual(update.application.id, target.application.id)
        XCTAssertEqual(update.session.id, target.session.id)
        XCTAssertEqual(update.session.type, target.session.type)
    }

    /// `usr` and `account` are identity fields: unlike diffed fields, `nil` on the wire must
    /// unambiguously mean "the target event has no usr/account", never "unchanged" — otherwise
    /// `clearUserInfo()`/`clearAccountInfo()` mid-view would be silently dropped from the delta.
    /// They must therefore be forwarded wholesale from `event`, like `dd`, and never diffed.
    func testUpdate_usrAndAccountAreForwardedWholesaleNotDiffed() throws {
        var base = RUMViewEvent.mockRandom()
        base.usr = .mockRandom()
        base.account = .mockRandom()

        // Same non-nil value on both sides: if diffed, this would collapse to `nil` — the exact
        // wire representation of "unchanged" — because old == new.
        var unchanged = base
        unchanged.usr = base.usr
        unchanged.account = base.account
        let unchangedUpdate = base.update(from: unchanged)
        DDAssertJSONEqual(unchangedUpdate.usr, base.usr)
        DDAssertJSONEqual(unchangedUpdate.account, base.account)

        // Non-nil → nil transition (e.g. clearUserInfo()/clearAccountInfo()) must produce `nil`
        // in the update, reflecting the target's actual (empty) value.
        var cleared = base
        cleared.usr = nil
        cleared.account = nil
        let clearedUpdate = base.update(from: cleared)
        XCTAssertNil(clearedUpdate.usr)
        XCTAssertNil(clearedUpdate.account)
    }

    // MARK: - Slow Frames

    func testSlowFrames_onlyNewRecordsAreSent() {
        // Given
        let base = viewEvent(slowFrames: [(start: 0, duration: 10), (start: 100, duration: 20)])
        let target = viewEvent(slowFrames: [(start: 0, duration: 10), (start: 100, duration: 20), (start: 200, duration: 30), (start: 300, duration: 40)])

        // When
        let update = base.update(from: target)

        // Then
        XCTAssertEqual(update.view.slowFrames, [.init(duration: 30, start: 200), .init(duration: 40, start: 300)])
    }

    func testSlowFrames_lastRecordIsResentWhenItGrew() {
        // Given
        let base = viewEvent(slowFrames: [(start: 0, duration: 10), (start: 100, duration: 20)])
        let grown = viewEvent(slowFrames: [(start: 0, duration: 10), (start: 100, duration: 50)])
        let grownAndNew = viewEvent(slowFrames: [(start: 0, duration: 10), (start: 100, duration: 50), (start: 200, duration: 30)])

        // When
        let grownUpdate = base.update(from: grown)
        let grownAndNewUpdate = base.update(from: grownAndNew)

        // Then
        XCTAssertEqual(grownUpdate.view.slowFrames, [.init(duration: 50, start: 100)])
        XCTAssertEqual(grownAndNewUpdate.view.slowFrames, [.init(duration: 50, start: 100), .init(duration: 30, start: 200)])
    }

    func testSlowFrames_nilWhenNothingChanged() {
        // Given
        let base = viewEvent(slowFrames: [(start: 0, duration: 10), (start: 100, duration: 20)])

        // When
        let unchangedUpdate = base.update(from: viewEvent(slowFrames: [(start: 0, duration: 10), (start: 100, duration: 20)]))
        let emptyUpdate = base.update(from: viewEvent(slowFrames: []))
        let nilUpdate = base.update(from: viewEvent(slowFrames: nil))

        // Then
        XCTAssertNil(unchangedUpdate.view.slowFrames)
        XCTAssertNil(emptyUpdate.view.slowFrames)
        XCTAssertNil(nilUpdate.view.slowFrames)
    }

    func testSlowFrames_whenOldestRecordsWereEvicted() {
        // Given
        let base = viewEvent(slowFrames: [(start: 0, duration: 10), (start: 100, duration: 20), (start: 200, duration: 30)])
        let target = viewEvent(slowFrames: [(start: 200, duration: 30), (start: 300, duration: 40)])

        // When
        let update = base.update(from: target)

        // Then
        XCTAssertEqual(update.view.slowFrames, [.init(duration: 40, start: 300)])
    }

    func testSlowFrames_olderRecordsAreNeverResent() {
        // Given
        let base = viewEvent(slowFrames: [(start: 0, duration: 10), (start: 100, duration: 20)])
        let target = viewEvent(slowFrames: [(start: 0, duration: 99), (start: 100, duration: 20), (start: 200, duration: 30)])

        // When
        let update = base.update(from: target)

        // Then
        XCTAssertEqual(update.view.slowFrames, [.init(duration: 30, start: 200)])
    }

    private func viewEvent(slowFrames: [(start: Int64, duration: Int64)]?) -> RUMViewEvent {
        .mockRandomWith(slowFrames: slowFrames?.map { .init(duration: $0.duration, start: $0.start) })
    }
}
