/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogRUM

class RUMViewsHandlerTests: XCTestCase {
    private let dateProvider = RelativeDateProvider(using: .mockDecember15th2019At10AMUTC())
    private let commandSubscriber = RUMCommandSubscriberMock()
    private let notificationCenter = NotificationCenter()

    // MARK: - Helper
    private func createHandler(
        uiKitPredicate: UIKitRUMViewsPredicate? = nil,
        swiftUIPredicate: SwiftUIRUMViewsPredicate? = nil,
        swiftUIViewNameExtractor: SwiftUIViewNameExtractor? = nil
    ) -> RUMViewsHandler {
        let handler = RUMViewsHandler(
            dateProvider: dateProvider,
            uiKitPredicate: uiKitPredicate,
            swiftUIPredicate: swiftUIPredicate,
            swiftUIViewNameExtractor: swiftUIViewNameExtractor,
            notificationCenter: notificationCenter
        )
        handler.publish(to: commandSubscriber)
        return handler
    }

    // MARK: - Handling `viewDidAppear`

    func testGivenUIKitPredicate_whenViewDidAppear_itStartsRUMView() throws {
        let viewName: String = .mockRandom()
        let viewControllerClassName: String = .mockRandom()
        let view = createMockView(viewControllerClassName: viewControllerClassName)

        // Given
        let uiKitPredicate = UIKitRUMViewsPredicateMock(result: .init(name: viewName, attributes: ["foo": "bar"]))
        let handler = createHandler(uiKitPredicate: uiKitPredicate)

        // When
        handler.notify_viewDidAppear(viewController: view, animated: .mockAny())

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 1)

