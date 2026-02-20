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

// MARK: - Mock Predicate

private class MockScrollPredicate: UITouchRUMActionsPredicate {
    var result: RUMAction?

    init(result: RUMAction? = RUMAction(name: "UIScrollView", attributes: [:])) {
        self.result = result
    }

    func rumAction(targetView: UIView) -> RUMAction? {
        return result
    }
}

// MARK: - Mock Scroll View

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

// MARK: - Tests

class UIScrollViewScrollHandlerTests: XCTestCase {
    private let dateProvider = RelativeDateProvider(using: .mockDecember15th2019At10AMUTC())
    private let commandSubscriber = RUMCommandSubscriberMock()

    private func createHandler(
        predicate: UITouchRUMActionsPredicate = MockScrollPredicate()
    ) -> UIScrollViewScrollHandler {
        let handler = UIScrollViewScrollHandler(
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

    // MARK: - Start Command Tests

    func testWhenUserInitiatedScrollBegins_itSendsStartCommand() {
        let handler = createHandler()
        let scrollView = createMockScrollView(panState: .began, contentOffset: CGPoint(x: 0, y: 0))

        // When
        handler.scrollViewWillBeginDragging(scrollView)

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 1)
        let command = commandSubscriber.receivedCommands[0] as? RUMStartUserActionCommand
        XCTAssertNotNil(command)
        XCTAssertEqual(command?.actionType, .scroll)
        XCTAssertEqual(command?.name, "UIScrollView")
        XCTAssertEqual(command?.instrumentation, .uikit)
        XCTAssertEqual(command?.time, .mockDecember15th2019At10AMUTC())
    }

    func testWhenProgrammaticScroll_itDoesNotTrack() {
        let handler = createHandler()
        let scrollView = createMockScrollView(panState: .possible)

        // When
        handler.scrollViewWillBeginDragging(scrollView)

        // Then
        XCTAssertTrue(commandSubscriber.receivedCommands.isEmpty)
    }

    func testWhenPredicateReturnsNil_itDoesNotTrack() {
        let predicate = MockScrollPredicate(result: nil)
        let handler = createHandler(predicate: predicate)
        let scrollView = createMockScrollView(panState: .began)

        // When
        handler.scrollViewWillBeginDragging(scrollView)

        // Then
        XCTAssertTrue(commandSubscriber.receivedCommands.isEmpty)
    }

    // MARK: - Stop Command Tests (Without Deceleration)

    func testWhenScrollEndsWithoutDeceleration_itSendsStopCommand() {
        let handler = createHandler()
        let scrollView = createMockScrollView(panState: .began, contentOffset: CGPoint(x: 0, y: 0))

        handler.scrollViewWillBeginDragging(scrollView)

        // Simulate scroll end
        scrollView.contentOffset = CGPoint(x: 0, y: 200)
        handler.scrollViewDidEndDragging(scrollView, willDecelerate: false)

        // Then: start + stop = 2 commands
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 2)
        let stopCommand = commandSubscriber.receivedCommands[1] as? RUMStopUserActionCommand
        XCTAssertNotNil(stopCommand)
        XCTAssertEqual(stopCommand?.name, "UIScrollView")
    }

    // MARK: - Stop Command Tests (With Deceleration)

    func testWhenScrollEndsWithDeceleration_itSendsStopCommandAfterDecelerating() {
        let handler = createHandler()
        let scrollView = createMockScrollView(panState: .began, contentOffset: CGPoint(x: 0, y: 0))

        handler.scrollViewWillBeginDragging(scrollView)

        // Simulate dragging ends with deceleration
        handler.scrollViewDidEndDragging(scrollView, willDecelerate: true)

        // Only start command so far
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 1)

        // Simulate deceleration ends
        scrollView.contentOffset = CGPoint(x: 0, y: 500)
        handler.scrollViewDidEndDecelerating(scrollView)

