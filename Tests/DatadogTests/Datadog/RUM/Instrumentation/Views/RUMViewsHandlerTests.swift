/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import Datadog

class RUMViewsHandlerTests: XCTestCase {
    private let dateProvider = RelativeDateProvider(using: .mockDecember15th2019At10AMUTC())
    private let commandSubscriber = RUMCommandSubscriberMock()
    private let predicate = UIKitRUMViewsPredicateMock()
    private let notificationCenter = NotificationCenter()

    private lazy var handler: RUMViewsHandler = {
        let handler = RUMViewsHandler(
            dateProvider: dateProvider,
            predicate: predicate,
            notificationCenter: notificationCenter
        )
        handler.publish(to: commandSubscriber)
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
            view1: .init(name: .mockRandom(), attributes: ["key1": "val1"]),
            view2: .init(name: .mockRandom(), attributes: ["key2": "val2"]),
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
        XCTAssertEqual(startCommand1.attributes as? [String: String], ["key1": "val1"])
        XCTAssertTrue(stopCommand.identity.equals(view1))
        XCTAssertEqual(stopCommand.attributes.count, 0)
        XCTAssertTrue(startCommand2.identity.equals(view2))
        XCTAssertEqual(startCommand2.attributes as? [String: String], ["key2": "val2"])
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

    func testGivenAcceptingPredicate_whenViewDidDisappear_itStartsPreviousRUMView() throws {
        // Given
        let view1 = createMockViewInWindow()
        let view2 = createMockViewInWindow()

        // When
        predicate.result = .init(name: .mockRandom())
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

        XCTAssertTrue(startCommand1.identity.equals(view1))
        XCTAssertTrue(stopCommand1.identity.equals(view1))
        XCTAssertTrue(startCommand2.identity.equals(view2))
        XCTAssertTrue(stopCommand2.identity.equals(view2))
        XCTAssertTrue(startCommand3.identity.equals(view1))
    }

    func testGivenAcceptingPredicate_whenViewDidDisappearButPreviousView_itDoesNotStartAnyRUMView() {
        let view = createMockViewInWindow()

        // Given
        predicate.result = .init(name: .mockRandom())

        // When
        handler.notify_viewDidDisappear(viewController: view, animated: .mockAny())

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 0)
    }

    func testGivenRejectingPredicate_whenViewDidDisappear_itDoesNotStartAnyRUMView() {
        let view1 = createMockViewInWindow()
        let view2 = createMockViewInWindow()

        // Given
        predicate.result = nil

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
        predicate.result = .init(name: viewName, attributes: ["foo": "bar"])
        handler.notify_viewDidAppear(viewController: view, animated: .mockAny())

        // When
        notificationCenter.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        dateProvider.advance(bySeconds: 1)
        notificationCenter.post(name: UIApplication.willEnterForegroundNotification, object: nil)

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)

        let stopCommand = try XCTUnwrap(commandSubscriber.receivedCommands[1] as? RUMStopViewCommand)
        XCTAssertTrue(stopCommand.identity.equals(view))
        XCTAssertEqual(stopCommand.attributes.count, 0)
        XCTAssertEqual(stopCommand.time, .mockDecember15th2019At10AMUTC())

