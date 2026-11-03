/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogInternal
@testable import DatadogRUM

class RUMViewsHandlerTests: XCTestCase {
    private let dateProvider = RelativeDateProvider(using: .mockDecember15th2019At10AMUTC())
    private let commandSubscriber = RUMCommandSubscriberMock()
    #if os(macOS)
    private let notificationCenterProvider = NotificationCenterProvider(applicationCenter: NotificationCenter(), workspaceCenter: NotificationCenter())
    #else
    private let notificationCenterProvider = NotificationCenterProvider(applicationCenter: NotificationCenter())
    #endif

    // MARK: - Helper
    #if !os(watchOS)
    private func createHandler(
        uiKitPredicate: DDKitRUMViewsPredicate? = nil,
        swiftUIPredicate: SwiftUIRUMViewsPredicate? = nil,
        swiftUIViewNameExtractor: SwiftUIViewNameExtractor? = nil
    ) -> RUMViewsHandler {
        let handler = RUMViewsHandler(
            dateProvider: dateProvider,
            uiKitPredicate: uiKitPredicate,
            swiftUIPredicate: swiftUIPredicate,
            swiftUIViewNameExtractor: swiftUIViewNameExtractor,
            notificationCenterProvider: notificationCenterProvider
        )
        handler.publish(to: commandSubscriber)
        return handler
    }
    #else
    private func createHandler() -> RUMViewsHandler {
        let handler = RUMViewsHandler(dateProvider: dateProvider, notificationCenterProvider: notificationCenterProvider)
        handler.publish(to: commandSubscriber)
        return handler
    }
    #endif

    // MARK: - macOS abstractions
    #if os(macOS)
    func notify(_ handler: RUMViewsHandler, viewDidAppear view: DDViewController) {
        handler.notify_viewDidAppear(viewController: view)
    }

    func notify(_ handler: RUMViewsHandler, viewDidDisappear view: DDViewController) {
        handler.notify_viewDidDisappear(viewController: view)
    }

    func postAppSuspendedNotification() {
        notificationCenterProvider.workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
    }

    func postAppResumedNotification() {
        notificationCenterProvider.workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    }

    var expectedInstrumentationType: InstrumentationType { .appkit }

    // MARK: - iOS abstractions
    #else
    #if !os(watchOS)
    func notify(_ handler: RUMViewsHandler, viewDidAppear view: DDViewController) {
        handler.notify_viewDidAppear(viewController: view, animated: .mockAny())
    }

    func notify(_ handler: RUMViewsHandler, viewDidDisappear view: DDViewController) {
        handler.notify_viewDidDisappear(viewController: view, animated: .mockAny())
    }
    #endif

    func postAppSuspendedNotification() {
        notificationCenterProvider.applicationCenter.post(name: ApplicationNotifications.didEnterBackground, object: nil)
    }

    func postAppResumedNotification() {
        notificationCenterProvider.applicationCenter.post(name: ApplicationNotifications.willEnterForeground, object: nil)
    }

    var expectedInstrumentationType: InstrumentationType { .uikit }
    #endif

    // MARK: - Handling `viewDidAppear`

    #if !os(watchOS)
    func testGivenUIKitPredicate_whenViewDidAppear_itStartsRUMView() throws {
        let viewName: String = .mockRandom()
        let viewControllerClassName: String = .mockRandom()
        let view = createMockView(viewControllerClassName: viewControllerClassName)

        // Given
        let uiKitPredicate = UIKitRUMViewsPredicateMock(result: .init(name: viewName, attributes: ["foo": "bar"]))
        let handler = createHandler(uiKitPredicate: uiKitPredicate)

        // When
        notify(handler, viewDidAppear: view)

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 1)

