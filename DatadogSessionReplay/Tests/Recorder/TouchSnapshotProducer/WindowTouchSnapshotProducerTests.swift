/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
@testable import DatadogSessionReplay
@_spi(Internal)
import TestUtilities

internal class AppWindowObserverMock: AppWindowObserver {
    var relevantWindow: UIWindow? = UIWindow(frame: .mockRandom(minWidth: 100, minHeight: 100))
}

class WindowTouchSnapshotProducerTests: XCTestCase {
    private let mockWindowObserver = AppWindowObserverMock()
    private let mockApplication = UIApplication.shared

    func testWhenTakingSnapshotsFasterThanReceivingTouchEvents() throws {
        let touchEvent1 = UITouchEventMock(touches: (0..<5).map { _ in UITouchMock(phase: .moved) })
        let touchEvent2 = UITouchEventMock(touches: (0..<10).map { _ in UITouchMock(phase: .moved) })

        // Given
        let producer = WindowTouchSnapshotProducer(
            windowObserver: mockWindowObserver
        )

        // When
        let snapshot1 = producer.takeSnapshot(context: .mockAny())
        producer.notify_sendEvent(application: mockApplication, event: touchEvent1)
        let snapshot2 = producer.takeSnapshot(context: .mockAny())
        let snapshot3 = producer.takeSnapshot(context: .mockAny())
        producer.notify_sendEvent(application: mockApplication, event: touchEvent2)
        let snapshot4 = producer.takeSnapshot(context: .mockAny())
        let snapshot5 = producer.takeSnapshot(context: .mockAny())

        // Then
        XCTAssertNil(snapshot1, "Until next touch event is tracked, it should produce no snapshot")
        XCTAssertNil(snapshot3)
        XCTAssertNil(snapshot5)
        XCTAssertNotNil(snapshot2, "After touch event is tracked, it should produce a snapshot")
        XCTAssertNotNil(snapshot4)
        XCTAssertEqual(snapshot2?.touches.count, touchEvent1._touches.count)
        XCTAssertEqual(snapshot4?.touches.count, touchEvent2._touches.count)
    }

    func testWhenReceivingTouchEventsFasterThanTakingSnapshots() throws {
        let touchEvent1 = UITouchEventMock(touches: (0..<10).map { _ in UITouchMock(phase: .moved) })
        let touchEvent2 = UITouchEventMock(touches: (0..<10).map { _ in UITouchMock(phase: .moved) })
        let touchEvent3 = UITouchEventMock(touches: (0..<15).map { _ in UITouchMock(phase: .moved) })

        // Given
        let producer = WindowTouchSnapshotProducer(
            windowObserver: mockWindowObserver
        )

        // When
        producer.notify_sendEvent(application: mockApplication, event: touchEvent1)
        producer.notify_sendEvent(application: mockApplication, event: touchEvent2)
        producer.notify_sendEvent(application: mockApplication, event: touchEvent3)
        let snapshot1 = producer.takeSnapshot(context: .mockAny())
        let snapshot2 = producer.takeSnapshot(context: .mockAny())

        // Then
        XCTAssertNotNil(snapshot1, "After touch event is tracked, it should produce a snapshot")
        XCTAssertNil(snapshot2, "Until next touch event is tracked, it should produce no snapshot")
        XCTAssertEqual(snapshot1?.touches.count, touchEvent1._touches.count + touchEvent2._touches.count + touchEvent3._touches.count)
    }

    func testSnapshotValue() throws {
        let touch1 = UITouchMock()
        let touch2 = UITouchMock()
        let touch3 = UITouchMock()

        // Given
        let producer = WindowTouchSnapshotProducer(
            windowObserver: mockWindowObserver
        )

        // When
        touch1.phase = .began
        producer.notify_sendEvent(application: mockApplication, event: UITouchEventMock(touches: [touch1]))

        touch1.phase = .moved
        touch2.phase = .began
        producer.notify_sendEvent(application: mockApplication, event: UITouchEventMock(touches: [touch1, touch2]))

        touch1.phase = .ended
        touch2.phase = .moved
        touch3.phase = .began
        producer.notify_sendEvent(application: mockApplication, event: UITouchEventMock(touches: [touch1, touch2, touch3]))

        touch2.phase = .ended
        touch3.phase = .moved
        producer.notify_sendEvent(application: mockApplication, event: UITouchEventMock(touches: [touch2, touch3]))

        touch3.phase = .ended
        producer.notify_sendEvent(application: mockApplication, event: UITouchEventMock(touches: [touch3]))

        // Then
        let snapshot = try XCTUnwrap(producer.takeSnapshot(context: .mockAny()))
        XCTAssertEqual(snapshot.touches.count, 9, "It should capture 9 touch informations")
        XCTAssertEqual(Set(snapshot.touches.map { $0.id }).count, 3, "There should be 3 distinct touch identifiers among touch information")
    }

    func testItAppliesServerTimeOffsetIsToSnapshot() {
        // Given
        let touchEvent1 = UITouchEventMock(touches: (0..<2).map { _ in UITouchMock(phase: .moved) })
        let producer = WindowTouchSnapshotProducer(
            windowObserver: mockWindowObserver
        )

        // When
        producer.notify_sendEvent(application: mockApplication, event: touchEvent1)
        let snapshot1 = producer.takeSnapshot(context: .mockWith(rumContext: .mockWith(serverTimeOffset: 1_000)))

        // Then
        XCTAssertGreaterThan(snapshot1!.date, Date())
    }