        let startCommand = try XCTUnwrap(commandSubscriber.receivedCommands[2] as? RUMStartViewCommand)
        XCTAssertTrue(startCommand.identity.equals(view))
        XCTAssertEqual(startCommand.path, viewControllerClassName)
        XCTAssertEqual(startCommand.name, viewName)
        XCTAssertEqual(startCommand.attributes as? [String: String], ["foo": "bar"])
        XCTAssertEqual(startCommand.time, .mockDecember15th2019At10AMUTC() + 1)
    }

    func testGivenViewControllerDidNotStart_whenAppStateChanges_itDoesNothing() throws {
        let view = createMockViewInWindow()
        let viewName: String = .mockRandom()

        // Given
        predicate.result = .init(name: viewName, attributes: ["foo": "bar"])
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
        class Predicate: UIKitRUMViewsPredicate {
            var numberOfCalls = 0

            func rumView(for viewController: UIViewController) -> RUMView? {
                numberOfCalls += 1
                return .init(name: .mockRandom())
            }
        }
        let predicate = Predicate()
        let handler = RUMViewsHandler(dateProvider: dateProvider, predicate: predicate)

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
        XCTAssertEqual(predicate.numberOfCalls, 2)
    }

    func testGivenAppearedView_whenTransitioningToUntrackedModal_viewDoesStop() throws {
        class Predicate: UIKitRUMViewsPredicate {
            let untrackedModal: UIViewController

            init(untrackedModal: UIViewController) {
                self.untrackedModal = untrackedModal
            }

            func rumView(for viewController: UIViewController) -> RUMView? {
                let isUntrackedModal = viewController == untrackedModal

                return .init(name: .mockRandom(), isUntrackedModal: isUntrackedModal)
            }
        }
        // Given
        let someView = createMockViewInWindow()
        let untrackedModal = createMockViewInWindow()

        let predicate = Predicate(untrackedModal: untrackedModal)
        let handler = RUMViewsHandler(dateProvider: dateProvider, predicate: predicate)
        handler.publish(to: commandSubscriber)

        // When
        handler.notify_viewDidAppear(viewController: someView, animated: .mockAny())
        handler.notify_viewDidAppear(viewController: untrackedModal, animated: .mockAny())

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 2)

        let startCommand = try XCTUnwrap(commandSubscriber.receivedCommands[0] as? RUMStartViewCommand)
        let stopCommand = try XCTUnwrap(commandSubscriber.receivedCommands[1] as? RUMStopViewCommand)

        XCTAssertTrue(startCommand.identity.equals(someView))
        XCTAssertTrue(stopCommand.identity.equals(someView))
    }

    func testGivenUntrackedModal_whenTransitioningToAppearedView_viewDoesStart() throws {
        class Predicate: UIKitRUMViewsPredicate {
            let untrackedModal: UIViewController

            init(untrackedModal: UIViewController) {
                self.untrackedModal = untrackedModal
            }

            func rumView(for viewController: UIViewController) -> RUMView? {
                let isUntrackedModal = viewController == untrackedModal

                return .init(name: .mockRandom(), isUntrackedModal: isUntrackedModal)
            }
        }
        // Given
        let someView = createMockViewInWindow()
        let untrackedModal = createMockViewInWindow()

        let predicate = Predicate(untrackedModal: untrackedModal)
        let handler = RUMViewsHandler(dateProvider: dateProvider, predicate: predicate)
        handler.publish(to: commandSubscriber)

        // When
        handler.notify_viewDidAppear(viewController: someView, animated: .mockAny())
        handler.notify_viewDidAppear(viewController: untrackedModal, animated: .mockAny())
        handler.notify_viewDidAppear(viewController: someView, animated: .mockAny())

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)

        let startCommand = try XCTUnwrap(commandSubscriber.receivedCommands[0] as? RUMStartViewCommand)
        let stopCommand = try XCTUnwrap(commandSubscriber.receivedCommands[1] as? RUMStopViewCommand)
        let startCommand2 = try XCTUnwrap(commandSubscriber.receivedCommands[2] as? RUMStartViewCommand)

        XCTAssertTrue(startCommand.identity.equals(someView))
        XCTAssertTrue(stopCommand.identity.equals(someView))
        XCTAssertTrue(startCommand2.identity.equals(someView))
    }

    func testGiveniOS13AppearedView_whenTransitioningToModal_viewDoesStop() throws {
        if #available(iOS 13, tvOS 13, *) {
            class Predicate: UIKitRUMViewsPredicate {
                let untrackedModal: UIViewController

                init(untrackedModal: UIViewController) {
                    self.untrackedModal = untrackedModal
                }

                func rumView(for viewController: UIViewController) -> RUMView? {
                    let isUntrackedModal = viewController == untrackedModal

                    return .init(name: .mockRandom(), isUntrackedModal: isUntrackedModal)
                }
            }
            // Given
            let someView = createMockViewInWindow()
            let untrackedModal = createMockViewInWindow()
            untrackedModal.isModalInPresentation = true

            let predicate = Predicate(untrackedModal: untrackedModal)
            let handler = RUMViewsHandler(dateProvider: dateProvider, predicate: predicate)
            handler.publish(to: commandSubscriber)

            // When
            handler.notify_viewDidAppear(viewController: someView, animated: .mockAny())
            handler.notify_viewDidAppear(viewController: untrackedModal, animated: .mockAny())

            XCTAssertEqual(commandSubscriber.receivedCommands.count, 2)

            let startCommand = try XCTUnwrap(commandSubscriber.receivedCommands[0] as? RUMStartViewCommand)
            let stopCommand = try XCTUnwrap(commandSubscriber.receivedCommands[1] as? RUMStopViewCommand)

            XCTAssertTrue(startCommand.identity.equals(someView))
            XCTAssertTrue(stopCommand.identity.equals(someView))
        }
    }

    func testGiveniOS13Modal_whenTransitioningToAppearedView_viewDoesStart() throws {
        if #available(iOS 13, tvOS 13, *) {
            class Predicate: UIKitRUMViewsPredicate {
                let untrackedModal: UIViewController

                init(untrackedModal: UIViewController) {
                    self.untrackedModal = untrackedModal
                }

                func rumView(for viewController: UIViewController) -> RUMView? {
                    if viewController == untrackedModal {
                        return nil
                    }

                    return .init(name: .mockRandom())
                }
            }
            // Given
            let someView = createMockViewInWindow()
            let untrackedModal = createMockViewInWindow()
            untrackedModal.isModalInPresentation = true

            let predicate = Predicate(untrackedModal: untrackedModal)
            let handler = RUMViewsHandler(dateProvider: dateProvider, predicate: predicate)
            handler.publish(to: commandSubscriber)

            // When
            handler.notify_viewDidAppear(viewController: someView, animated: .mockAny())
            handler.notify_viewDidAppear(viewController: untrackedModal, animated: .mockAny())
            handler.notify_viewDidAppear(viewController: someView, animated: .mockAny())

            XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)

            let startCommand = try XCTUnwrap(commandSubscriber.receivedCommands[0] as? RUMStartViewCommand)
            let stopCommand = try XCTUnwrap(commandSubscriber.receivedCommands[1] as? RUMStopViewCommand)
            let startCommand2 = try XCTUnwrap(commandSubscriber.receivedCommands[2] as? RUMStartViewCommand)

            XCTAssertTrue(startCommand.identity.equals(someView))
            XCTAssertTrue(stopCommand.identity.equals(someView))
            XCTAssertTrue(startCommand2.identity.equals(someView))
        }
    }

    // MARK: - Handling SwiftUI `.onAppear`

    func testWhenOnAppear_itStartsRUMView() throws {
        // Given
        let viewIdentity: String = UUID().uuidString
        let viewName: String = .mockRandom()
        let viewPath: String = .mockRandom()
        let viewAttributes = mockRandomAttributes()

        // When
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
        XCTAssertTrue(command.identity.equals(viewIdentity))
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

        XCTAssertTrue(startCommand1.identity.equals(view1Identity))
        DDAssertDictionariesEqual(startCommand1.attributes, view1Attributes)
        XCTAssertTrue(stopCommand.identity.equals(view1Identity))
        XCTAssertEqual(stopCommand.attributes.count, 0)
        XCTAssertTrue(startCommand2.identity.equals(view2Identity))
        DDAssertDictionariesEqual(startCommand2.attributes, view2Attributes)
    }

    func testWhenOnAppear_itDoesNotStartTheSameRUMViewTwice() throws {
        // Given
        let viewIdentity: String = UUID().uuidString
        let viewName: String = .mockRandom()
        let viewPath: String = .mockRandom()
        let viewAttributes = mockRandomAttributes()

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

    // MARK: - Handling SwiftUI `onDisappear`

    func testWhenOnDisappear_itDoesNotSendAnyCommand() {
        // Given
        let viewIdentity: String = UUID().uuidString

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

        XCTAssertTrue(startCommand.identity.equals(viewIdentity))
        DDAssertDictionariesEqual(startCommand.attributes, viewAttributes)
        XCTAssertTrue(stopCommand.identity.equals(viewIdentity))
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

        XCTAssertTrue(startCommand1.identity.equals(view1Identity))
        DDAssertDictionariesEqual(startCommand1.attributes, view1Attributes)
        XCTAssertTrue(stopCommand1.identity.equals(view1Identity))
        XCTAssertTrue(startCommand2.identity.equals(view2Identity))
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

        XCTAssertTrue(startCommand1.identity.equals(view1Identity))
        DDAssertDictionariesEqual(startCommand1.attributes, view1Attributes)
        XCTAssertTrue(stopCommand1.identity.equals(view1Identity))
        XCTAssertTrue(startCommand2.identity.equals(view2Identity))
        DDAssertDictionariesEqual(startCommand2.attributes, view2Attributes)
        XCTAssertTrue(stopCommand2.identity.equals(view2Identity))
        XCTAssertTrue(startCommand3.identity.equals(view1Identity))
        DDAssertDictionariesEqual(startCommand1.attributes, view1Attributes)
    }

    // MARK: - Handling Application Activity

    func testGivenSwiftUIViewStarted_whenAppStateChanges_itStopsAndRestartsRUMView() throws {
        // Given
        let viewIdentity: String = UUID().uuidString
        let viewName: String = .mockRandom()
        let viewPath: String = .mockRandom()
        let viewAttributes = mockRandomAttributes()

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
        XCTAssertTrue(stopCommand.identity.equals(viewIdentity))
        XCTAssertEqual(stopCommand.attributes.count, 0)
        XCTAssertEqual(stopCommand.time, .mockDecember15th2019At10AMUTC())
        XCTAssertTrue(startCommand.identity.equals(viewIdentity))
        XCTAssertEqual(startCommand.path, viewPath)
        XCTAssertEqual(startCommand.name, viewName)
        DDAssertDictionariesEqual(startCommand.attributes, viewAttributes)
        XCTAssertEqual(startCommand.time, .mockDecember15th2019At10AMUTC() + 1)
    }

    func testGivenSwiftUIViewDidNotStart_whenAppStateChanges_itDoesNothing() throws {
        // Given
        let viewIdentity: String = UUID().uuidString

        // When
        handler.notify_onDisappear(identity: viewIdentity)

        notificationCenter.post(name: UIApplication.willResignActiveNotification, object: nil)
        dateProvider.advance(bySeconds: 1)
        notificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 0)
    }
}