        let command = try XCTUnwrap(commandSubscriber.receivedCommands[0] as? RUMStartViewCommand)
        XCTAssertTrue(command.identity == ViewIdentifier(view))
        XCTAssertEqual(command.path, viewControllerClassName)
        XCTAssertEqual(command.name, viewName)
        XCTAssertEqual(command.attributes as? [String: String], ["foo": "bar"])
        XCTAssertEqual(command.instrumentationType, expectedInstrumentationType)
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
        notify(handler, viewDidAppear: view1)
        notify(handler, viewDidAppear: view2)

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)

        let startCommand1 = try XCTUnwrap(commandSubscriber.receivedCommands[0] as? RUMStartViewCommand)
        let stopCommand = try XCTUnwrap(commandSubscriber.receivedCommands[1] as? RUMStopViewCommand)
        let startCommand2 = try XCTUnwrap(commandSubscriber.receivedCommands[2] as? RUMStartViewCommand)
        XCTAssertTrue(startCommand1.identity == ViewIdentifier(view1))
        XCTAssertEqual(startCommand1.attributes as? [String: String], ["key1": "val1"])
        XCTAssertTrue(stopCommand.identity == ViewIdentifier(view1))
        XCTAssertEqual(stopCommand.attributes as? [String: String], ["key1": "val1"])
        XCTAssertTrue(startCommand2.identity == ViewIdentifier(view2))
        XCTAssertEqual(startCommand2.attributes as? [String: String], ["key2": "val2"])
    }

    func testGivenUIKitPredicate_whenViewDidAppear_itDoesNotStartTheSameRUMViewTwice() {
        let view = createMockViewInWindow()

        // Given
        let uiKitPredicate = UIKitRUMViewsPredicateMock(result: .init(name: .mockRandom()))
        let handler = createHandler(uiKitPredicate: uiKitPredicate)

        // When
        notify(handler, viewDidAppear: view)
        notify(handler, viewDidAppear: view)

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 1)
        XCTAssertTrue(commandSubscriber.receivedCommands[0] is RUMStartViewCommand)
    }

    func testGivenNoUIKitPredicate_whenViewDidAppear_itDoesNotStartAnyRUMView() {
        let view = createMockViewInWindow()

        // Given
        let handler = createHandler()

        // When
        notify(handler, viewDidAppear: view)

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
        notify(handler, viewDidAppear: viewController)

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 1)
        let command = try XCTUnwrap(commandSubscriber.receivedCommands[0] as? RUMStartViewCommand)
        XCTAssertTrue(command.identity == ViewIdentifier(viewController))
        XCTAssertEqual(command.path, viewController.canonicalClassName)
        XCTAssertEqual(command.name, viewName)
        XCTAssertEqual(command.attributes as? [String: String], ["foo": "bar"])
        XCTAssertEqual(command.instrumentationType, .swiftuiAutomatic)
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
        notify(handler, viewDidAppear: viewController)

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
        notify(handler, viewDidAppear: viewController)

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
        notify(handler, viewDidAppear: view1)
        notify(handler, viewDidAppear: view2)

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)

        let startCommand1 = try XCTUnwrap(commandSubscriber.receivedCommands[0] as? RUMStartViewCommand)
        let stopCommand = try XCTUnwrap(commandSubscriber.receivedCommands[1] as? RUMStopViewCommand)
        let startCommand2 = try XCTUnwrap(commandSubscriber.receivedCommands[2] as? RUMStartViewCommand)

        XCTAssertTrue(startCommand1.identity == ViewIdentifier(view1))
        XCTAssertEqual(startCommand1.attributes as? [String: String], ["key1": "val1"])
        XCTAssertEqual(startCommand1.instrumentationType, .swiftuiAutomatic)
        XCTAssertTrue(stopCommand.identity == ViewIdentifier(view1))
        XCTAssertEqual(stopCommand.attributes as? [String: String], ["key1": "val1"])
        XCTAssertTrue(startCommand2.identity == ViewIdentifier(view2))
        XCTAssertEqual(startCommand2.attributes as? [String: String], ["key2": "val2"])
        XCTAssertEqual(startCommand2.instrumentationType, .swiftuiAutomatic)
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
        notify(handler, viewDidAppear: viewController)

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 1)
        let command = try XCTUnwrap(commandSubscriber.receivedCommands[0] as? RUMStartViewCommand)
        XCTAssertEqual(command.name, "UIKitName")
        XCTAssertEqual(command.instrumentationType, expectedInstrumentationType)
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
        notify(handler, viewDidAppear: viewController)

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 1)
        let command = try XCTUnwrap(commandSubscriber.receivedCommands[0] as? RUMStartViewCommand)
        XCTAssertEqual(command.name, "SwiftUIName")
        XCTAssertEqual(command.instrumentationType, .swiftuiAutomatic)
    }

    // MARK: - Handling `viewDidDisappear`

    func testGivenAcceptingPredicate_whenViewDidDisappear_itStartsPreviousRUMView() throws {
        // Given
        let view1 = createMockViewInWindow()
        let view2 = createMockViewInWindow()

        // When
        let uiKitPredicate = UIKitRUMViewsPredicateMock(result: .init(name: .mockRandom()))
        let handler = createHandler(uiKitPredicate: uiKitPredicate)
        notify(handler, viewDidAppear: view1)
        notify(handler, viewDidAppear: view2)
        notify(handler, viewDidDisappear: view2)

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
        notify(handler, viewDidDisappear: view)

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 0)
    }

    func testGivenNoPredicates_whenViewDidDisappear_itDoesNotStartAnyRUMView() {
        let view1 = createMockViewInWindow()
        let view2 = createMockViewInWindow()

        // Given
        let handler = createHandler()

        // When
        notify(handler, viewDidAppear: view1)
        notify(handler, viewDidAppear: view2)
        notify(handler, viewDidDisappear: view2)

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
        notify(handler, viewDidAppear: view)

        // When
        postAppSuspendedNotification()
        dateProvider.advance(bySeconds: 1)
        postAppResumedNotification()

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 5)

        let stopCommand = try XCTUnwrap(commandSubscriber.receivedCommands[1] as? RUMStopViewCommand)
        XCTAssertTrue(stopCommand.identity == ViewIdentifier(view))
        XCTAssertEqual(stopCommand.attributes as? [String: String], ["foo": "bar"])
        XCTAssertEqual(stopCommand.time, .mockDecember15th2019At10AMUTC())

        let lifecycleCommand1 = try XCTUnwrap(commandSubscriber.receivedCommands[2] as? RUMHandleAppLifecycleEventCommand)
        XCTAssertEqual(lifecycleCommand1.event, .didEnterBackground)

        let startCommand = try XCTUnwrap(commandSubscriber.receivedCommands[3] as? RUMStartViewCommand)
        XCTAssertTrue(startCommand.identity == ViewIdentifier(view))
        XCTAssertEqual(startCommand.path, viewControllerClassName)
        XCTAssertEqual(startCommand.name, viewName)
        XCTAssertEqual(startCommand.attributes as? [String: String], ["foo": "bar"])
        XCTAssertEqual(startCommand.time, .mockDecember15th2019At10AMUTC() + 1)

        let lifecycleCommand2 = try XCTUnwrap(commandSubscriber.receivedCommands[4] as? RUMHandleAppLifecycleEventCommand)
        XCTAssertEqual(lifecycleCommand2.event, .willEnterForeground)
    }

    func testGivenViewControllerDidNotStart_whenAppStateChanges_itDoesAlterViews() throws {
        let view = createMockViewInWindow()
        let viewName: String = .mockRandom()

        // Given
        let uiKitPredicate = UIKitRUMViewsPredicateMock(result: .init(name: viewName, attributes: ["foo": "bar"]))
        let handler = createHandler(uiKitPredicate: uiKitPredicate)
        notify(handler, viewDidDisappear: view)

        // When
        postAppSuspendedNotification()
        dateProvider.advance(bySeconds: 1)
        postAppResumedNotification()

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 2)
        XCTAssertEqual((commandSubscriber.receivedCommands[0] as? RUMHandleAppLifecycleEventCommand)?.event, .didEnterBackground)
        XCTAssertEqual((commandSubscriber.receivedCommands[1] as? RUMHandleAppLifecycleEventCommand)?.event, .willEnterForeground)
    }

    // MARK: - Interacting with predicate

    func testGivenAppearedView_whenTransitioningBackAndForthFromThisViewToAnother_thenPredicateIsCalledOnlyTwice() {
        let uiKitPredicate = UIKitPredicateWithTrackingMock()
        let handler = createHandler(uiKitPredicate: uiKitPredicate)

        // Given
        let someView = createMockViewInWindow()
        let anotherView = createMockViewInWindow()

        // When
        notify(handler, viewDidAppear: anotherView)  // 1st: `anotherView` receives "did appear"
        notify(handler, viewDidAppear: someView)     // 2nd: `someView` receives "did disappear"
        notify(handler, viewDidAppear: anotherView)  // 3rd: `anotherView` receives "did appear"
        notify(handler, viewDidAppear: someView)     // 4th: `someView` receives "did disappear"
        notify(handler, viewDidAppear: anotherView)  // 5th: `anotherView` receives "did appear"

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
        notify(handler, viewDidAppear: someView)
        notify(handler, viewDidAppear: untrackedModal)

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
        notify(handler, viewDidAppear: someView)
        notify(handler, viewDidAppear: untrackedModal)
        notify(handler, viewDidAppear: someView)

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)

        let startCommand = try XCTUnwrap(commandSubscriber.receivedCommands[0] as? RUMStartViewCommand)
        let stopCommand = try XCTUnwrap(commandSubscriber.receivedCommands[1] as? RUMStopViewCommand)
        let startCommand2 = try XCTUnwrap(commandSubscriber.receivedCommands[2] as? RUMStartViewCommand)

        XCTAssertTrue(startCommand.identity == ViewIdentifier(someView))
        XCTAssertTrue(stopCommand.identity == ViewIdentifier(someView))
        XCTAssertTrue(startCommand2.identity == ViewIdentifier(someView))
    }

    #endif // !os(watchOS)

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
        XCTAssertGreaterThan(stopCommand.attributes.count, 0)
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
        XCTAssertGreaterThan(stopCommand.attributes.count, 0)
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
        DDAssertDictionariesEqual(startCommand3.attributes, view1Attributes)
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

        postAppSuspendedNotification()
        dateProvider.advance(bySeconds: 1)
        postAppResumedNotification()

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 5)

        let stopCommand = try XCTUnwrap(commandSubscriber.receivedCommands[1] as? RUMStopViewCommand)
        XCTAssertEqual((commandSubscriber.receivedCommands[2] as? RUMHandleAppLifecycleEventCommand)?.event, .didEnterBackground)
        let startCommand = try XCTUnwrap(commandSubscriber.receivedCommands[3] as? RUMStartViewCommand)
        XCTAssertEqual((commandSubscriber.receivedCommands[4] as? RUMHandleAppLifecycleEventCommand)?.event, .willEnterForeground)
        XCTAssertTrue(stopCommand.identity == ViewIdentifier(viewIdentity))
        XCTAssertGreaterThan(stopCommand.attributes.count, 0)
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

        #if os(macOS)
        // Although macOS has a `willResignActive` notification, we use `didResignActive`
        // to trigger AppState changes, so it makes more sense to test using that one,
        // since it's the notification that can trigger code in the SDK.
        notificationCenterProvider.applicationCenter.post(name: ApplicationNotifications.didResignActive, object: nil)
        #else
        notificationCenterProvider.applicationCenter.post(name: ApplicationNotifications.willResignActive, object: nil)
        #endif
        dateProvider.advance(bySeconds: 1)
        notificationCenterProvider.applicationCenter.post(name: ApplicationNotifications.didBecomeActive, object: nil)

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 0)
    }
}

