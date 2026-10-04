/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS) || os(visionOS)

import XCTest
@testable import TestUtilities
import DatadogInternal
@testable import DatadogRUM

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

private class MockScrollPredicate: UITouchRUMActionsPredicate {
    var result: RUMAction?

    init(result: RUMAction? = RUMAction(name: "UIScrollView", attributes: [:])) {
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

#if os(iOS)
@_spi(Internal) import DatadogInternal

@available(iOS 27.0, *)
@MainActor
final class SceneScrollOwnershipTests: XCTestCase {
    func testSceneScroll_capturesBeforePredicateAndNeverRechecksTerminalHierarchy() throws {
        let f = SceneScrollFixture()
        let scroll = f.scroll(in: f.windowA)
        let originalView = try XCTUnwrap(f.monitor.rumContextSnapshot(for: .scene(.init(rawValue: "a")))?.viewID)
        f.predicate.onAction = { view in
            XCTAssertEqual(RUMContextHandoff.current(for: f.owner)?.sceneIdentifier, "a")
            f.windowB.addSubview(view)
            f.startView("next-b", scene: "b")
        }
        defer { f.predicate.onAction = nil }
        var previousCalls = 0
        f.handler.interceptWillBeginDragging(scroll) {
            previousCalls += 1
            XCTAssertIdentical(scroll.window, f.windowB)
            let value = RUMContextHandoff.current(for: f.owner)
            XCTAssertEqual(value?.sceneIdentifier, "a")
            XCTAssertEqual(value?.rumContext?.viewID, originalView)
            XCTAssertEqual(value?.hasPendingUserAction, true)
        }
        let receipt = try f.receipt(at: 0)
        XCTAssertEqual(receipt.sceneIdentifier?.rawValue, "a")
        XCTAssertEqual(receipt.claim?.viewID.toRUMDataFormat, originalView)
        scroll.contentOffset = CGPoint(x: 0, y: 100)
        f.handler.interceptDidEndDragging(scroll, willDecelerate: false) {
            previousCalls += 1
            let value = RUMContextHandoff.current(for: f.owner)
            XCTAssertEqual(value?.sceneIdentifier, "a")
            XCTAssertNil(value?.rumContext)
            XCTAssertEqual(value?.hasPendingUserAction, false)
            XCTAssertNil(value?.excludedUserActionID)
        }
        XCTAssertEqual(previousCalls, 2)
        XCTAssertEqual(f.sourceProbe.reads, 1)
        XCTAssertEqual(f.events.count, 1)
        XCTAssertEqual(f.events.first?.view.id, originalView)
        XCTAssertNil(RUMContextHandoff.current(for: f.owner))
    }

    func testSceneScroll_peerGesturesAndDuplicateTerminalsDoNotShareOwners() throws {
        let f = SceneScrollFixture()
        let a = f.scroll(in: f.windowA)
        let b = f.scroll(in: f.windowB)
        f.handler.notify_scrollViewWillBeginDragging(a)
        f.handler.notify_scrollViewWillBeginDragging(b)
        let ra = try f.receipt(at: 0)
        let rb = try f.receipt(at: 1)
        XCTAssertNotEqual(ra.claim?.actionID, rb.claim?.actionID)
        a.contentOffset = CGPoint(x: 0, y: 50)
        f.handler.notify_scrollViewDidEndDragging(a, willDecelerate: false)
        f.handler.notify_scrollViewDidEndDragging(a, willDecelerate: false)
        XCTAssertEqual(f.events.count, 1)
        XCTAssertTrue(ra.isClosed)
        XCTAssertFalse(rb.isClosed)
        XCTAssertEqual(f.monitor.applicationScope.activeSession?.viewScopes.last(where: { $0.sceneIdentifier?.rawValue == "b" })?.userActionScope?.actionUUID, rb.claim?.actionID)
        XCTAssertEqual(f.monitor.applicationScope.activeSession?.viewScopes.last(where: { $0.sceneIdentifier?.rawValue == "b" })?.userActionScope?.name, "selected")
        b.mockPan.mockVelocity = CGPoint(x: 700, y: 0)
        f.handler.notify_scrollViewDidEndDragging(b, willDecelerate: true)
        XCTAssertEqual(f.events.count, 1)
        b.mockPan.mockVelocity = .zero
        b.contentOffset = CGPoint(x: 200, y: 0)
        f.handler.notify_scrollViewDidEndDecelerating(b)
        f.handler.notify_scrollViewDidEndDecelerating(b)
        XCTAssertEqual(f.monitor.commands.count, 4)
        XCTAssertEqual(f.events.count, 2)
        XCTAssertEqual(f.events.map(\.view.id), [ra.claim!.viewID.toRUMDataFormat, rb.claim!.viewID.toRUMDataFormat])
        XCTAssertEqual(f.events.map { $0.context?.contextInfo["action.gesture.direction"] as? String }, ["down", "right"])
        XCTAssertEqual(f.events.map(\.action.type), [.scroll, .swipe])
    }

    func testSceneScroll_restartStopsOldOwnerBeforeFreshStart() throws {
        let f = SceneScrollFixture()
        let scroll = f.scroll(in: f.windowA)
        f.handler.notify_scrollViewWillBeginDragging(scroll)
        let old = try f.receipt(at: 0)
        f.handler.notify_scrollViewDidEndDragging(scroll, willDecelerate: true)
        f.windowB.addSubview(scroll)
        f.predicate.onAction = { _ in
            XCTAssertEqual(RUMContextHandoff.current(for: f.owner)?.sceneIdentifier, "b")
        }
        defer { f.predicate.onAction = nil }
        f.handler.interceptWillBeginDragging(scroll) {
            XCTAssertEqual(RUMContextHandoff.current(for: f.owner)?.sceneIdentifier, "b")
            XCTAssertEqual(RUMContextHandoff.current(for: f.owner)?.hasPendingUserAction, true)
        }
        XCTAssertEqual(f.monitor.commands.count, 3)
        let terminal = try XCTUnwrap(f.monitor.commands[1] as? RUMStopUserActionCommand)
        XCTAssertEqual(terminal.target, .continuousAction(old))
        let fresh = try f.receipt(at: 2)
        XCTAssertFalse(fresh === old)
        XCTAssertEqual(fresh.sceneIdentifier?.rawValue, "b")
        XCTAssertTrue(old.isClosed)
        XCTAssertFalse(fresh.isClosed)
        XCTAssertEqual(f.monitor.publicationScenes, ["a", "a", "b"])
        XCTAssertEqual(f.monitor.publicationPending, [true, false, true])
        XCTAssertEqual(f.monitor.publicationContextPresent, [true, false, true])
    }

    func testSceneScroll_filteredRestartAndNonUserBeginPreserveExistingGesture() throws {
        let f = SceneScrollFixture()
        let scroll = f.scroll(in: f.windowA)
        f.handler.notify_scrollViewWillBeginDragging(scroll)
        let original = try f.receipt(at: 0)
        f.handler.notify_scrollViewDidEndDragging(scroll, willDecelerate: true)
        f.predicate.result = nil
        var previousCalls = 0
        f.handler.interceptWillBeginDragging(scroll) {
            previousCalls += 1
            XCTAssertEqual(RUMContextHandoff.current(for: f.owner)?.hasPendingUserAction, false)
        }
        scroll.mockPan.mockState = .possible
        f.predicate.result = RUMAction(name: "selected")
        f.handler.interceptWillBeginDragging(scroll) {
            previousCalls += 1
            XCTAssertEqual(RUMContextHandoff.current(for: f.owner)?.hasPendingUserAction, false)
        }
        XCTAssertEqual(previousCalls, 2)
        XCTAssertEqual(f.monitor.commands.count, 1)
        f.handler.notify_scrollViewDidEndDecelerating(scroll)
        XCTAssertEqual(f.monitor.commands.last?.target, .continuousAction(original))
        XCTAssertTrue(original.isClosed)
        XCTAssertEqual(f.events.count, 1)
    }

    func testSceneScroll_nestedPredicateAndDelegatesRestoreEachPublicationFrame() throws {
        let f = SceneScrollFixture()
        let a = f.scroll(in: f.windowA)
        let b = f.scroll(in: f.windowB)
        let nilSource = f.scroll(in: nil)
        var nested = false
        f.predicate.onAction = { view in
            guard view === a, !nested else { return }
            nested = true
            XCTAssertEqual(RUMContextHandoff.current(for: f.owner)?.sceneIdentifier, "a")
            f.handler.interceptWillBeginDragging(b) {
                XCTAssertEqual(RUMContextHandoff.current(for: f.owner)?.sceneIdentifier, "b")
            }
            XCTAssertEqual(RUMContextHandoff.current(for: f.owner)?.sceneIdentifier, "a")
            f.handler.interceptWillBeginDragging(nilSource) {
                XCTAssertEqual(RUMContextHandoff.current(for: f.owner)?.sceneIdentifier, "a")
            }
            XCTAssertEqual(RUMContextHandoff.current(for: f.owner)?.sceneIdentifier, "a")
        }
        defer { f.predicate.onAction = nil }
        f.handler.interceptWillBeginDragging(a) {
            XCTAssertEqual(RUMContextHandoff.current(for: f.owner)?.sceneIdentifier, "a")
            f.handler.interceptDidEndDragging(a, willDecelerate: false) {
                XCTAssertEqual(RUMContextHandoff.current(for: f.owner)?.sceneIdentifier, "a")
                XCTAssertNil(RUMContextHandoff.current(for: f.owner)?.rumContext)
                f.handler.interceptDidEndDragging(b, willDecelerate: false) {
                    XCTAssertEqual(RUMContextHandoff.current(for: f.owner)?.sceneIdentifier, "b")
                }
                XCTAssertEqual(RUMContextHandoff.current(for: f.owner)?.sceneIdentifier, "a")
            }
            XCTAssertEqual(RUMContextHandoff.current(for: f.owner)?.sceneIdentifier, "a")
            XCTAssertEqual(RUMContextHandoff.current(for: f.owner)?.hasPendingUserAction, true)
        }
        XCTAssertEqual(try f.receipt(at: 0).sceneIdentifier?.rawValue, "b")
        XCTAssertNil(try f.receipt(at: 1).sceneIdentifier)
        XCTAssertEqual(try f.receipt(at: 2).sceneIdentifier?.rawValue, "a")
        XCTAssertNil(RUMContextHandoff.current(for: f.owner))
    }

    func testSceneScroll_sameReceiverPredicateAndDelegateReentryKeepDistinctOwners() throws {
        for reenterPredicate in [false, true] {
            let f = SceneScrollFixture()
            let scroll = f.scroll(in: f.windowA)
            var nested = false
            var previousCalls = 0
            let reenter = {
                guard !nested else { return }
                nested = true
                f.windowB.addSubview(scroll)
                f.handler.interceptWillBeginDragging(scroll) {
                    previousCalls += 1
                    XCTAssertEqual(RUMContextHandoff.current(for: f.owner)?.sceneIdentifier, "b")
                }
                XCTAssertEqual(RUMContextHandoff.current(for: f.owner)?.sceneIdentifier, "a")
            }
            if reenterPredicate { f.predicate.onAction = { _ in reenter() } }
            defer { f.predicate.onAction = nil }
            f.handler.interceptWillBeginDragging(scroll) {
                previousCalls += 1
                if !reenterPredicate { reenter() }
                XCTAssertEqual(RUMContextHandoff.current(for: f.owner)?.sceneIdentifier, "a")
            }
            XCTAssertEqual(previousCalls, 2)
            XCTAssertEqual(f.monitor.commands.count, 3)
            let first = try f.receipt(at: 0)
            let last = try f.receipt(at: 2)
            XCTAssertFalse(first === last)
            XCTAssertEqual(f.monitor.commands[1].target, .continuousAction(first))
            XCTAssertEqual(first.sceneIdentifier?.rawValue, reenterPredicate ? "b" : "a")
            XCTAssertEqual(last.sceneIdentifier?.rawValue, reenterPredicate ? "a" : "b")
            XCTAssertTrue(first.isClosed)
            XCTAssertFalse(last.isClosed)
            XCTAssertNil(RUMContextHandoff.current(for: f.owner))
        }
    }

    func testSceneScroll_sourceLessInheritsButAttachedMissingSnapshotStaysAuthoritativeNil() throws {
        let f = SceneScrollFixture(startA: false)
        let outer = RUMContextHandoff.CurrentValue(rumContext: nil, sceneIdentifier: "outer", hasPendingUserAction: false, excludedUserActionID: nil)
        let absent = f.scroll(in: nil)
        let attached = f.scroll(in: f.windowA)
        XCTAssertNotNil(f.monitor.rumContextSnapshot(for: .processRepresentative))
        RUMContextHandoff.withValue(outer, for: f.owner) {
            f.handler.interceptWillBeginDragging(absent) {
                XCTAssertEqual(RUMContextHandoff.current(for: f.owner)?.sceneIdentifier, "outer")
                XCTAssertEqual(RUMContextHandoff.current(for: f.owner)?.hasPendingUserAction, false)
            }
            f.handler.interceptWillBeginDragging(attached) {
                let value = RUMContextHandoff.current(for: f.owner)
                XCTAssertNotNil(value)
                XCTAssertEqual(value?.sceneIdentifier, "a")
                XCTAssertNil(value?.rumContext)
                XCTAssertEqual(value?.hasPendingUserAction, true)
            }
            XCTAssertEqual(RUMContextHandoff.current(for: f.owner)?.sceneIdentifier, "outer")
        }
        XCTAssertNil(try f.receipt(at: 0).sceneIdentifier)
        XCTAssertEqual(try f.receipt(at: 1).sceneIdentifier?.rawValue, "a")
        XCTAssertNil(try f.receipt(at: 1).claim)
    }

    func testSceneScroll_adapterPreservesLegacyClassifierAndAttributes() throws {
        for (velocity, end, direction, swipe, deceleration) in [
            (CGPoint(x: 0, y: 499), CGPoint(x: 0, y: 40), "down", false, false),
            (CGPoint(x: 0, y: 500), CGPoint(x: 0, y: -40), "up", true, true),
            (CGPoint(x: 800, y: 0), CGPoint(x: 40, y: 0), "right", true, false),
            (CGPoint(x: 0, y: 300), CGPoint(x: -40, y: 0), "left", false, true)
        ] {
            let f = SceneScrollFixture()
            f.predicate.result = RUMAction(name: "custom-scroll", attributes: ["start-attribute": "kept"])
            let scroll = f.scroll(in: f.windowA)
            f.handler.notify_scrollViewWillBeginDragging(scroll)
            scroll.mockPan.mockVelocity = velocity
            scroll.contentOffset = end
            f.handler.notify_scrollViewDidEndDragging(scroll, willDecelerate: deceleration)
            if deceleration {
                scroll.mockPan.mockVelocity = .zero
                f.handler.notify_scrollViewDidEndDecelerating(scroll)
            }
            let start = try XCTUnwrap(f.monitor.commands.first as? RUMStartUserActionCommand)
            let stop = try XCTUnwrap(f.monitor.commands.last as? RUMStopUserActionCommand)
            XCTAssertEqual(start.name, "custom-scroll")
            XCTAssertEqual(start.instrumentation, .uikit)
            XCTAssertEqual(start.actionType, .scroll)
            XCTAssertEqual(start.attributes["start-attribute"] as? String, "kept")
            XCTAssertEqual(stop.name, "custom-scroll")
            XCTAssertEqual(stop.actionType, swipe ? .swipe : .scroll)
            XCTAssertEqual(stop.attributes[RUMScrollHandler.gestureDirectionAttribute] as? String, direction)
            XCTAssertEqual(stop.target, start.target)
            XCTAssertEqual(f.events.first?.action.target?.name, start.name)
            XCTAssertEqual(f.events.first?.context?.contextInfo["start-attribute"] as? String, "kept")
        }
    }

    func testSceneScroll_replacedSubscriberDoesNotPublishOrExposePending() {
        let f = SceneScrollFixture()
        let foreign = RUMCommandSubscriberMock()
        f.monitor.onOwnerRead = {
            if f.monitor.ownerReads == 2 { f.handler.publish(to: foreign) }
        }
        defer { f.monitor.onOwnerRead = nil }
        let scroll = f.scroll(in: f.windowA)
        var previousCalls = 0
        f.handler.interceptWillBeginDragging(scroll) {
            previousCalls += 1
            XCTAssertEqual(RUMContextHandoff.current(for: f.owner)?.sceneIdentifier, "a")
            XCTAssertEqual(RUMContextHandoff.current(for: f.owner)?.hasPendingUserAction, false)
        }
        XCTAssertEqual(previousCalls, 1)
        XCTAssertTrue(f.monitor.commands.isEmpty)
        XCTAssertTrue(foreign.receivedCommands.isEmpty)
    }

    func testSceneScroll_monitorReleasedAfterEligibilityKeepsOneNonpendingOriginalCall() {
        let owner = RUMContextHandoff.Owner()
        let clock = DateProviderMock()
        var monitor: SceneScrollMonitor? = SceneScrollMonitor(owner: owner, clock: clock)
        weak var weakMonitor = monitor
        let handler = RUMSceneScrollHandler(legacyHandler: RUMScrollHandler(dateProvider: clock, predicate: SceneScrollPredicate()), dateProvider: clock, owner: owner, expectedMonitor: monitor!, sceneIdentifier: { _ in .init(rawValue: "a") })
        handler.publish(to: monitor!)
        var ownerReads = 0
        monitor?.onOwnerRead = {
            ownerReads += 1
            if ownerReads == 2 { monitor = nil }
        }
        let window = UIWindow(frame: .zero)
        let scroll = SceneScrollView()
        window.addSubview(scroll)
        var previousCalls = 0
        handler.interceptWillBeginDragging(scroll) {
            previousCalls += 1
            XCTAssertNil(weakMonitor)
            XCTAssertEqual(RUMContextHandoff.current(for: owner)?.sceneIdentifier, "a")
            XCTAssertEqual(RUMContextHandoff.current(for: owner)?.hasPendingUserAction, false)
        }
        XCTAssertEqual(previousCalls, 1)
        XCTAssertEqual(ownerReads, 2)
        XCTAssertNil(weakMonitor)
    }

    func testSceneScroll_foreignAndInvalidatedOwnersCannotPublishAcrossLifetime() {
        for invalidate in [false, true] {
            let f = SceneScrollFixture()
            let fresh = RUMContextHandoff.Owner()
            f.predicate.onAction = { _ in
                if invalidate { f.owner.invalidate() }
                f.monitor.currentOwner = fresh
            }
            defer { f.predicate.onAction = nil }
            let scroll = f.scroll(in: f.windowA)
            var previousCalls = 0
            f.handler.interceptWillBeginDragging(scroll) {
                previousCalls += 1
                XCTAssertNil(RUMContextHandoff.current(for: fresh))
                if invalidate { XCTAssertNil(RUMContextHandoff.current(for: f.owner)) }
                else { XCTAssertEqual(RUMContextHandoff.current(for: f.owner)?.hasPendingUserAction, false) }
            }
            XCTAssertEqual(previousCalls, 1)
            XCTAssertTrue(f.monitor.commands.isEmpty)
        }
    }

    func testSceneScroll_retainsNoSourceUIOrExpectedMonitor() {
        let owner = RUMContextHandoff.Owner()
        let clock = DateProviderMock()
        var monitor: SceneScrollMonitor? = SceneScrollMonitor(owner: owner, clock: clock)
        weak var weakMonitor = monitor
        let predicate = SceneScrollPredicate()
        let handler = RUMSceneScrollHandler(legacyHandler: RUMScrollHandler(dateProvider: clock, predicate: predicate), dateProvider: clock, owner: owner, expectedMonitor: monitor!, sceneIdentifier: { _ in .init(rawValue: "a") })
        handler.publish(to: monitor!)
        weak var weakWindow: UIWindow?
        weak var weakController: UIViewController?
        weak var weakScroll: SceneScrollView?
        autoreleasepool {
            let window = UIWindow(frame: .zero)
            let controller = UIViewController()
            let scroll = SceneScrollView()
            controller.view.addSubview(scroll)
            window.rootViewController = controller
            weakWindow = window
            weakController = controller
            weakScroll = scroll
            handler.notify_scrollViewWillBeginDragging(scroll)
        }
        XCTAssertNil(weakWindow)
        XCTAssertNil(weakController)
        XCTAssertNil(weakScroll)
        let scroll = SceneScrollView()
        let window = UIWindow(frame: .zero)
        window.addSubview(scroll)
        predicate.onAction = { _ in monitor = nil }
        defer { predicate.onAction = nil }
        var previousCalls = 0
        handler.interceptWillBeginDragging(scroll) {
            previousCalls += 1
            XCTAssertNil(weakMonitor)
            XCTAssertEqual(RUMContextHandoff.current(for: owner)?.hasPendingUserAction, false)
        }
        XCTAssertEqual(previousCalls, 1)
        XCTAssertNil(weakMonitor)
    }
}

@available(iOS 27.0, *)
@MainActor
private final class SceneScrollFixture {
    let owner = RUMContextHandoff.Owner()
    let clock = DateProviderMock(now: Date(timeIntervalSince1970: 1_600_000_000))
    let windowA = UIWindow(frame: .zero)
    let windowB = UIWindow(frame: .zero)
    let predicate = SceneScrollPredicate()
    let sourceProbe = SceneScrollSourceProbe()
    let monitor: SceneScrollMonitor
    let handler: RUMSceneScrollHandler
    var events: [RUMActionEvent] { monitor.scope.eventsWritten(ofType: RUMActionEvent.self) }

    init(startA: Bool = true) {
        monitor = SceneScrollMonitor(owner: owner, clock: clock)
        let a = ObjectIdentifier(windowA), b = ObjectIdentifier(windowB), probe = sourceProbe
        handler = RUMSceneScrollHandler(legacyHandler: RUMScrollHandler(dateProvider: clock, predicate: predicate), dateProvider: clock, owner: owner, expectedMonitor: monitor, sceneIdentifier: { window in
            probe.reads += 1
            return ObjectIdentifier(window) == a ? .init(rawValue: "a") : (ObjectIdentifier(window) == b ? .init(rawValue: "b") : nil)
        })
        handler.publish(to: monitor)
        if startA { startView("a", scene: "a") }
        startView("b", scene: "b")
        monitor.ownerReads = 0
    }
    func scroll(in window: UIWindow?) -> SceneScrollView {
        let scroll = SceneScrollView()
        window?.addSubview(scroll)
        return scroll
    }
    func startView(_ key: String, scene: String) {
        monitor.process(command: RUMStartViewCommand(time: clock.now, identity: ViewIdentifier(key), name: key, path: key, globalAttributes: [:], attributes: [:], instrumentationType: .manual, target: .scene(.init(rawValue: scene))))
    }
    func receipt(at index: Int) throws -> RUMContinuousActionOwnership {
        guard case .continuousAction(let receipt) = monitor.commands[index].target else {
            throw DDAssertError.expectedFailure("Expected automatic continuous action ownership")
        }
        return receipt
    }
}

private final class SceneScrollSourceProbe { var reads = 0 }
private final class SceneScrollPredicate: UITouchRUMActionsPredicate {
    var result: RUMAction? = RUMAction(name: "selected")
    var onAction: ((UIView) -> Void)?
    func rumAction(targetView: UIView) -> RUMAction? { onAction?(targetView); return result }
}
private final class SceneScrollView: UIScrollView {
    let mockPan = MockPanGestureRecognizer()
    init() { super.init(frame: .zero) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var panGestureRecognizer: UIPanGestureRecognizer { mockPan }
}
private final class SceneScrollMonitor: Monitor {
    let scope: FeatureScopeMock
    var currentOwner: RUMContextHandoff.Owner?
    var ownerReads = 0
    var onOwnerRead: (() -> Void)?
    var commands: [RUMCommand] = []
    var publicationScenes: [String?] = []
    var publicationPending: [Bool?] = []
    var publicationContextPresent: [Bool] = []
    override var rumContextHandoffOwner: RUMContextHandoff.Owner? {
        ownerReads += 1
        let owner = currentOwner
        onOwnerRead?()
        return owner
    }
    init(owner: RUMContextHandoff.Owner, clock: DateProvider) {
        currentOwner = owner
        scope = FeatureScopeMock(context: .mockWith(sdkInitDate: clock.now, launchInfo: .mockWith(launchReason: .userLaunch, processLaunchDate: clock.now), applicationStateHistory: .mockWith(initialState: .active, date: clock.now)))
        super.init(dependencies: .mockWith(featureScope: scope, viewCache: ViewCache(dateProvider: clock, isMultiSceneTrackingEnabled: true), featureFlags: [.multiSceneTracking: true]), dateProvider: clock, executionContextProvider: RUMContextHandoff.current(for:))
    }
    override func process(command: RUMCommand) {
        if command is RUMStartUserActionCommand || command is RUMStopUserActionCommand {
            commands.append(command)
            let value = currentOwner.flatMap { RUMContextHandoff.current(for: $0) }
            publicationScenes.append(value?.sceneIdentifier)
            publicationPending.append(value?.hasPendingUserAction)
            publicationContextPresent.append(value?.rumContext != nil)
        }
        super.process(command: command)
    }
}
#endif

#if os(iOS) || os(visionOS)
@MainActor
final class LegacyScrollCompatibilityTests: XCTestCase {
    func testLegacyScroll_actionTraceAndTargetFootprint() throws {
        let clock = DateProviderMock(now: Date(timeIntervalSince1970: 1_600_000_000))
        let subscriber = RUMCommandSubscriberMock()
        let handler = RUMScrollHandler(dateProvider: clock, predicate: MockScrollPredicate(result: RUMAction(name: "compatibility-scroll", attributes: ["fixture": "legacy"])))
        handler.publish(to: subscriber)
        var trace: [[String: Any]] = []
        let delegate = CompatibilityScrollDelegate()
        delegate.onCallback = { callback in trace.append(["callback": callback, "commands": subscriber.receivedCommands.count]) }
        defer { delegate.onCallback = nil }
        let proxy = UIScrollViewDelegateProxy(originalDelegate: delegate, handler: handler)
        for velocity in [CGFloat(499), 500] {
            let pan = MockPanGestureRecognizer()
            let scroll = MockScrollView(panGesture: pan)
            proxy.scrollViewWillBeginDragging(scroll)
            pan.mockVelocity = CGPoint(x: 0, y: velocity)
            proxy.scrollViewDidEndDragging(scroll, willDecelerate: true)
            pan.mockVelocity = .zero
            scroll.contentOffset = CGPoint(x: 0, y: -100)
            proxy.scrollViewDidEndDecelerating(scroll)
            let start = try XCTUnwrap(subscriber.receivedCommands[subscriber.receivedCommands.count - 2] as? RUMStartUserActionCommand)
            let stop = try XCTUnwrap(subscriber.receivedCommands.last as? RUMStopUserActionCommand)
            XCTAssertEqual(start.target, .processRepresentative)
            XCTAssertEqual(stop.target, .processRepresentative)
            XCTAssertEqual(start.name, "compatibility-scroll")
            XCTAssertEqual(stop.name, start.name)
            XCTAssertEqual(start.attributes["fixture"] as? String, "legacy")
            XCTAssertEqual(stop.attributes[RUMScrollHandler.gestureDirectionAttribute] as? String, "up")
            XCTAssertEqual(stop.actionType, velocity < 500 ? .scroll : .swipe)
            trace.append(["name": start.name, "start_type": String(describing: start.actionType), "stop_type": String(describing: stop.actionType), "instrumentation": String(describing: start.instrumentation), "direction": "up", "fixture": "legacy", "target": "processRepresentative", "start_time": start.time.timeIntervalSince1970, "stop_time": stop.time.timeIntervalSince1970])
        }
        let data = try JSONSerialization.data(withJSONObject: ["trace": trace, "target_size": MemoryLayout<RUMCommandTarget>.size, "target_stride": MemoryLayout<RUMCommandTarget>.stride, "target_alignment": MemoryLayout<RUMCommandTarget>.alignment], options: [.sortedKeys])
        print("SCROLL_COMPATIBILITY_RESULT " + String(decoding: data, as: UTF8.self))
    }
}
private final class CompatibilityScrollDelegate: NSObject, UIScrollViewDelegate {
    var onCallback: ((String) -> Void)?
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { onCallback?("begin") }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate: Bool) { onCallback?("drag") }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { onCallback?("decelerate") }
}
#endif