    // MARK: - Touch Override View Tests
    func testResolveTouchOverride_whenViewHasNoOverride_returnsNil() {
        // Given
        let view = UIView(frame: .mockRandom())
        let touch = UITouchMock(phase: .began, location: .mockRandom(), view: view)

        let producer = WindowTouchSnapshotProducer(
            windowObserver: mockWindowObserver
        )

        // When
        let override = producer.resolveTouchOverride(for: touch)

        // Then
        XCTAssertNil(override, "Touch privacy override should be `nil` if view and its ancestors have no overrides")
    }

    func testResolveTouchOverride_whenParentViewHasOverride_returnsOverride() {
        // Given
        let parentView = UIView(frame: .mockRandom())
        let touchOverride: TouchPrivacyLevel = .mockRandom()
        parentView.dd.sessionReplayPrivacyOverrides.touchPrivacy = touchOverride

        let childView = UIView(frame: .mockRandom())
        parentView.addSubview(childView)

        let touch = UITouchMock(phase: .began, location: .mockRandom(), view: childView)

        let producer = WindowTouchSnapshotProducer(
            windowObserver: mockWindowObserver
        )

        // When
        let override = producer.resolveTouchOverride(for: touch)

        // Then
        XCTAssertEqual(override, touchOverride, "Touch privacy override should be inherited from the parent view")
    }

    func testWhenViewHasTouchOverrideSetToHide_touchesAreNotRecorded() {
        // Given
        let view = UIView(frame: .mockRandom())
        view.dd.sessionReplayPrivacyOverrides.touchPrivacy = .hide

        let touch = UITouchMock(phase: .began, location: .mockRandom(), view: view)
        let touchEvent = UITouchEventMock(touches: [touch])

        let producer = WindowTouchSnapshotProducer(
            windowObserver: mockWindowObserver
        )

        // When
        producer.notify_sendEvent(application: mockApplication, event: touchEvent)
        let snapshot = producer.takeSnapshot(context: .mockAny())

        // Then
        XCTAssertNil(snapshot, "Touches in a view with touch privacy set to `.hide` should not be recorded")
    }

    func testWhenParentViewHasTouchOverrideSetToHide_touchesInChildViewsAreNotRecorded() {
        // Given
        let parentView = UIView(frame: .mockRandom())
        parentView.dd.sessionReplayPrivacyOverrides.touchPrivacy = .hide

        let childView = UIView(frame: .mockRandom())
        parentView.addSubview(childView)

        let touch = UITouchMock(phase: .began, location: .mockRandom(), view: childView)
        let touchEvent = UITouchEventMock(touches: [touch])

        let producer = WindowTouchSnapshotProducer(
            windowObserver: mockWindowObserver
        )

        // When
        producer.notify_sendEvent(application: mockApplication, event: touchEvent)
        let snapshot = producer.takeSnapshot(context: .mockAny())

        // Then
        XCTAssertNil(snapshot, "Touches in a child view of a parent with touch privacy set to `.hide` should not be recorded")
    }

    func testWhenViewHasTouchOverrideSetToShow_touchesAreRecorded() {
        // Given
        let view = UIView(frame: .mockRandom())
        view.dd.sessionReplayPrivacyOverrides.touchPrivacy = .show

        let touch = UITouchMock(phase: .began, location: .mockRandom(), view: view)
        let touchEvent = UITouchEventMock(touches: [touch])

        let producer = WindowTouchSnapshotProducer(
            windowObserver: mockWindowObserver
        )

        // When
        producer.notify_sendEvent(application: mockApplication, event: touchEvent)
        let snapshot = producer.takeSnapshot(context: .mockAny())

        // Then
        XCTAssertNotNil(snapshot, "Touches in a view with touch privacy override `.show` should be recorded even when global setting is `.hide`")
        XCTAssertEqual(snapshot?.touches.count, 1, "It should record one touch event")
    }

    func testWhenParentViewHasTouchOverrideSetToShow_touchesInChildViewsAreRecorded() {
        // Given
        let parentView = UIView(frame: .mockRandom())
        parentView.dd.sessionReplayPrivacyOverrides.touchPrivacy = .show

        let childView = UIView(frame: .mockRandom())
        parentView.addSubview(childView)

        let touch = UITouchMock(phase: .began, location: .mockRandom(), view: childView)
        let touchEvent = UITouchEventMock(touches: [touch])

        let producer = WindowTouchSnapshotProducer(
            windowObserver: mockWindowObserver
        )

        // When
        producer.notify_sendEvent(application: mockApplication, event: touchEvent)
        let snapshot = producer.takeSnapshot(context: .mockAny())

        // Then
        XCTAssertNotNil(snapshot, "Touches in a view with touch privacy override `.show` should be recorded even when global setting is `.hide`")
        XCTAssertEqual(snapshot?.touches.count, 1, "It should record one touch event")
    }

    // MARK: Touch Override Cache Tests
    func testTouchPrivacyOverrideIsNilByDefault() {
        // Given
        let touch = UITouchMock()

        // Then
        XCTAssertNil(touch.touchPrivacyOverride, "The associated touchPrivacyOverride should be nil by default")
    }

    func testSettingAndGettingTouchPrivacyOverride() {
        // Given
        let touch = UITouchMock()
        let expectedOverride: TouchPrivacyLevel = .show

        // When
        touch.touchPrivacyOverride = expectedOverride

        // Then
        XCTAssertEqual(touch.touchPrivacyOverride, expectedOverride, "The associated touchPrivacyOverride should be correctly set and retrieved")
    }
}
#endif