#if os(iOS)
import UIKit

@MainActor
class RUMSceneViewsHandlerTests: XCTestCase {
    private final class CountingPredicate: UIKitRUMViewsPredicate {
        var calls = 0
        func rumView(for viewController: UIViewController) -> RUMView? {
            calls += 1
            return .init(name: "View")
        }
    }

    private final class Sentinel {}

    private let date = RelativeDateProvider(using: .mockDecember15th2019At10AMUTC())
    private let subscriber = RUMCommandSubscriberMock()
    private let center = NotificationCenter()
    private let sceneA = RUMSceneIdentifier(rawValue: "scene-a")
    private let sceneB = RUMSceneIdentifier(rawValue: "scene-b")
    private var owners: [ObjectIdentifier: RUMSceneIdentifier] = [:]
    private var contexts: [ObjectIdentifier: RUMSceneViewsHandler.UIKitSplitViewContext] = [:]
    private var scheduled: [() -> Void] = []

    private func makeHandler(
        predicate: UIKitRUMViewsPredicate? = UIKitRUMViewsPredicateMock(result: .init(name: "View")),
        initial: [RUMSceneIdentifier: Bool]? = nil,
        initialProvider: (() -> [RUMSceneIdentifier: Bool])? = nil,
        sceneProvider: ((UIViewController) -> RUMSceneIdentifier?)? = nil
    ) -> RUMSceneViewsHandler {
        let initial = initial ?? [sceneA: true, sceneB: true]
        let handler = RUMSceneViewsHandler(
            dateProvider: date,
            uiKitPredicate: predicate,
            swiftUIPredicate: nil,
            swiftUIViewNameExtractor: nil,
            notificationCenterProvider: .init(applicationCenter: center),
            isMultiSceneApplication: true,
            sceneIdentifierProvider: sceneProvider ?? { self.owners[ObjectIdentifier($0)] },
            sceneIdentifierFromNotification: { notification in
                (notification.object as? NSString).map { RUMSceneIdentifier(rawValue: $0 as String) }
            },
            initialSceneActivityProvider: initialProvider ?? { initial },
            uiKitSplitViewContextProvider: { self.contexts[ObjectIdentifier($0)] },
            scheduleUIKitSplitViewReconciliation: { self.scheduled.append($0) }
        )
        handler.publish(to: subscriber)
        return handler
    }

