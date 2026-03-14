/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(tvOS)

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogRUM

@MainActor
class RUMScrollHandlerTests: XCTestCase {
    private let dateProvider = RelativeDateProvider(using: .mockDecember15th2019At10AMUTC())
    private let commandSubscriber = RUMCommandSubscriberMock()

    private func createHandler(
        predicate: UITouchRUMActionsPredicate = MockScrollPredicate()
    ) -> RUMScrollHandler {
        let handler = RUMScrollHandler(
            dateProvider: dateProvider,
            predicate: predicate
        )
        handler.publish(to: commandSubscriber)
        return handler
    }

    private func createMockScrollView(
        panState: UIGestureRecognizer.State = .began,
        velocity: CGPoint = .zero,
        contentOffset: CGPoint = .zero
    ) -> MockScrollView {
        let panGesture = MockPanGestureRecognizer()
        panGesture.mockState = panState
        panGesture.mockVelocity = velocity
        let scrollView = MockScrollView(panGesture: panGesture)
        scrollView.contentOffset = contentOffset
        return scrollView
    }

    // MARK: - Scroll Tracking

    func testWhenUserScrollsDown_itSendsStartAndStopCommandsWithDirectionAndType() {
        let handler = createHandler()
        let panGesture = MockPanGestureRecognizer()
        panGesture.mockState = .began
        panGesture.mockVelocity = CGPoint(x: 0, y: 300) // Below threshold = scroll
        let scrollView = MockScrollView(panGesture: panGesture)
        scrollView.contentOffset = CGPoint(x: 0, y: 0)

        // When
        handler.notify_scrollViewWillBeginDragging(scrollView)
        scrollView.contentOffset = CGPoint(x: 0, y: 300)
        handler.notify_scrollViewDidEndDragging(scrollView, willDecelerate: false)

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 2)

        let startCommand = commandSubscriber.receivedCommands[0] as? RUMStartUserActionCommand
        XCTAssertNotNil(startCommand)
        XCTAssertEqual(startCommand?.actionType, .scroll)
        XCTAssertEqual(startCommand?.name, "UIScrollView")
        XCTAssertEqual(startCommand?.instrumentation, .uikit)
        XCTAssertEqual(startCommand?.time, .mockDecember15th2019At10AMUTC())

