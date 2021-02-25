/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

private class UIKitHierarchyInspectorMock: UIKitHierarchyInspectorType {
    var mockTopViewController: UIViewController?

    func topViewController() -> UIViewController? { mockTopViewController }
}

class UIKitRUMViewsHandlerTests: XCTestCase {
    private let dateProvider = RelativeDateProvider(using: .mockDecember15th2019At10AMUTC())
    private let commandSubscriber = RUMCommandSubscriberMock()
    private let predicate = UIKitRUMViewsPredicateMock()
    private let uiKitHierarchyInspector = UIKitHierarchyInspectorMock()

    private lazy var handler: UIKitRUMViewsHandler = {
        let handler = UIKitRUMViewsHandler(
            predicate: predicate,
            dateProvider: dateProvider,
            inspector: uiKitHierarchyInspector
        )
        handler.subscribe(commandsSubscriber: commandSubscriber)
        return handler
    }()

    // MARK: - Handling `viewDidAppear`

    func testGivenAcceptingPredicate_whenViewDidAppear_itStartsRUMView() throws {
        let viewName: String = .mockRandom()
        let viewControllerClassName: String = .mockRandom()
        let view = createMockView(viewControllerClassName: viewControllerClassName)

        // Given
        predicate.result = .init(name: viewName, attributes: ["foo": "bar"])

        // When
        handler.notify_viewDidAppear(viewController: view, animated: .mockAny())

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 1)

        let command = try XCTUnwrap(commandSubscriber.receivedCommands[0] as? RUMStartViewCommand)
        XCTAssertTrue(command.identity.equals(view))
        XCTAssertEqual(command.path, viewControllerClassName)
        XCTAssertEqual(command.name, viewName)
        XCTAssertEqual(command.attributes as? [String: String], ["foo": "bar"])
        XCTAssertEqual(command.time, .mockDecember15th2019At10AMUTC())
    }

    func testGivenAcceptingPredicate_whenViewDidAppear_itStopsPreviousRUMView() throws {
        let view1 = createMockViewInWindow()
        let view2 = createMockViewInWindow()

        // Given
        predicate.resultByViewController = [
            view1: .init(name: .mockRandom()),
            view2: .init(name: .mockRandom()),
        ]

        // When
        handler.notify_viewDidAppear(viewController: view1, animated: .mockAny())
        handler.notify_viewDidAppear(viewController: view2, animated: .mockAny())

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)

        let startCommand1 = try XCTUnwrap(commandSubscriber.receivedCommands[0] as? RUMStartViewCommand)
        let stopCommand = try XCTUnwrap(commandSubscriber.receivedCommands[1] as? RUMStopViewCommand)
        let startCommand2 = try XCTUnwrap(commandSubscriber.receivedCommands[2] as? RUMStartViewCommand)
        XCTAssertTrue(startCommand1.identity.equals(view1))
        XCTAssertTrue(stopCommand.identity.equals(view1))
        XCTAssertTrue(startCommand2.identity.equals(view2))
    }

    func testGivenAcceptingPredicate_whenViewDidAppear_itDoesNotStartTheSameRUMViewTwice() {
        let view = createMockViewInWindow()

        // Given
        predicate.result = .init(name: .mockRandom())

        // When
        handler.notify_viewDidAppear(viewController: view, animated: .mockAny())
        handler.notify_viewDidAppear(viewController: view, animated: .mockAny())

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 1)
        XCTAssertTrue(commandSubscriber.receivedCommands[0] is RUMStartViewCommand)
    }

    func testGivenRejectingPredicate_whenViewDidAppear_itDoesNotStartAnyRUMView() {
        let view = createMockViewInWindow()

        // Given
        predicate.result = nil

        // When
        handler.notify_viewDidAppear(viewController: view, animated: .mockAny())

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 0)
    }

    // MARK: - Handling `viewDidDisappear`

    func testGivenAcceptingPredicate_whenViewDidDisappear_itStartsRUMViewForTopViewController() throws {
        let view = createMockViewInWindow()
        let topViewName: String = .mockRandom()
        let topViewControllerClassName: String = .mockRandom()
        let topViewController = createMockView(viewControllerClassName: topViewControllerClassName)
        uiKitHierarchyInspector.mockTopViewController = topViewController

        // Given
        predicate.resultByViewController = [
            topViewController: .init(name: topViewName)
        ]

        // When
        handler.notify_viewDidDisappear(viewController: view, animated: .mockAny())

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 1)

        let command = try XCTUnwrap(commandSubscriber.receivedCommands[0] as? RUMStartViewCommand)
        XCTAssertTrue(command.identity.equals(topViewController))
        XCTAssertEqual(command.name, topViewName)
        XCTAssertEqual(command.path, topViewControllerClassName)
        XCTAssertEqual(command.time, .mockDecember15th2019At10AMUTC())
    }

    func testGivenAcceptingPredicate_whenViewDidDisappearButThereIsNoTopViewController_itDoesNotStartAnyRUMView() {
        let view = createMockViewInWindow()
        uiKitHierarchyInspector.mockTopViewController = nil

        // Given
        predicate.result = .init(name: .mockRandom())

        // When
        handler.notify_viewDidDisappear(viewController: view, animated: .mockAny())

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 0)
    }

    func testGivenRejectingPredicate_whenViewDidDisappear_itDoesNotStartAnyRUMView() {
        let view = createMockViewInWindow()
        let topViewController = createMockViewInWindow()
        uiKitHierarchyInspector.mockTopViewController = topViewController

        // Given
        predicate.result = nil

        // When
        handler.notify_viewDidDisappear(viewController: view, animated: .mockAny())

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 0)
    }

    // MARK: - Interacting with predicate

    func testGivenHierarchyWithSomeTopView_whenTransitioningFromThisViewToAnother_thenPredicateIsCalledOnlyOnce() {
        class Predicate: UIKitRUMViewsPredicate {
            var numberOfCalls = 0

            func rumView(for viewController: UIViewController) -> RUMView? {
                numberOfCalls += 1
                return nil
            }
        }
        let predicate = Predicate()
        let handler = UIKitRUMViewsHandler(
            predicate: predicate,
            dateProvider: dateProvider,
            inspector: uiKitHierarchyInspector
        )

        // Given
        let someView = createMockViewInWindow()
        uiKitHierarchyInspector.mockTopViewController = someView

        // When
        let anotherView = createMockViewInWindow()
        uiKitHierarchyInspector.mockTopViewController = anotherView // 1st: `anotherView` is installed on top of the hierarchy
        handler.notify_viewDidDisappear(viewController: someView, animated: .mockAny()) // 2nd: `someView` receives "did disappear"
        handler.notify_viewDidAppear(viewController: anotherView, animated: .mockAny()) // 3rd: `anotherView` receives "did appear"

        // Then
        XCTAssertEqual(predicate.numberOfCalls, 1)
    }
}