    private func appear(_ view: UIViewController, in scene: RUMSceneIdentifier?, using handler: RUMSceneViewsHandler) {
        owners[ObjectIdentifier(view)] = scene
        handler.notify_viewDidAppear(viewController: view, animated: false)
    }

    private func post(_ name: Notification.Name, scene: RUMSceneIdentifier) {
        center.post(name: name, object: scene.rawValue as NSString)
    }

    private func assertCommands(
        _ expected: [(Bool, ViewIdentifier, RUMCommandTarget)],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(subscriber.receivedCommands.count, expected.count, file: file, line: line)
        guard subscriber.receivedCommands.count == expected.count else {
            return
        }
        for (command, value) in zip(subscriber.receivedCommands, expected) {
            if value.0 {
                let start = try XCTUnwrap(command as? RUMStartViewCommand, file: file, line: line)
                XCTAssertEqual(start.identity, value.1, file: file, line: line)
                XCTAssertEqual(start.target, value.2, file: file, line: line)
            } else {
                let stop = try XCTUnwrap(command as? RUMStopViewCommand, file: file, line: line)
                XCTAssertEqual(stop.identity, value.1, file: file, line: line)
                XCTAssertEqual(stop.target, value.2, file: file, line: line)
            }
        }
    }

    func testUIKitAppearance_keepsIndependentSceneOwners() throws {
        let handler = makeHandler()
        let a = UIViewController(), b = UIViewController()
        appear(a, in: sceneA, using: handler)
        appear(b, in: sceneB, using: handler)
        try assertCommands([(true, ViewIdentifier(a), .scene(sceneA)), (true, ViewIdentifier(b), .scene(sceneB))])
    }