        let stopCommand = commandSubscriber.receivedCommands[1] as? RUMStopUserActionCommand
        XCTAssertNotNil(stopCommand)
        XCTAssertEqual(stopCommand?.actionType, .scroll)
        XCTAssertEqual(stopCommand?.name, "UIScrollView")
        XCTAssertEqual(
            stopCommand?.attributes[RUMScrollHandler.gestureDirectionAttribute] as? String,
            "down"
        )
    }

    func testWhenUserSwipesUp_itClassifiesAsSwipeWithCorrectDirection() {
        let handler = createHandler()
        let panGesture = MockPanGestureRecognizer()
        panGesture.mockState = .began
        panGesture.mockVelocity = CGPoint(x: 0, y: 500) // At threshold = swipe
        let scrollView = MockScrollView(panGesture: panGesture)
        scrollView.contentOffset = CGPoint(x: 0, y: 300)

        // When
        handler.notify_scrollViewWillBeginDragging(scrollView)
        scrollView.contentOffset = CGPoint(x: 0, y: 0)
        handler.notify_scrollViewDidEndDragging(scrollView, willDecelerate: false)

        // Then
        let stopCommand = commandSubscriber.receivedCommands[1] as? RUMStopUserActionCommand
        XCTAssertEqual(stopCommand?.actionType, .swipe)
        XCTAssertEqual(
            stopCommand?.attributes[RUMScrollHandler.gestureDirectionAttribute] as? String,
            "up"
        )
    }

    func testDirectionCalculation() {
        let handler = createHandler()

        let testCases: [(start: CGPoint, end: CGPoint, expected: String)] = [
            (CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 300), "down"),
            (CGPoint(x: 0, y: 300), CGPoint(x: 0, y: 0), "up"),
            (CGPoint(x: 0, y: 0), CGPoint(x: 300, y: 0), "right"),
            (CGPoint(x: 300, y: 0), CGPoint(x: 0, y: 0), "left"),
        ]

        for testCase in testCases {
            let scrollView = createMockScrollView(panState: .began, contentOffset: testCase.start)
            handler.notify_scrollViewWillBeginDragging(scrollView)
            scrollView.contentOffset = testCase.end
            handler.notify_scrollViewDidEndDragging(scrollView, willDecelerate: false)

            let stopCommand = commandSubscriber.receivedCommands.last as? RUMStopUserActionCommand
            XCTAssertEqual(
                stopCommand?.attributes[RUMScrollHandler.gestureDirectionAttribute] as? String,
                testCase.expected,
                "Expected direction '\(testCase.expected)' for offset \(testCase.start) -> \(testCase.end)"
            )
        }
    }

    // MARK: - Deceleration

    func testWhenScrollDecelerates_velocityIsCapturedAtDragEnd() {
        let handler = createHandler()
        let panGesture = MockPanGestureRecognizer()
        panGesture.mockState = .began
        let scrollView = MockScrollView(panGesture: panGesture)
        scrollView.contentOffset = CGPoint(x: 0, y: 0)

        handler.notify_scrollViewWillBeginDragging(scrollView)

        // Velocity is high at drag end
        panGesture.mockVelocity = CGPoint(x: 0, y: 800)
        handler.notify_scrollViewDidEndDragging(scrollView, willDecelerate: true)

        // Only start command so far
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 1)

        // After deceleration, velocity resets to zero — but we captured it at drag end
        panGesture.mockVelocity = .zero
        scrollView.contentOffset = CGPoint(x: 0, y: 600)
        handler.notify_scrollViewDidEndDecelerating(scrollView)

        // Start + stop
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 2)
        let stopCommand = commandSubscriber.receivedCommands[1] as? RUMStopUserActionCommand
        XCTAssertEqual(stopCommand?.actionType, .swipe)
    }

    func testWhenNewDragStartsDuringDeceleration_previousScrollIsFinalized() {
        let handler = createHandler()
        let panGesture = MockPanGestureRecognizer()
        panGesture.mockState = .began
        panGesture.mockVelocity = CGPoint(x: 0, y: 600)
        let scrollView = MockScrollView(panGesture: panGesture)
        scrollView.contentOffset = CGPoint(x: 0, y: 0)

        handler.notify_scrollViewWillBeginDragging(scrollView)
        handler.notify_scrollViewDidEndDragging(scrollView, willDecelerate: true)

        // User re-drags during deceleration
        scrollView.contentOffset = CGPoint(x: 0, y: 300)
        handler.notify_scrollViewWillBeginDragging(scrollView)

        // start1 + stop1 (auto-finalized) + start2 = 3
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)
        XCTAssertTrue(commandSubscriber.receivedCommands[0] is RUMStartUserActionCommand)
        XCTAssertTrue(commandSubscriber.receivedCommands[1] is RUMStopUserActionCommand)
        XCTAssertTrue(commandSubscriber.receivedCommands[2] is RUMStartUserActionCommand)
    }

    // MARK: - Filtering

    func testWhenPredicateReturnsNil_itDoesNotTrack() {
        let predicate = MockScrollPredicate(result: nil)
        let handler = createHandler(predicate: predicate)
        let scrollView = createMockScrollView(panState: .began)

        handler.notify_scrollViewWillBeginDragging(scrollView)
        scrollView.contentOffset = CGPoint(x: 0, y: 100)
        handler.notify_scrollViewDidEndDragging(scrollView, willDecelerate: false)

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 0)
    }
}

// MARK: - Test Mocks

@MainActor
private class MockScrollPredicate: UITouchRUMActionsPredicate {
    var result: RUMAction?

    nonisolated init(result: RUMAction? = RUMAction(name: "UIScrollView", attributes: [:])) {
        self.result = result
    }

    func rumAction(targetView: UIView) -> RUMAction? {
        return result
    }
}

private class MockPanGestureRecognizer: UIPanGestureRecognizer {
    var mockState: UIGestureRecognizer.State = .began
    var mockVelocity: CGPoint = .zero

    override var state: UIGestureRecognizer.State {
        get { mockState }
        set { mockState = newValue }
    }

    override func velocity(in view: UIView?) -> CGPoint {
        return mockVelocity
    }
}

private class MockScrollView: UIScrollView {
    private let mockPanGesture: MockPanGestureRecognizer

    init(panGesture: MockPanGestureRecognizer) {
        self.mockPanGesture = panGesture
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var panGestureRecognizer: UIPanGestureRecognizer {
        return mockPanGesture
    }
}

#endif