        // Now: start + stop = 2 commands
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 2)
        let stopCommand = commandSubscriber.receivedCommands[1] as? RUMStopUserActionCommand
        XCTAssertNotNil(stopCommand)
    }

    func testWhenSwipeWithDeceleration_velocityCapturedAtDragEnd() {
        let handler = createHandler()
        let panGesture = MockPanGestureRecognizer()
        panGesture.mockState = .began
        let scrollView = MockScrollView(panGesture: panGesture)
        scrollView.contentOffset = CGPoint(x: 0, y: 0)

        handler.scrollViewWillBeginDragging(scrollView)

        // At drag end, velocity is high (swipe)
        panGesture.mockVelocity = CGPoint(x: 0, y: 800)
        handler.scrollViewDidEndDragging(scrollView, willDecelerate: true)

        // After deceleration, velocity would be zero — but we captured it at drag end
        panGesture.mockVelocity = .zero
        scrollView.contentOffset = CGPoint(x: 0, y: 600)
        handler.scrollViewDidEndDecelerating(scrollView)

        let stopCommand = commandSubscriber.receivedCommands[1] as? RUMStopUserActionCommand
        XCTAssertEqual(stopCommand?.actionType, .swipe)
    }

    // MARK: - Scroll vs Swipe Classification

    func testWhenVelocityBelowThreshold_itClassifiesAsScroll() {
        let handler = createHandler()
        let panGesture = MockPanGestureRecognizer()
        panGesture.mockState = .began
        panGesture.mockVelocity = CGPoint(x: 0, y: 300) // Below 500 pts/sec
        let scrollView = MockScrollView(panGesture: panGesture)
        scrollView.contentOffset = CGPoint(x: 0, y: 0)

        handler.scrollViewWillBeginDragging(scrollView)

        scrollView.contentOffset = CGPoint(x: 0, y: 200)
        handler.scrollViewDidEndDragging(scrollView, willDecelerate: false)

        let stopCommand = commandSubscriber.receivedCommands[1] as? RUMStopUserActionCommand
        XCTAssertEqual(stopCommand?.actionType, .scroll)
    }

    func testWhenVelocityAboveThreshold_itClassifiesAsSwipe() {
        let handler = createHandler()
        let panGesture = MockPanGestureRecognizer()
        panGesture.mockState = .began
        panGesture.mockVelocity = CGPoint(x: 0, y: 600) // Above 500 pts/sec
        let scrollView = MockScrollView(panGesture: panGesture)
        scrollView.contentOffset = CGPoint(x: 0, y: 0)

        handler.scrollViewWillBeginDragging(scrollView)

        scrollView.contentOffset = CGPoint(x: 0, y: 500)
        handler.scrollViewDidEndDragging(scrollView, willDecelerate: false)

        let stopCommand = commandSubscriber.receivedCommands[1] as? RUMStopUserActionCommand
        XCTAssertEqual(stopCommand?.actionType, .swipe)
    }

    func testWhenVelocityExactlyAtThreshold_itClassifiesAsSwipe() {
        let handler = createHandler()
        let panGesture = MockPanGestureRecognizer()
        panGesture.mockState = .began
        panGesture.mockVelocity = CGPoint(x: 0, y: 500) // Exactly at threshold
        let scrollView = MockScrollView(panGesture: panGesture)
        scrollView.contentOffset = CGPoint(x: 0, y: 0)

        handler.scrollViewWillBeginDragging(scrollView)

        scrollView.contentOffset = CGPoint(x: 0, y: 300)
        handler.scrollViewDidEndDragging(scrollView, willDecelerate: false)

        let stopCommand = commandSubscriber.receivedCommands[1] as? RUMStopUserActionCommand
        XCTAssertEqual(stopCommand?.actionType, .swipe)
    }

    // MARK: - Direction Calculation

    func testDirectionCalculation_down() {
        let handler = createHandler()
        let scrollView = createMockScrollView(panState: .began, contentOffset: CGPoint(x: 0, y: 0))

        handler.scrollViewWillBeginDragging(scrollView)
        scrollView.contentOffset = CGPoint(x: 0, y: 300)
        handler.scrollViewDidEndDragging(scrollView, willDecelerate: false)

        let stopCommand = commandSubscriber.receivedCommands[1] as? RUMStopUserActionCommand
        XCTAssertEqual(
            stopCommand?.attributes[UIScrollViewScrollHandler.gestureDirectionAttribute] as? String,
            "down"
        )
    }

    func testDirectionCalculation_up() {
        let handler = createHandler()
        let scrollView = createMockScrollView(panState: .began, contentOffset: CGPoint(x: 0, y: 300))

        handler.scrollViewWillBeginDragging(scrollView)
        scrollView.contentOffset = CGPoint(x: 0, y: 0)
        handler.scrollViewDidEndDragging(scrollView, willDecelerate: false)

        let stopCommand = commandSubscriber.receivedCommands[1] as? RUMStopUserActionCommand
        XCTAssertEqual(
            stopCommand?.attributes[UIScrollViewScrollHandler.gestureDirectionAttribute] as? String,
            "up"
        )
    }

    func testDirectionCalculation_right() {
        let handler = createHandler()
        let scrollView = createMockScrollView(panState: .began, contentOffset: CGPoint(x: 0, y: 0))

        handler.scrollViewWillBeginDragging(scrollView)
        scrollView.contentOffset = CGPoint(x: 300, y: 0)
        handler.scrollViewDidEndDragging(scrollView, willDecelerate: false)

        let stopCommand = commandSubscriber.receivedCommands[1] as? RUMStopUserActionCommand
        XCTAssertEqual(
            stopCommand?.attributes[UIScrollViewScrollHandler.gestureDirectionAttribute] as? String,
            "right"
        )
    }

    func testDirectionCalculation_left() {
        let handler = createHandler()
        let scrollView = createMockScrollView(panState: .began, contentOffset: CGPoint(x: 300, y: 0))

        handler.scrollViewWillBeginDragging(scrollView)
        scrollView.contentOffset = CGPoint(x: 0, y: 0)
        handler.scrollViewDidEndDragging(scrollView, willDecelerate: false)

        let stopCommand = commandSubscriber.receivedCommands[1] as? RUMStopUserActionCommand
        XCTAssertEqual(
            stopCommand?.attributes[UIScrollViewScrollHandler.gestureDirectionAttribute] as? String,
            "left"
        )
    }

    // MARK: - Multiple Scroll Views

    func testMultipleScrollViews_trackedIndependently() {
        let handler = createHandler()
        let scrollView1 = createMockScrollView(panState: .began, contentOffset: CGPoint(x: 0, y: 0))
        let scrollView2 = createMockScrollView(panState: .began, contentOffset: CGPoint(x: 0, y: 0))

        handler.scrollViewWillBeginDragging(scrollView1)
        handler.scrollViewWillBeginDragging(scrollView2)

        // 2 start commands
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 2)

        // End first scroll view
        scrollView1.contentOffset = CGPoint(x: 0, y: 200)
        handler.scrollViewDidEndDragging(scrollView1, willDecelerate: false)

        // 2 starts + 1 stop = 3
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)

        // End second scroll view
        scrollView2.contentOffset = CGPoint(x: 0, y: 400)
        handler.scrollViewDidEndDragging(scrollView2, willDecelerate: false)

        // 2 starts + 2 stops = 4
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 4)
    }

    // MARK: - Cancel All

    func testCancelAll_cleansUpActiveScrolls() {
        let handler = createHandler()
        let scrollView = createMockScrollView(panState: .began, contentOffset: CGPoint(x: 0, y: 0))

        handler.scrollViewWillBeginDragging(scrollView)
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 1)

        handler.cancelAll()

        // End dragging after cancel — should NOT produce a stop command
        scrollView.contentOffset = CGPoint(x: 0, y: 200)
        handler.scrollViewDidEndDragging(scrollView, willDecelerate: false)

        // Still only 1 command (the start)
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 1)
    }

    // MARK: - Edge Cases

    func testFinalizingWithoutStarting_doesNotCrash() {
        let handler = createHandler()
        let scrollView = createMockScrollView()

        // Call end without start — should be a no-op
        handler.scrollViewDidEndDragging(scrollView, willDecelerate: false)
        handler.scrollViewDidEndDecelerating(scrollView)

        XCTAssertTrue(commandSubscriber.receivedCommands.isEmpty)
    }

    func testWhenNewDragStartsDuringDeceleration_previousScrollIsFinalized() {
        let handler = createHandler()
        let panGesture = MockPanGestureRecognizer()
        panGesture.mockState = .began
        panGesture.mockVelocity = CGPoint(x: 0, y: 600)
        let scrollView = MockScrollView(panGesture: panGesture)
        scrollView.contentOffset = CGPoint(x: 0, y: 0)

        // First scroll starts
        handler.scrollViewWillBeginDragging(scrollView)

        // Drag ends with deceleration
        handler.scrollViewDidEndDragging(scrollView, willDecelerate: true)

        // 1 command so far (start)
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 1)

        // User starts a new drag during deceleration
        scrollView.contentOffset = CGPoint(x: 0, y: 300)
        handler.scrollViewWillBeginDragging(scrollView)

        // Should now have: start1 + stop1 (auto-finalized) + start2 = 3 commands
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)
        XCTAssertTrue(commandSubscriber.receivedCommands[0] is RUMStartUserActionCommand)
        XCTAssertTrue(commandSubscriber.receivedCommands[1] is RUMStopUserActionCommand)
        XCTAssertTrue(commandSubscriber.receivedCommands[2] is RUMStartUserActionCommand)

        // The auto-finalized stop should have the captured velocity
        let stopCommand = commandSubscriber.receivedCommands[1] as? RUMStopUserActionCommand
        XCTAssertEqual(stopCommand?.actionType, .swipe)
    }

    func testRapidSuccessiveScrolls_eachTrackedSeparately() {
        let handler = createHandler()
        let scrollView = createMockScrollView(panState: .began, contentOffset: CGPoint(x: 0, y: 0))

        // First scroll
        handler.scrollViewWillBeginDragging(scrollView)
        scrollView.contentOffset = CGPoint(x: 0, y: 100)
        handler.scrollViewDidEndDragging(scrollView, willDecelerate: false)

        // Second scroll
        scrollView.contentOffset = CGPoint(x: 0, y: 100) // Reset start position
        handler.scrollViewWillBeginDragging(scrollView)
        scrollView.contentOffset = CGPoint(x: 0, y: 400)
        handler.scrollViewDidEndDragging(scrollView, willDecelerate: false)

        // 2 starts + 2 stops = 4 commands
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 4)

        // Both should have start commands
        XCTAssertTrue(commandSubscriber.receivedCommands[0] is RUMStartUserActionCommand)
        XCTAssertTrue(commandSubscriber.receivedCommands[1] is RUMStopUserActionCommand)
        XCTAssertTrue(commandSubscriber.receivedCommands[2] is RUMStartUserActionCommand)
        XCTAssertTrue(commandSubscriber.receivedCommands[3] is RUMStopUserActionCommand)
    }

    func testPredicateAttributes_areForwardedToStartCommand() {
        let predicate = MockScrollPredicate(
            result: RUMAction(name: "ProductList", attributes: ["custom_key": "custom_value"])
        )
        let handler = createHandler(predicate: predicate)
        let scrollView = createMockScrollView(panState: .began)

        handler.scrollViewWillBeginDragging(scrollView)

        let startCommand = commandSubscriber.receivedCommands[0] as? RUMStartUserActionCommand
        XCTAssertEqual(startCommand?.name, "ProductList")
        XCTAssertEqual(startCommand?.attributes["custom_key"] as? String, "custom_value")
    }
}

#endif