    func testControllerMovement_stopsCapturedOwnerAndStartsNewOwner() throws {
        let predicate = CountingPredicate()
        let handler = makeHandler(predicate: predicate)
        let view = UIViewController()
        appear(view, in: sceneA, using: handler)
        appear(view, in: sceneB, using: handler)
        try assertCommands([(true, ViewIdentifier(view), .scene(sceneA)), (false, ViewIdentifier(view), .scene(sceneA)), (true, ViewIdentifier(view), .scene(sceneB))])
        XCTAssertEqual(predicate.calls, 1)
    }

    func testDetachedDisappearance_usesCapturedOwnerWithoutSceneLookup() throws {
        var reads = 0
        let handler = makeHandler(sceneProvider: { _ in reads += 1; return self.sceneA })
        let view = UIViewController()
        handler.notify_viewDidAppear(viewController: view, animated: false)
        handler.notify_viewDidDisappear(viewController: view, animated: false)
        XCTAssertEqual(reads, 1)
        try assertCommands([(true, ViewIdentifier(view), .scene(sceneA)), (false, ViewIdentifier(view), .scene(sceneA))])
    }

    func testManualSameKey_inTwoScenesDoesNotStopPeer() throws {
        let handler = makeHandler()
        handler.startView(key: "same", name: nil, attributes: [:], sceneIdentifier: sceneA)
        handler.startView(key: "same", name: nil, attributes: [:], sceneIdentifier: sceneB)
        handler.stopView(key: "same", attributes: ["stop": "a"], sceneIdentifier: sceneA)
        try assertCommands([(true, ViewIdentifier("same"), .scene(sceneA)), (true, ViewIdentifier("same"), .scene(sceneB)), (false, ViewIdentifier("same"), .scene(sceneA))])
        XCTAssertEqual((subscriber.receivedCommands.last as? RUMStopViewCommand)?.attributes["stop"] as? String, "a")
    }

    func testManualStop_wrongKeyOrSceneCannotStopOwner() throws {
        let handler = makeHandler()
        handler.startView(key: "owned", name: nil, attributes: [:], sceneIdentifier: sceneA)
        handler.stopView(key: "owned", attributes: [:], sceneIdentifier: sceneB)
        handler.stopView(key: "foreign", attributes: [:], sceneIdentifier: sceneA)
        try assertCommands([(true, ViewIdentifier("owned"), .scene(sceneA))])
    }

    func testNestedManualAuthority_stagesPlatformBelowOwningSuffix() throws {
        let handler = makeHandler()
        let root = UIViewController(), next = UIViewController(), peer = UIViewController()
        appear(root, in: sceneA, using: handler)
        appear(peer, in: sceneB, using: handler)
        handler.startView(key: "outer", name: nil, attributes: [:], sceneIdentifier: sceneA)
        handler.startView(key: "inner", name: nil, attributes: [:], sceneIdentifier: sceneA)
        appear(next, in: sceneA, using: handler)
        handler.stopView(key: "inner", attributes: [:], sceneIdentifier: sceneA)
        handler.stopView(key: "outer", attributes: [:], sceneIdentifier: sceneA)
        try assertCommands([
            (true, ViewIdentifier(root), .scene(sceneA)), (true, ViewIdentifier(peer), .scene(sceneB)),
            (false, ViewIdentifier(root), .scene(sceneA)), (true, ViewIdentifier("outer"), .scene(sceneA)),
            (false, ViewIdentifier("outer"), .scene(sceneA)), (true, ViewIdentifier("inner"), .scene(sceneA)),
            (false, ViewIdentifier("inner"), .scene(sceneA)), (true, ViewIdentifier("outer"), .scene(sceneA)),
            (false, ViewIdentifier("outer"), .scene(sceneA)), (true, ViewIdentifier(next), .scene(sceneA)),
        ])
    }

    func testManualAuthority_retainsImmediatePlatformUntilMatchingStop() throws {
        let handler = makeHandler()
        let view = UIViewController()
        appear(view, in: sceneA, using: handler)
        handler.startView(key: "manual", name: nil, attributes: [:], sceneIdentifier: sceneA)
        handler.notify_viewDidDisappear(viewController: view, animated: false)
        handler.stopView(key: "manual", attributes: [:], sceneIdentifier: sceneA)
        try assertCommands([(true, ViewIdentifier(view), .scene(sceneA)), (false, ViewIdentifier(view), .scene(sceneA)), (true, ViewIdentifier("manual"), .scene(sceneA)), (false, ViewIdentifier("manual"), .scene(sceneA)), (true, ViewIdentifier(view), .scene(sceneA))])
    }