        let command = try XCTUnwrap(commandSubscriber.receivedCommands[0] as? RUMStartViewCommand)
        XCTAssertTrue(command.identity == ViewIdentifier(view))
        XCTAssertEqual(command.path, viewControllerClassName)
        XCTAssertEqual(command.name, viewName)
        XCTAssertEqual(command.attributes as? [String: String], ["foo": "bar"])
        XCTAssertEqual(command.instrumentationType, .uikit)
        XCTAssertEqual(command.time, .mockDecember15th2019At10AMUTC())
    }

    func testGivenUIKitPredicate_whenViewDidAppear_itStopsPreviousRUMView() throws {
        let view1 = createMockViewInWindow()
        let view2 = createMockViewInWindow()

        // Given
        let uiKitPredicate = UIKitRUMViewsPredicateMock()
        uiKitPredicate.resultByViewController = [
            view1: .init(name: .mockRandom(), attributes: ["key1": "val1"]),
            view2: .init(name: .mockRandom(), attributes: ["key2": "val2"]),
        ]
        let handler = createHandler(uiKitPredicate: uiKitPredicate)

        // When
        handler.notify_viewDidAppear(viewController: view1, animated: .mockAny())
        handler.notify_viewDidAppear(viewController: view2, animated: .mockAny())

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)

        let startCommand1 = try XCTUnwrap(commandSubscriber.receivedCommands[0] as? RUMStartViewCommand)
        let stopCommand = try XCTUnwrap(commandSubscriber.receivedCommands[1] as? RUMStopViewCommand)
        let startCommand2 = try XCTUnwrap(commandSubscriber.receivedCommands[2] as? RUMStartViewCommand)
        XCTAssertTrue(startCommand1.identity == ViewIdentifier(view1))
        XCTAssertEqual(startCommand1.attributes as? [String: String], ["key1": "val1"])
        XCTAssertTrue(stopCommand.identity == ViewIdentifier(view1))
        XCTAssertEqual(stopCommand.attributes.count, 0)
        XCTAssertTrue(startCommand2.identity == ViewIdentifier(view2))
        XCTAssertEqual(startCommand2.attributes as? [String: String], ["key2": "val2"])
    }

    func testGivenUIKitPredicate_whenViewDidAppear_itDoesNotStartTheSameRUMViewTwice() {
        let view = createMockViewInWindow()

        // Given
        let uiKitPredicate = UIKitRUMViewsPredicateMock(result: .init(name: .mockRandom()))
        let handler = createHandler(uiKitPredicate: uiKitPredicate)

        // When
        handler.notify_viewDidAppear(viewController: view, animated: .mockAny())
        handler.notify_viewDidAppear(viewController: view, animated: .mockAny())

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 1)
        XCTAssertTrue(commandSubscriber.receivedCommands[0] is RUMStartViewCommand)
    }

    func testGivenNoUIKitPredicate_whenViewDidAppear_itDoesNotStartAnyRUMView() {
        let view = createMockViewInWindow()

        // Given
        let handler = createHandler()

        // When
        handler.notify_viewDidAppear(viewController: view, animated: .mockAny())

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 0)
    }

    func testGivenSwiftUIPredicateAndNameExtractor_whenViewDidAppear_itStartsRUMView() throws {
        let viewController = createMockViewInWindow()
        let extractedName = "MySwiftUIView"
        let viewName = "CustomizedName"

        // Given
        let swiftUIViewNameExtractor = SwiftUIViewNameExtractorMock(defaultResult: extractedName)
        let swiftUIPredicate = SwiftUIRUMViewsPredicateMock(result: .init(name: viewName, attributes: ["foo": "bar"]))

        let handler = createHandler(
            swiftUIPredicate: swiftUIPredicate,
            swiftUIViewNameExtractor: swiftUIViewNameExtractor
        )

        // When
        handler.notify_viewDidAppear(viewController: viewController, animated: .mockAny())

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 1)
        let command = try XCTUnwrap(commandSubscriber.receivedCommands[0] as? RUMStartViewCommand)
        XCTAssertTrue(command.identity == ViewIdentifier(viewController))
        XCTAssertEqual(command.path, viewController.canonicalClassName)
        XCTAssertEqual(command.name, viewName)
        XCTAssertEqual(command.attributes as? [String: String], ["foo": "bar"])
        XCTAssertEqual(command.instrumentationType, .swiftui)
        XCTAssertEqual(command.time, .mockDecember15th2019At10AMUTC())
    }

    func testGivenSwiftUIPredicateAndNoNameExtractor_whenViewDidAppear_itDoesNotStartView() {
        let viewController = createMockViewInWindow()

        // Given
        let swiftUIPredicate = SwiftUIRUMViewsPredicateMock(result: .init(name: "ShouldNotBeCalled"))

        let handler = createHandler(
            swiftUIPredicate: swiftUIPredicate,
            swiftUIViewNameExtractor: nil
        )

        // When
        handler.notify_viewDidAppear(viewController: viewController, animated: true)

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 0)
    }

    func testGivenNameExtractorButNoSwiftUIPredicate_whenViewDidAppear_itDoesNotStartView() {
        let viewController = createMockViewInWindow()

        // Given
        let swiftUIViewNameExtractor = SwiftUIViewNameExtractorMock(defaultResult: "MySwiftUIView")

        let handler = createHandler(
            swiftUIPredicate: nil,
            swiftUIViewNameExtractor: swiftUIViewNameExtractor
        )

        // When
        handler.notify_viewDidAppear(viewController: viewController, animated: true)

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 0)
    }

    func testGivenSwiftUIPredicate_whenViewDidAppear_itStopsPreviousRUMView() throws {
        let view1 = createMockViewInWindow()
        let view2 = createMockViewInWindow()

        // Given
        let swiftUIViewNameExtractor = SwiftUIViewNameExtractorMock()
        swiftUIViewNameExtractor.resultByViewController = [
            view1: "view1",
            view2: "view2"
        ]

        let swiftUIPredicate = SwiftUIRUMViewsPredicateMock()
        swiftUIPredicate.resultByViewName = [
            "view1": .init(name: .mockRandom(), attributes: ["key1": "val1"]),
            "view2": .init(name: .mockRandom(), attributes: ["key2": "val2"]),
        ]
        let handler = createHandler(swiftUIPredicate: swiftUIPredicate, swiftUIViewNameExtractor: swiftUIViewNameExtractor)

        // When
        handler.notify_viewDidAppear(viewController: view1, animated: .mockAny())
        handler.notify_viewDidAppear(viewController: view2, animated: .mockAny())

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)

        let startCommand1 = try XCTUnwrap(commandSubscriber.receivedCommands[0] as? RUMStartViewCommand)
        let stopCommand = try XCTUnwrap(commandSubscriber.receivedCommands[1] as? RUMStopViewCommand)
        let startCommand2 = try XCTUnwrap(commandSubscriber.receivedCommands[2] as? RUMStartViewCommand)

        XCTAssertTrue(startCommand1.identity == ViewIdentifier(view1))
        XCTAssertEqual(startCommand1.attributes as? [String: String], ["key1": "val1"])
        XCTAssertEqual(startCommand1.instrumentationType, .swiftui)
        XCTAssertTrue(stopCommand.identity == ViewIdentifier(view1))
        XCTAssertEqual(stopCommand.attributes.count, 0)
        XCTAssertTrue(startCommand2.identity == ViewIdentifier(view2))
        XCTAssertEqual(startCommand2.attributes as? [String: String], ["key2": "val2"])
        XCTAssertEqual(startCommand2.instrumentationType, .swiftui)
    }

    func testGivenBothPredicates_whenViewDidAppear_itUsesUIKitPredicate() throws {
        let viewController = createMockViewInWindow()

        // Given
        let swiftUIViewNameExtractor = SwiftUIViewNameExtractorMock(defaultResult: "MySwiftUIView")
        let swiftUIPredicate = SwiftUIRUMViewsPredicateMock(result: .init(name: "SwiftUIName"))
        let uiKitPredicate = UIKitRUMViewsPredicateMock(result: .init(name: "UIKitName"))

        let handler = createHandler(
            uiKitPredicate: uiKitPredicate,
            swiftUIPredicate: swiftUIPredicate,
            swiftUIViewNameExtractor: swiftUIViewNameExtractor
        )

        // When
        handler.notify_viewDidAppear(viewController: viewController, animated: true)

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 1)
        let command = try XCTUnwrap(commandSubscriber.receivedCommands[0] as? RUMStartViewCommand)
        XCTAssertEqual(command.name, "UIKitName")
        XCTAssertEqual(command.instrumentationType, .uikit)
    }

    func testGivenNoUIKitPredicate_whenViewDidAppear_itFallsBackToSwiftUIPredicate() throws {
        let viewController = createMockViewInWindow()

        // Given
        let swiftUIViewNameExtractor = SwiftUIViewNameExtractorMock(defaultResult: "MySwiftUIView")
        let swiftUIPredicate = SwiftUIRUMViewsPredicateMock(result: .init(name: "SwiftUIName"))

        let handler = createHandler(
            swiftUIPredicate: swiftUIPredicate,
            swiftUIViewNameExtractor: swiftUIViewNameExtractor
        )
        handler.publish(to: commandSubscriber)

        // When
        handler.notify_viewDidAppear(viewController: viewController, animated: true)

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 1)
        let command = try XCTUnwrap(commandSubscriber.receivedCommands[0] as? RUMStartViewCommand)
        XCTAssertEqual(command.name, "SwiftUIName")
        XCTAssertEqual(command.instrumentationType, .swiftui)
    }

    // MARK: - Handling `viewDidDisappear`

    func testGivenAcceptingPredicate_whenViewDidDisappear_itStartsPreviousRUMView() throws {
        // Given
        let view1 = createMockViewInWindow()
        let view2 = createMockViewInWindow()

        // When
        let uiKitPredicate = UIKitRUMViewsPredicateMock(result: .init(name: .mockRandom()))
        let handler = createHandler(uiKitPredicate: uiKitPredicate)
        handler.notify_viewDidAppear(viewController: view1, animated: .mockAny())
        handler.notify_viewDidAppear(viewController: view2, animated: .mockAny())
        handler.notify_viewDidDisappear(viewController: view2, animated: .mockAny())

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 5)

        let startCommand1 = try XCTUnwrap(commandSubscriber.receivedCommands[0] as? RUMStartViewCommand)
        let stopCommand1 = try XCTUnwrap(commandSubscriber.receivedCommands[1] as? RUMStopViewCommand)
        let startCommand2 = try XCTUnwrap(commandSubscriber.receivedCommands[2] as? RUMStartViewCommand)
        let stopCommand2 = try XCTUnwrap(commandSubscriber.receivedCommands[3] as? RUMStopViewCommand)
        let startCommand3 = try XCTUnwrap(commandSubscriber.receivedCommands[4] as? RUMStartViewCommand)

        XCTAssertTrue(startCommand1.identity == ViewIdentifier(view1))
        XCTAssertTrue(stopCommand1.identity == ViewIdentifier(view1))
        XCTAssertTrue(startCommand2.identity == ViewIdentifier(view2))
        XCTAssertTrue(stopCommand2.identity == ViewIdentifier(view2))
        XCTAssertTrue(startCommand3.identity == ViewIdentifier(view1))
    }

    func testGivenNoActiveView_whenViewDidDisappear_itDoesNotStartAnyRUMView() {
        let view = createMockViewInWindow()

        // Given
        let uiKitPredicate = UIKitRUMViewsPredicateMock(result: .init(name: .mockRandom()))
        let handler = createHandler(uiKitPredicate: uiKitPredicate)

        // When
        handler.notify_viewDidDisappear(viewController: view, animated: .mockAny())

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 0)
    }

    func testGivenNoPredicates_whenViewDidDisappear_itDoesNotStartAnyRUMView() {
        let view1 = createMockViewInWindow()
        let view2 = createMockViewInWindow()

        // Given
        let handler = createHandler()

        // When
        handler.notify_viewDidAppear(viewController: view1, animated: .mockAny())
        handler.notify_viewDidAppear(viewController: view2, animated: .mockAny())
        handler.notify_viewDidDisappear(viewController: view2, animated: .mockAny())

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 0)
    }

    func testGivenViewControllerStarted_whenAppStateChanges_itStopsAndRestartsRUMView() throws {
        let viewName: String = .mockRandom()
        let viewControllerClassName: String = .mockRandom()
        let view = createMockView(viewControllerClassName: viewControllerClassName)

        // Given
        let uiKitPredicate = UIKitRUMViewsPredicateMock(result: .init(name: viewName, attributes: ["foo": "bar"]))
        let handler = createHandler(uiKitPredicate: uiKitPredicate)
        handler.notify_viewDidAppear(viewController: view, animated: .mockAny())

        // When
        notificationCenter.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        dateProvider.advance(bySeconds: 1)
        notificationCenter.post(name: UIApplication.willEnterForegroundNotification, object: nil)

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)

        let stopCommand = try XCTUnwrap(commandSubscriber.receivedCommands[1] as? RUMStopViewCommand)
        XCTAssertTrue(stopCommand.identity == ViewIdentifier(view))
        XCTAssertEqual(stopCommand.attributes.count, 0)
        XCTAssertEqual(stopCommand.time, .mockDecember15th2019At10AMUTC())

        let startCommand = try XCTUnwrap(commandSubscriber.receivedCommands[2] as? RUMStartViewCommand)
        XCTAssertTrue(startCommand.identity == ViewIdentifier(view))
        XCTAssertEqual(startCommand.path, viewControllerClassName)
        XCTAssertEqual(startCommand.name, viewName)
        XCTAssertEqual(startCommand.attributes as? [String: String], ["foo": "bar"])
        XCTAssertEqual(startCommand.time, .mockDecember15th2019At10AMUTC() + 1)
    }

    func testGivenViewControllerDidNotStart_whenAppStateChanges_itDoesNothing() throws {
        let view = createMockViewInWindow()
        let viewName: String = .mockRandom()

        // Given
        let uiKitPredicate = UIKitRUMViewsPredicateMock(result: .init(name: viewName, attributes: ["foo": "bar"]))
        let handler = createHandler(uiKitPredicate: uiKitPredicate)
        handler.notify_viewDidDisappear(viewController: view, animated: .mockAny())

        // When
        notificationCenter.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        dateProvider.advance(bySeconds: 1)
        notificationCenter.post(name: UIApplication.willEnterForegroundNotification, object: nil)

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 0)
    }

    // MARK: - Interacting with predicate

    func testGivenAppearedView_whenTransitioningBackAndForthFromThisViewToAnother_thenPredicateIsCalledOnlyTwice() {
        let uiKitPredicate = UIKitPredicateWithTrackingMock()
        let handler = createHandler(uiKitPredicate: uiKitPredicate)

        // Given
        let someView = createMockViewInWindow()
        let anotherView = createMockViewInWindow()

        // When
        handler.notify_viewDidAppear(viewController: anotherView, animated: .mockAny()) // 1st: `anotherView` receives "did appear"
        handler.notify_viewDidAppear(viewController: someView, animated: .mockAny()) // 2nd: `someView` receives "did disappear"
        handler.notify_viewDidAppear(viewController: anotherView, animated: .mockAny()) // 3rd: `anotherView` receives "did appear"
        handler.notify_viewDidAppear(viewController: someView, animated: .mockAny()) // 4th: `someView` receives "did disappear"
        handler.notify_viewDidAppear(viewController: anotherView, animated: .mockAny()) // 5th: `anotherView` receives "did appear"

        // Then
        XCTAssertEqual(uiKitPredicate.numberOfCalls, 2)
    }

    func testGivenAppearedView_whenTransitioningToUntrackedModal_viewDoesStop() throws {
        // Given
        let someView = createMockViewInWindow()
        let untrackedModal = createMockViewInWindow()

        let uiKitPredicate = UIKitPredicateWithModalMock(untrackedModal: untrackedModal)
        let handler = createHandler(uiKitPredicate: uiKitPredicate)

        // When
        handler.notify_viewDidAppear(viewController: someView, animated: .mockAny())
        handler.notify_viewDidAppear(viewController: untrackedModal, animated: .mockAny())

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 2)

        let startCommand = try XCTUnwrap(commandSubscriber.receivedCommands[0] as? RUMStartViewCommand)
        let stopCommand = try XCTUnwrap(commandSubscriber.receivedCommands[1] as? RUMStopViewCommand)

        XCTAssertTrue(startCommand.identity == ViewIdentifier(someView))
        XCTAssertTrue(stopCommand.identity == ViewIdentifier(someView))
    }

    func testGivenUntrackedModal_whenTransitioningToAppearedView_viewDoesStart() throws {
        // Given
        let someView = createMockViewInWindow()
        let untrackedModal = createMockViewInWindow()

        let uiKitPredicate = UIKitPredicateWithModalMock(untrackedModal: untrackedModal)
        let handler = createHandler(uiKitPredicate: uiKitPredicate)

        // When
        handler.notify_viewDidAppear(viewController: someView, animated: .mockAny())
        handler.notify_viewDidAppear(viewController: untrackedModal, animated: .mockAny())
        handler.notify_viewDidAppear(viewController: someView, animated: .mockAny())

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)

        let startCommand = try XCTUnwrap(commandSubscriber.receivedCommands[0] as? RUMStartViewCommand)
        let stopCommand = try XCTUnwrap(commandSubscriber.receivedCommands[1] as? RUMStopViewCommand)
        let startCommand2 = try XCTUnwrap(commandSubscriber.receivedCommands[2] as? RUMStartViewCommand)

        XCTAssertTrue(startCommand.identity == ViewIdentifier(someView))
        XCTAssertTrue(stopCommand.identity == ViewIdentifier(someView))
        XCTAssertTrue(startCommand2.identity == ViewIdentifier(someView))
    }

    // MARK: - Handling Manual SwiftUI Instrumentation `.onAppear`

    func testWhenOnAppear_itStartsRUMView() throws {
        // Given
        let viewIdentity: String = UUID().uuidString
        let viewName: String = .mockRandom()
        let viewPath: String = .mockRandom()
        let viewAttributes = mockRandomAttributes()

        // When
        let handler = createHandler()
        handler.notify_onAppear(
            identity: viewIdentity,
            name: viewName,
            path: viewPath,
            attributes: viewAttributes
        )

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 1)

        let command = try XCTUnwrap(commandSubscriber.receivedCommands[0] as? RUMStartViewCommand)
        XCTAssertEqual(command.time, .mockDecember15th2019At10AMUTC())
        XCTAssertTrue(command.identity == ViewIdentifier(viewIdentity))
        XCTAssertEqual(command.name, viewName)
        XCTAssertEqual(command.path, viewPath)
        DDAssertDictionariesEqual(command.attributes, viewAttributes)
    }

    func testWhenOnAppear_itStopsPreviousRUMView() throws {
        // Given
        let view1Identity: String = UUID().uuidString
        let view1Name: String = .mockRandom()
        let view1Path: String = .mockRandom()
        let view1Attributes = mockRandomAttributes()

        let view2Identity: String = UUID().uuidString
        let view2Name: String = .mockRandom()
        let view2Path: String = .mockRandom()
        let view2Attributes = mockRandomAttributes()
        let handler = createHandler()

        // When
        handler.notify_onAppear(
            identity: view1Identity,
            name: view1Name,
            path: view1Path,
            attributes: view1Attributes
        )

        handler.notify_onAppear(
            identity: view2Identity,
            name: view2Name,
            path: view2Path,
            attributes: view2Attributes
        )

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)

        let startCommand1 = try XCTUnwrap(commandSubscriber.receivedCommands[0] as? RUMStartViewCommand)
        let stopCommand = try XCTUnwrap(commandSubscriber.receivedCommands[1] as? RUMStopViewCommand)
        let startCommand2 = try XCTUnwrap(commandSubscriber.receivedCommands[2] as? RUMStartViewCommand)

        XCTAssertTrue(startCommand1.identity == ViewIdentifier(view1Identity))
        DDAssertDictionariesEqual(startCommand1.attributes, view1Attributes)
        XCTAssertTrue(stopCommand.identity == ViewIdentifier(view1Identity))
        XCTAssertEqual(stopCommand.attributes.count, 0)
        XCTAssertTrue(startCommand2.identity == ViewIdentifier(view2Identity))
        DDAssertDictionariesEqual(startCommand2.attributes, view2Attributes)
    }

    func testWhenOnAppear_itDoesNotStartTheSameRUMViewTwice() throws {
        // Given
        let viewIdentity: String = UUID().uuidString
        let viewName: String = .mockRandom()
        let viewPath: String = .mockRandom()
        let viewAttributes = mockRandomAttributes()
        let handler = createHandler()

        // When
        handler.notify_onAppear(
            identity: viewIdentity,
            name: viewName,
            path: viewPath,
            attributes: viewAttributes
        )

        handler.notify_onAppear(
            identity: viewIdentity,
            name: viewName,
            path: viewPath,
            attributes: viewAttributes
        )

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 1)
        XCTAssertTrue(commandSubscriber.receivedCommands[0] is RUMStartViewCommand)
    }

    // MARK: - Handling Manual SwiftUI Instrumentation `onDisappear`

    func testWhenOnDisappear_itDoesNotSendAnyCommand() {
        // Given
        let viewIdentity: String = UUID().uuidString
        let handler = createHandler()

        // When
        handler.notify_onDisappear(identity: viewIdentity)

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 0)
    }

    func testGivenAppearedView_whenOnDisappear_itSopsTheRUMView() throws {
        // Given
        let viewIdentity: String = UUID().uuidString
        let viewName: String = .mockRandom()
        let viewPath: String = .mockRandom()
        let viewAttributes = mockRandomAttributes()
        let handler = createHandler()

        // When
        handler.notify_onAppear(
            identity: viewIdentity,
            name: viewName,
            path: viewPath,
            attributes: viewAttributes
        )

        handler.notify_onDisappear(identity: viewIdentity)

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 2)

        let startCommand = try XCTUnwrap(commandSubscriber.receivedCommands[0] as? RUMStartViewCommand)
        let stopCommand = try XCTUnwrap(commandSubscriber.receivedCommands[1] as? RUMStopViewCommand)

        XCTAssertTrue(startCommand.identity == ViewIdentifier(viewIdentity))
        DDAssertDictionariesEqual(startCommand.attributes, viewAttributes)
        XCTAssertTrue(stopCommand.identity == ViewIdentifier(viewIdentity))
        XCTAssertEqual(stopCommand.attributes.count, 0)
    }

    func testGiven2AppearedView_whenTheFirstDisappears_itDoesNotStopItTwice() throws {
        // Given
        let view1Identity: String = UUID().uuidString
        let view1Name: String = .mockRandom()
        let view1Path: String = .mockRandom()
        let view1Attributes = mockRandomAttributes()

        let view2Identity: String = UUID().uuidString
        let view2Name: String = .mockRandom()
        let view2Path: String = .mockRandom()
        let view2Attributes = mockRandomAttributes()

        let handler = createHandler()

        // When
        handler.notify_onAppear(
            identity: view1Identity,
            name: view1Name,
            path: view1Path,
            attributes: view1Attributes
        )

        handler.notify_onAppear(
            identity: view2Identity,
            name: view2Name,
            path: view2Path,
            attributes: view2Attributes
        )

        handler.notify_onDisappear(identity: view1Identity)

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)

        let startCommand1 = try XCTUnwrap(commandSubscriber.receivedCommands[0] as? RUMStartViewCommand)
        let stopCommand1 = try XCTUnwrap(commandSubscriber.receivedCommands[1] as? RUMStopViewCommand)
        let startCommand2 = try XCTUnwrap(commandSubscriber.receivedCommands[2] as? RUMStartViewCommand)

        XCTAssertTrue(startCommand1.identity == ViewIdentifier(view1Identity))
        DDAssertDictionariesEqual(startCommand1.attributes, view1Attributes)
        XCTAssertTrue(stopCommand1.identity == ViewIdentifier(view1Identity))
        XCTAssertTrue(startCommand2.identity == ViewIdentifier(view2Identity))
        DDAssertDictionariesEqual(startCommand2.attributes, view2Attributes)
    }

    func testGiven2AppearedView_whenTheLastDisappears_itRestartsThePreviousRUMView() throws {
        // Given
        let view1Identity: String = UUID().uuidString
        let view1Name: String = .mockRandom()
        let view1Path: String = .mockRandom()
        let view1Attributes = mockRandomAttributes()

        let view2Identity: String = UUID().uuidString
        let view2Name: String = .mockRandom()
        let view2Path: String = .mockRandom()
        let view2Attributes = mockRandomAttributes()

        let handler = createHandler()

        // When
        handler.notify_onAppear(
            identity: view1Identity,
            name: view1Name,
            path: view1Path,
            attributes: view1Attributes
        )

        handler.notify_onAppear(
            identity: view2Identity,
            name: view2Name,
            path: view2Path,
            attributes: view2Attributes
        )

        handler.notify_onDisappear(identity: view2Identity)

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 5)

        let startCommand1 = try XCTUnwrap(commandSubscriber.receivedCommands[0] as? RUMStartViewCommand)
        let stopCommand1 = try XCTUnwrap(commandSubscriber.receivedCommands[1] as? RUMStopViewCommand)
        let startCommand2 = try XCTUnwrap(commandSubscriber.receivedCommands[2] as? RUMStartViewCommand)
        let stopCommand2 = try XCTUnwrap(commandSubscriber.receivedCommands[3] as? RUMStopViewCommand)
        let startCommand3 = try XCTUnwrap(commandSubscriber.receivedCommands[4] as? RUMStartViewCommand)

        XCTAssertTrue(startCommand1.identity == ViewIdentifier(view1Identity))
        DDAssertDictionariesEqual(startCommand1.attributes, view1Attributes)
        XCTAssertTrue(stopCommand1.identity == ViewIdentifier(view1Identity))
        XCTAssertTrue(startCommand2.identity == ViewIdentifier(view2Identity))
        DDAssertDictionariesEqual(startCommand2.attributes, view2Attributes)
        XCTAssertTrue(stopCommand2.identity == ViewIdentifier(view2Identity))
        XCTAssertTrue(startCommand3.identity == ViewIdentifier(view1Identity))
        DDAssertDictionariesEqual(startCommand1.attributes, view1Attributes)
    }

    // MARK: - Handling Application Activity

    func testGivenSwiftUIViewStarted_whenAppStateChanges_itStopsAndRestartsRUMView() throws {
        // Given
        let viewIdentity: String = UUID().uuidString
        let viewName: String = .mockRandom()
        let viewPath: String = .mockRandom()
        let viewAttributes = mockRandomAttributes()
        let handler = createHandler()

        // When
        handler.notify_onAppear(
            identity: viewIdentity,
            name: viewName,
            path: viewPath,
            attributes: viewAttributes
        )

        notificationCenter.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        dateProvider.advance(bySeconds: 1)
        notificationCenter.post(name: UIApplication.willEnterForegroundNotification, object: nil)

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)

        let stopCommand = try XCTUnwrap(commandSubscriber.receivedCommands[1] as? RUMStopViewCommand)
        let startCommand = try XCTUnwrap(commandSubscriber.receivedCommands[2] as? RUMStartViewCommand)
        XCTAssertTrue(stopCommand.identity == ViewIdentifier(viewIdentity))
        XCTAssertEqual(stopCommand.attributes.count, 0)
        XCTAssertEqual(stopCommand.time, .mockDecember15th2019At10AMUTC())
        XCTAssertTrue(startCommand.identity == ViewIdentifier(viewIdentity))
        XCTAssertEqual(startCommand.path, viewPath)
        XCTAssertEqual(startCommand.name, viewName)
        DDAssertDictionariesEqual(startCommand.attributes, viewAttributes)
        XCTAssertEqual(startCommand.time, .mockDecember15th2019At10AMUTC() + 1)
    }

    func testGivenSwiftUIViewDidNotStart_whenAppStateChanges_itDoesNothing() throws {
        // Given
        let viewIdentity: String = UUID().uuidString
        let handler = createHandler()

        // When
        handler.notify_onDisappear(identity: viewIdentity)

        notificationCenter.post(name: UIApplication.willResignActiveNotification, object: nil)
        dateProvider.advance(bySeconds: 1)
        notificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 0)
    }
}