    func testSourceLessSwiftUIRemoval_matchesOnlyProcessStack() throws {
        let handler = makeHandler()
        handler.startView(key: "same", name: nil, attributes: [:], sceneIdentifier: sceneA)
        handler.notify_onAppear(identity: "same", name: "Process", path: "Process", attributes: [:])
        handler.notify_onDisappear(identity: "same")
        try assertCommands([(true, ViewIdentifier("same"), .scene(sceneA)), (true, ViewIdentifier("same"), .processRepresentative), (false, ViewIdentifier("same"), .processRepresentative)])
    }

    func testMissingUIKitScene_usesProcessFallback() throws {
        let handler = makeHandler()
        let view = UIViewController()
        appear(view, in: nil, using: handler)
        handler.notify_viewDidDisappear(viewController: view, animated: false)
        try assertCommands([(true, ViewIdentifier(view), .processRepresentative), (false, ViewIdentifier(view), .processRepresentative)])
    }

    func testSceneBackgroundAndForeground_doNotAffectPeerOrRepeat() throws {
        let handler = makeHandler(initial: [sceneA: true, sceneB: true])
        let a = UIViewController(), b = UIViewController()
        appear(a, in: sceneA, using: handler); appear(b, in: sceneB, using: handler)
        post(UIScene.didEnterBackgroundNotification, scene: sceneA)
        post(UIScene.didEnterBackgroundNotification, scene: sceneA)
        post(UIScene.willEnterForegroundNotification, scene: sceneA)
        post(UIScene.willEnterForegroundNotification, scene: sceneA)
        try assertCommands([(true, ViewIdentifier(a), .scene(sceneA)), (true, ViewIdentifier(b), .scene(sceneB)), (false, ViewIdentifier(a), .scene(sceneA)), (true, ViewIdentifier(a), .scene(sceneA))])
    }

    func testInitialBackgroundScene_waitsForOwnForeground() throws {
        let handler = makeHandler(initial: [sceneA: false])
        let view = UIViewController()
        appear(view, in: sceneA, using: handler)
        XCTAssertTrue(subscriber.receivedCommands.isEmpty)
        post(UIScene.willEnterForegroundNotification, scene: sceneA)
        try assertCommands([(true, ViewIdentifier(view), .scene(sceneA))])
    }

    func testInitialSceneInventory_isConsumedOnce() {
        var reads = 0
        let handler = makeHandler(initialProvider: { reads += 1; return [self.sceneA: true] })
        XCTAssertEqual(reads, 0)
        let view = UIViewController()
        appear(view, in: sceneA, using: handler)
        appear(view, in: sceneA, using: handler)
        post(UIScene.didEnterBackgroundNotification, scene: sceneA)
        XCTAssertEqual(reads, 1)
    }

    func testConnectBeforeFirstView_requiresOwnForeground() throws {
        let handler = makeHandler(initial: [:])
        post(UIScene.willConnectNotification, scene: sceneA)
        let view = UIViewController()
        appear(view, in: sceneA, using: handler)
        XCTAssertTrue(subscriber.receivedCommands.isEmpty)
        post(UIScene.willEnterForegroundNotification, scene: sceneA)
        try assertCommands([(true, ViewIdentifier(view), .scene(sceneA))])
    }

    func testUnknownScene_afterObservedLifecycleCannotPublish() {
        let handler = makeHandler(initial: [:])
        post(UIScene.willConnectNotification, scene: sceneA)
        appear(UIViewController(), in: sceneB, using: handler)
        handler.startView(key: "unknown", name: nil, attributes: [:], sceneIdentifier: sceneB)
        XCTAssertTrue(subscriber.receivedCommands.isEmpty)
    }

    func testUnknownScene_beforeLifecycleCannotPublishOrStopPeer() throws {
        let handler = makeHandler(initial: [sceneA: true])
        handler.startView(key: "peer", name: nil, attributes: [:], sceneIdentifier: sceneA)
        appear(UIViewController(), in: sceneB, using: handler)
        handler.startView(key: "unknown", name: nil, attributes: [:], sceneIdentifier: sceneB)
        handler.stopView(key: "peer", attributes: [:], sceneIdentifier: sceneB)
        post(UIScene.willEnterForegroundNotification, scene: sceneB)
        handler.startView(key: "late-unknown", name: nil, attributes: [:], sceneIdentifier: sceneB)
        try assertCommands([(true, ViewIdentifier("peer"), .scene(sceneA))])
    }

    func testForegroundAfterDisconnect_withoutConnectionCannotPublishOrStopPeer() throws {
        let handler = makeHandler(initial: [sceneA: true, sceneB: true])
        handler.startView(key: "owner", name: nil, attributes: [:], sceneIdentifier: sceneA)
        handler.startView(key: "peer", name: nil, attributes: [:], sceneIdentifier: sceneB)
        post(UIScene.didDisconnectNotification, scene: sceneA)
        post(UIScene.willEnterForegroundNotification, scene: sceneA)
        appear(UIViewController(), in: sceneA, using: handler)
        handler.startView(key: "late", name: nil, attributes: [:], sceneIdentifier: sceneA)
        handler.stopView(key: "peer", attributes: [:], sceneIdentifier: sceneA)
        try assertCommands([(true, ViewIdentifier("owner"), .scene(sceneA)), (true, ViewIdentifier("peer"), .scene(sceneB)), (false, ViewIdentifier("owner"), .scene(sceneA))])
    }

    func testDisconnect_stopsOnlyOwnerAndRejectsLateCallbacks() throws {
        let handler = makeHandler(initial: [sceneA: true, sceneB: true])
        let a = UIViewController(), b = UIViewController()
        appear(a, in: sceneA, using: handler); appear(b, in: sceneB, using: handler)
        post(UIScene.didDisconnectNotification, scene: sceneA)
        appear(a, in: sceneA, using: handler)
        handler.stopView(key: "foreign", attributes: [:], sceneIdentifier: sceneA)
        handler.notify_viewDidDisappear(viewController: a, animated: false)
        try assertCommands([(true, ViewIdentifier(a), .scene(sceneA)), (true, ViewIdentifier(b), .scene(sceneB)), (false, ViewIdentifier(a), .scene(sceneA))])
    }

    func testReconnect_sameIdentifierNeedsConnectionAndForeground() throws {
        let handler = makeHandler(initial: [sceneA: true])
        handler.startView(key: "old", name: nil, attributes: [:], sceneIdentifier: sceneA)
        post(UIScene.didDisconnectNotification, scene: sceneA)
        handler.startView(key: "late", name: nil, attributes: [:], sceneIdentifier: sceneA)
        post(UIScene.willConnectNotification, scene: sceneA)
        handler.startView(key: "new", name: nil, attributes: [:], sceneIdentifier: sceneA)
        post(UIScene.willEnterForegroundNotification, scene: sceneA)
        try assertCommands([(true, ViewIdentifier("old"), .scene(sceneA)), (false, ViewIdentifier("old"), .scene(sceneA)), (true, ViewIdentifier("new"), .scene(sceneA))])
    }

    func testApplicationForeground_resumesOnlyProcessFallback() throws {
        let handler = makeHandler(initial: [sceneA: true])
        handler.startView(key: "scene", name: nil, attributes: [:], sceneIdentifier: sceneA)
        handler.notify_onAppear(identity: "process", name: "Process", path: "Process", attributes: [:])
        center.post(name: ApplicationNotifications.didEnterBackground, object: nil)
        center.post(name: ApplicationNotifications.willEnterForeground, object: nil)
        XCTAssertEqual(subscriber.receivedCommands.count, 7)
        XCTAssertEqual((subscriber.receivedCommands[4] as? RUMHandleAppLifecycleEventCommand)?.event, .didEnterBackground)
        XCTAssertEqual((subscriber.receivedCommands[5] as? RUMStartViewCommand)?.target, .processRepresentative)
        XCTAssertEqual((subscriber.receivedCommands[6] as? RUMHandleAppLifecycleEventCommand)?.event, .willEnterForeground)
        post(UIScene.willEnterForegroundNotification, scene: sceneA)
        XCTAssertEqual((subscriber.receivedCommands.last as? RUMStartViewCommand)?.target, .scene(sceneA))
    }

    func testSplitSuccessor_preservesOwnerAndCapturedRemovalTime() throws {
        let handler = makeHandler()
        let outgoing = UIViewController(), incoming = UIViewController(), split = UIViewController()
        let context = RUMSceneViewsHandler.UIKitSplitViewContext(splitViewController: ObjectIdentifier(split), column: 2)
        contexts[ObjectIdentifier(outgoing)] = context; contexts[ObjectIdentifier(incoming)] = context
        appear(outgoing, in: sceneA, using: handler)
        let removedAt = date.now
        handler.notify_viewDidDisappear(viewController: outgoing, animated: false)
        date.advance(bySeconds: 1)
        appear(incoming, in: sceneA, using: handler)
        scheduled.forEach { $0() }
        try assertCommands([(true, ViewIdentifier(outgoing), .scene(sceneA)), (false, ViewIdentifier(outgoing), .scene(sceneA)), (true, ViewIdentifier(incoming), .scene(sceneA))])
        XCTAssertEqual((subscriber.receivedCommands[1] as? RUMStopViewCommand)?.time, removedAt)
    }

    func testSplitRevertedAppearance_doesNotReplaceOccurrenceOnSupportedRuntime() throws {
        let handler = makeHandler()
        let view = UIViewController(), split = UIViewController()
        contexts[ObjectIdentifier(view)] = .init(splitViewController: ObjectIdentifier(split), column: 2)
        appear(view, in: sceneA, using: handler)
        handler.notify_viewDidDisappear(viewController: view, animated: false)
        appear(view, in: sceneA, using: handler)
        scheduled.forEach { $0() }
        if #available(iOS 27.0, *) {
            try assertCommands([(true, ViewIdentifier(view), .scene(sceneA))])
        } else {
            try assertCommands([(true, ViewIdentifier(view), .scene(sceneA)), (false, ViewIdentifier(view), .scene(sceneA)), (true, ViewIdentifier(view), .scene(sceneA))])
            XCTAssertTrue(scheduled.isEmpty)
        }
    }

    func testSplitPendingDisconnect_invalidatesScheduledRemovalAfterReconnect() throws {
        let handler = makeHandler(initial: [sceneA: true])
        let view = UIViewController(), split = UIViewController()
        contexts[ObjectIdentifier(view)] = .init(splitViewController: ObjectIdentifier(split), column: 2)
        appear(view, in: sceneA, using: handler)
        handler.notify_viewDidDisappear(viewController: view, animated: false)
        post(UIScene.didDisconnectNotification, scene: sceneA)
        post(UIScene.willConnectNotification, scene: sceneA)
        post(UIScene.willEnterForegroundNotification, scene: sceneA)
        appear(view, in: sceneA, using: handler)
        scheduled.forEach { $0() }
        try assertCommands([(true, ViewIdentifier(view), .scene(sceneA)), (false, ViewIdentifier(view), .scene(sceneA)), (true, ViewIdentifier(view), .scene(sceneA))])
    }

    func testSplitPendingWork_isIndependentPerSceneAndBounded() {
        let handler = makeHandler(initial: [sceneA: true, sceneB: true])
        let a = UIViewController(), b = UIViewController(), split = UIViewController()
        for view in [a, b] { contexts[ObjectIdentifier(view)] = .init(splitViewController: ObjectIdentifier(split), column: 2) }
        appear(a, in: sceneA, using: handler); appear(b, in: sceneB, using: handler)
        handler.notify_viewDidDisappear(viewController: a, animated: false)
        handler.notify_viewDidDisappear(viewController: a, animated: false)
        handler.notify_viewDidDisappear(viewController: b, animated: false)
        if #available(iOS 27.0, *) { XCTAssertEqual(scheduled.count, 2) } else { XCTAssertTrue(scheduled.isEmpty) }
        scheduled.forEach { $0() }
        XCTAssertEqual(subscriber.receivedCommands.count, 4)
        XCTAssertEqual((subscriber.receivedCommands[2] as? RUMStopViewCommand)?.target, .scene(sceneA))
        XCTAssertEqual((subscriber.receivedCommands[3] as? RUMStopViewCommand)?.target, .scene(sceneB))
    }

    func testUnexpectedBackgroundCallbacks_readNoUIKitProviderOrSceneState() {
        var reads = 0
        let handler = makeHandler(sceneProvider: { _ in reads += 1; return self.sceneA })
        let view = UIViewController()
        let finished = expectation(description: "unsupported callbacks returned")
        DispatchQueue.global().async {
            handler.notify_viewDidAppear(viewController: view, animated: false)
            handler.notify_viewDidDisappear(viewController: view, animated: false)
            handler.notify_onAppear(identity: "background", name: "Background", path: "Background", attributes: [:])
            handler.notify_onDisappear(identity: "background")
            finished.fulfill()
        }
        wait(for: [finished], timeout: 5)
        XCTAssertEqual(reads, 0)
        XCTAssertTrue(subscriber.receivedCommands.isEmpty)
    }
    func testInitialProvider_releasesCaptureAfterFirstInventory() {
        var sentinel: Sentinel? = Sentinel()
        weak var weakSentinel = sentinel
        let handler = makeHandler(initialProvider: { [held = sentinel] in
            _ = held
            return [self.sceneA: true]
        })
        sentinel = nil
        XCTAssertNotNil(weakSentinel)
        appear(UIViewController(), in: sceneA, using: handler)
        XCTAssertNil(weakSentinel)
    }

    func testSubscriber_isWeakAndReleaseDoesNotRetainMonitor() throws {
        let handler = makeHandler()
        var owned: RUMCommandSubscriberMock? = RUMCommandSubscriberMock()
        weak var weakSubscriber = owned
        handler.publish(to: try XCTUnwrap(owned))
        owned = nil
        XCTAssertNil(weakSubscriber)
        XCTAssertNil(handler.subscriber)
    }
    func testControllerMovement_duringManualAuthorityCannotRestoreForeignController() throws {
        let handler = makeHandler()
        let view = UIViewController()
        appear(view, in: sceneA, using: handler)
        handler.startView(key: "manual", name: nil, attributes: [:], sceneIdentifier: sceneA)
        appear(view, in: sceneB, using: handler)
        handler.stopView(key: "manual", attributes: [:], sceneIdentifier: sceneA)
        try assertCommands([
            (true, ViewIdentifier(view), .scene(sceneA)),
            (false, ViewIdentifier(view), .scene(sceneA)),
            (true, ViewIdentifier("manual"), .scene(sceneA)),
            (true, ViewIdentifier(view), .scene(sceneB)),
            (false, ViewIdentifier("manual"), .scene(sceneA)),
        ])
    }
}
#endif
