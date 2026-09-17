/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Combine
import SwiftUI
import XCTest
import TestUtilities
@testable import DatadogInternal
@_spi(Experimental)
@testable import DatadogRUM

class RUMViewsHandlerTests: XCTestCase {
    private let dateProvider = RelativeDateProvider(using: .mockDecember15th2019At10AMUTC())
    private let commandSubscriber = RUMCommandSubscriberMock()
    private let notificationCenter = NotificationCenter()

    #if os(iOS)
    @available(iOS 27.0, *)
    private struct SemanticPresentation: Identifiable, Equatable {
        let id: String
        let name: String
        let style: RUMNavigationPresentationStyle
    }

    private enum ObservedNavigationRoot: Hashable {
        case messages
        case settings
    }

    private enum ObservedNavigationRoute: Hashable, CustomStringConvertible {
        case thread(Int)
        case preferences

        var description: String {
            switch self {
            case .thread(let id): "customer-secret-thread-\(id)"
            case .preferences: "customer-secret-preferences"
            }
        }
    }

    private enum ObservedNavigationPresentation: Hashable {
        case compose(Int)
    }

    private struct ObservedNavigationState {
        let root: ObservedNavigationRoot
        var route: ObservedNavigationRoute? = nil
        var routeDepth: Int = 0
        var presentation: ObservedNavigationPresentation? = nil
        var marker: String
    }

    private struct UIKitSplitViewFixture {
        let splitViewController: UISplitViewController
        let primary: UIViewController
        let secondaryNavigationController: UINavigationController
        let secondaryRoot: UIViewController
    }

    private func createUIKitSplitViewFixture() -> UIKitSplitViewFixture {
        let splitViewController = UISplitViewController(style: .doubleColumn)
        let primary = UIViewController()
        let secondaryRoot = UIViewController()
        let secondaryNavigationController = UINavigationController(rootViewController: secondaryRoot)
        splitViewController.setViewController(primary, for: .primary)
        splitViewController.setViewController(secondaryNavigationController, for: .secondary)
        return UIKitSplitViewFixture(
            splitViewController: splitViewController,
            primary: primary,
            secondaryNavigationController: secondaryNavigationController,
            secondaryRoot: secondaryRoot
        )
    }

    private func createUIKitSplitViewContextProvider(
        fixture: UIKitSplitViewFixture,
        additionalSecondaryControllers: [UIViewController] = [],
        primaryIsStructural: Bool = false
    ) -> (UIViewController) -> RUMViewsHandler.UIKitSplitViewContext? {
        let splitViewController = ObjectIdentifier(fixture.splitViewController)
        let secondaryControllers = [fixture.secondaryRoot] + additionalSecondaryControllers
        return { viewController in
            if viewController === fixture.primary {
                return RUMViewsHandler.UIKitSplitViewContext(
                    splitViewController: splitViewController,
                    column: UISplitViewController.Column.primary.rawValue,
                    isStructural: primaryIsStructural
                )
            }
            if secondaryControllers.contains(where: { $0 === viewController }) {
                return RUMViewsHandler.UIKitSplitViewContext(
                    splitViewController: splitViewController,
                    column: UISplitViewController.Column.secondary.rawValue
                )
            }
            return nil
        }
    }

    @available(iOS 27.0, *)
    private func semanticDescriptor(
        for presentation: SemanticPresentation
    ) -> RUMNavigationPresentation {
        var view = RUMView(name: presentation.name)
        view.path = "/semantic/\(presentation.id)"
        return RUMNavigationPresentation(view: view, style: presentation.style)
    }
    #endif

    // MARK: - Helper
    #if !os(watchOS)
    private func createHandler(
        uiKitPredicate: UIKitRUMViewsPredicate? = nil,
        swiftUIPredicate: SwiftUIRUMViewsPredicate? = nil,
        swiftUIViewNameExtractor: SwiftUIViewNameExtractor? = nil,
        isSwiftUIAutomaticViewSuppressed: @escaping (UIViewController) -> Bool = { _ in false },
        isMultiSceneApplication: Bool = false,
        sceneIdentifierProvider: @escaping (UIViewController) -> RUMSceneIdentifier? = { _ in nil },
        sceneIdentifierFromNotification: @escaping (Notification) -> RUMSceneIdentifier? = { _ in nil },
        initialSceneActivityProvider: @escaping () -> [RUMSceneIdentifier: Bool] = { [:] },
        uiKitSplitViewContextProvider: ((UIViewController) -> RUMViewsHandler.UIKitSplitViewContext?)? = nil,
        scheduleUIKitSplitViewReconciliation: @escaping (@escaping () -> Void) -> Void = { work in
            DispatchQueue.main.async(execute: work)
        }
    ) -> RUMViewsHandler {
        let handler = RUMViewsHandler(
            dateProvider: dateProvider,
            uiKitPredicate: uiKitPredicate,
            swiftUIPredicate: swiftUIPredicate,
            swiftUIViewNameExtractor: swiftUIViewNameExtractor,
            isSwiftUIAutomaticViewSuppressed: isSwiftUIAutomaticViewSuppressed,
            notificationCenter: notificationCenter,
            isMultiSceneApplication: isMultiSceneApplication,
            sceneIdentifierProvider: sceneIdentifierProvider,
            sceneIdentifierFromNotification: sceneIdentifierFromNotification,
            initialSceneActivityProvider: initialSceneActivityProvider,
            uiKitSplitViewContextProvider: uiKitSplitViewContextProvider,
            scheduleUIKitSplitViewReconciliation: scheduleUIKitSplitViewReconciliation
        )
        handler.publish(to: commandSubscriber)
        return handler
    }
    #else
    private func createHandler() -> RUMViewsHandler {
        let handler = RUMViewsHandler(dateProvider: dateProvider, notificationCenter: notificationCenter)
        handler.publish(to: commandSubscriber)
        return handler
    }
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
        XCTAssertEqual(stopCommand.attributes as? [String: String], ["key1": "val1"])
        XCTAssertTrue(startCommand2.identity == ViewIdentifier(view2))
        XCTAssertEqual(startCommand2.attributes as? [String: String], ["key2": "val2"])
    }

    func testGivenViewsInDifferentScenes_whenViewDidAppear_itKeepsBothRUMViewsActive() throws {
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
        let viewA = createMockViewInWindow()
        let viewB = createMockViewInWindow()

        let uiKitPredicate = UIKitRUMViewsPredicateMock(result: .init(name: .mockRandom()))
        let handler = createHandler(
            uiKitPredicate: uiKitPredicate,
            sceneIdentifierProvider: { viewController in
                viewController === viewA ? sceneA : sceneB
            }
        )

        handler.notify_viewDidAppear(viewController: viewA, animated: false)
        handler.notify_viewDidAppear(viewController: viewB, animated: false)

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 2)
        let startA = try XCTUnwrap(commandSubscriber.receivedCommands[0] as? RUMStartViewCommand)
        let startB = try XCTUnwrap(commandSubscriber.receivedCommands[1] as? RUMStartViewCommand)
        XCTAssertEqual(startA.target, .scene(sceneA))
        XCTAssertEqual(startB.target, .scene(sceneB))
    }

    func testGivenConcurrentScenes_whenNavigatingAndReturning_itOnlyChangesOwningScene() throws {
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
        let viewA1 = createMockViewInWindow()
        let viewA2 = createMockViewInWindow()
        let viewB = createMockViewInWindow()

        let uiKitPredicate = UIKitRUMViewsPredicateMock(result: .init(name: .mockRandom()))
        let handler = createHandler(
            uiKitPredicate: uiKitPredicate,
            sceneIdentifierProvider: { viewController in
                viewController === viewB ? sceneB : sceneA
            }
        )

        handler.notify_viewDidAppear(viewController: viewA1, animated: false)
        handler.notify_viewDidAppear(viewController: viewB, animated: false)
        handler.notify_viewDidAppear(viewController: viewA2, animated: false)
        handler.notify_viewDidDisappear(viewController: viewA2, animated: false)

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 6)
        let commands = commandSubscriber.receivedCommands
        XCTAssertTrue((commands[0] as? RUMStartViewCommand)?.identity == ViewIdentifier(viewA1))
        XCTAssertTrue((commands[1] as? RUMStartViewCommand)?.identity == ViewIdentifier(viewB))
        XCTAssertTrue((commands[2] as? RUMStopViewCommand)?.identity == ViewIdentifier(viewA1))
        XCTAssertTrue((commands[3] as? RUMStartViewCommand)?.identity == ViewIdentifier(viewA2))
        XCTAssertTrue((commands[4] as? RUMStopViewCommand)?.identity == ViewIdentifier(viewA2))
        XCTAssertTrue((commands[5] as? RUMStartViewCommand)?.identity == ViewIdentifier(viewA1))
        XCTAssertEqual((commands[1] as? RUMStartViewCommand)?.target, .scene(sceneB))
        XCTAssertEqual((commands[2] as? RUMStopViewCommand)?.target, .scene(sceneA))
        XCTAssertFalse(commands.contains { command in
            (command as? RUMStopViewCommand)?.identity == ViewIdentifier(viewB)
        })
    }

    #if os(iOS)
    func testGivenMultiSceneSplitView_whenOldControllerDisappearsBeforePush_itHandoffsWithinColumn() throws {
        guard #available(iOS 27.0, *) else {
            return
        }
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let fixture = createUIKitSplitViewFixture()
        let detail = UIViewController()
        let predicate = UIKitRUMViewsPredicateMock()
        predicate.resultByViewController = [
            fixture.primary: .init(name: "Primary"),
            fixture.secondaryRoot: .init(name: "Home"),
            detail: .init(name: "Detail"),
        ]
        var scheduledReconciliations: [() -> Void] = []
        let handler = createHandler(
            uiKitPredicate: predicate,
            isMultiSceneApplication: true,
            sceneIdentifierProvider: { _ in scene },
            uiKitSplitViewContextProvider: createUIKitSplitViewContextProvider(
                fixture: fixture,
                additionalSecondaryControllers: [detail]
            ),
            scheduleUIKitSplitViewReconciliation: { scheduledReconciliations.append($0) }
        )
        handler.notify_viewDidAppear(viewController: fixture.primary, animated: false)
        handler.notify_viewDidAppear(viewController: fixture.secondaryRoot, animated: false)

        fixture.secondaryNavigationController.setViewControllers(
            [fixture.secondaryRoot, detail],
            animated: false
        )
        handler.notify_viewDidDisappear(viewController: fixture.secondaryRoot, animated: false)
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)

        dateProvider.advance(bySeconds: 1)
        handler.notify_viewDidAppear(viewController: detail, animated: false)
        scheduledReconciliations.forEach { $0() }

        let starts = commandSubscriber.receivedCommands.compactMap { $0 as? RUMStartViewCommand }
        let stops = commandSubscriber.receivedCommands.compactMap { $0 as? RUMStopViewCommand }
        XCTAssertEqual(starts.map(\.name), ["Primary", "Home", "Detail"])
        XCTAssertEqual(stops.map(\.identity), [
            ViewIdentifier(fixture.primary),
            ViewIdentifier(fixture.secondaryRoot),
        ])
        XCTAssertEqual(stops.last?.time, .mockDecember15th2019At10AMUTC())
        XCTAssertEqual(starts.last?.time, .mockDecember15th2019At10AMUTC() + 1)
        XCTAssertFalse(starts.dropFirst().contains { $0.name == "Primary" })
    }

    func testGivenMultiSceneSplitView_whenPoppingToSameController_itCreatesFreshReturnedOccurrence() throws {
        guard #available(iOS 27.0, *) else {
            return
        }
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let fixture = createUIKitSplitViewFixture()
        let detail = UIViewController()
        let predicate = UIKitRUMViewsPredicateMock()
        predicate.resultByViewController = [
            fixture.primary: .init(name: "Primary"),
            fixture.secondaryRoot: .init(name: "Home"),
            detail: .init(name: "Detail"),
        ]
        var scheduledReconciliations: [() -> Void] = []
        let handler = createHandler(
            uiKitPredicate: predicate,
            isMultiSceneApplication: true,
            sceneIdentifierProvider: { _ in scene },
            uiKitSplitViewContextProvider: createUIKitSplitViewContextProvider(
                fixture: fixture,
                additionalSecondaryControllers: [detail]
            ),
            scheduleUIKitSplitViewReconciliation: { scheduledReconciliations.append($0) }
        )
        handler.notify_viewDidAppear(viewController: fixture.primary, animated: false)
        handler.notify_viewDidAppear(viewController: fixture.secondaryRoot, animated: false)
        fixture.secondaryNavigationController.setViewControllers(
            [fixture.secondaryRoot, detail],
            animated: false
        )
        handler.notify_viewDidDisappear(viewController: fixture.secondaryRoot, animated: false)
        handler.notify_viewDidAppear(viewController: detail, animated: false)

        fixture.secondaryNavigationController.setViewControllers([fixture.secondaryRoot], animated: false)
        handler.notify_viewDidDisappear(viewController: detail, animated: false)
        handler.notify_viewDidAppear(viewController: fixture.secondaryRoot, animated: false)
        scheduledReconciliations.forEach { $0() }

        let starts = commandSubscriber.receivedCommands.compactMap { $0 as? RUMStartViewCommand }
        XCTAssertEqual(starts.map(\.name), ["Primary", "Home", "Detail", "Home"])
        XCTAssertTrue(starts[1].identity == ViewIdentifier(fixture.secondaryRoot))
        XCTAssertTrue(starts[3].identity == ViewIdentifier(fixture.secondaryRoot))
        XCTAssertFalse(starts.dropFirst().contains { $0.name == "Primary" })
    }

    func testGivenMultiSceneSplitView_whenReplacingColumnRoot_itDoesNotRestartPrimary() throws {
        guard #available(iOS 27.0, *) else {
            return
        }
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let fixture = createUIKitSplitViewFixture()
        let replacement = UIViewController()
        let predicate = UIKitRUMViewsPredicateMock()
        predicate.resultByViewController = [
            fixture.primary: .init(name: "Primary"),
            fixture.secondaryRoot: .init(name: "Secondary 1"),
            replacement: .init(name: "Secondary 2"),
        ]
        var scheduledReconciliations: [() -> Void] = []
        let handler = createHandler(
            uiKitPredicate: predicate,
            isMultiSceneApplication: true,
            sceneIdentifierProvider: { _ in scene },
            uiKitSplitViewContextProvider: createUIKitSplitViewContextProvider(
                fixture: fixture,
                additionalSecondaryControllers: [replacement]
            ),
            scheduleUIKitSplitViewReconciliation: { scheduledReconciliations.append($0) }
        )
        handler.notify_viewDidAppear(viewController: fixture.primary, animated: false)
        handler.notify_viewDidAppear(viewController: fixture.secondaryRoot, animated: false)

        fixture.splitViewController.setViewController(replacement, for: .secondary)
        handler.notify_viewDidDisappear(viewController: fixture.secondaryRoot, animated: false)
        handler.notify_viewDidAppear(viewController: replacement, animated: false)
        scheduledReconciliations.forEach { $0() }

        let starts = commandSubscriber.receivedCommands.compactMap { $0 as? RUMStartViewCommand }
        XCTAssertEqual(starts.map(\.name), ["Primary", "Secondary 1", "Secondary 2"])
        XCTAssertFalse(starts.dropFirst().contains { $0.name == "Primary" })
    }

    func testGivenMultiSceneRegularSplitView_whenPrimaryIsStructural_itTracksOnlyDestinations() throws {
        guard #available(iOS 27.0, *) else {
            return
        }
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let fixture = createUIKitSplitViewFixture()
        let replacement = UIViewController()
        let predicate = UIKitRUMViewsPredicateMock()
        predicate.resultByViewController = [
            fixture.primary: .init(name: "Primary"),
            fixture.secondaryRoot: .init(name: "Secondary 1"),
            replacement: .init(name: "Secondary 2"),
        ]
        var scheduledReconciliations: [() -> Void] = []
        let handler = createHandler(
            uiKitPredicate: predicate,
            isMultiSceneApplication: true,
            sceneIdentifierProvider: { _ in scene },
            uiKitSplitViewContextProvider: createUIKitSplitViewContextProvider(
                fixture: fixture,
                additionalSecondaryControllers: [replacement],
                primaryIsStructural: true
            ),
            scheduleUIKitSplitViewReconciliation: { scheduledReconciliations.append($0) }
        )

        handler.notify_viewDidAppear(viewController: fixture.primary, animated: false)
        handler.notify_viewDidAppear(viewController: fixture.secondaryRoot, animated: false)
        fixture.splitViewController.setViewController(replacement, for: .secondary)
        handler.notify_viewDidDisappear(viewController: fixture.secondaryRoot, animated: false)
        handler.notify_viewDidAppear(viewController: replacement, animated: false)
        scheduledReconciliations.forEach { $0() }

        let starts = commandSubscriber.receivedCommands.compactMap { $0 as? RUMStartViewCommand }
        let stops = commandSubscriber.receivedCommands.compactMap { $0 as? RUMStopViewCommand }
        XCTAssertEqual(starts.map(\.name), ["Secondary 1", "Secondary 2"])
        XCTAssertEqual(stops.map(\.identity), [ViewIdentifier(fixture.secondaryRoot)])
        XCTAssertFalse(starts.contains { $0.name == "Primary" })
    }

    func testGivenOrdinaryApplication_whenPrimaryIsMarkedStructural_itKeepsLegacyTracking() throws {
        guard #available(iOS 27.0, *) else {
            return
        }
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let fixture = createUIKitSplitViewFixture()
        let predicate = UIKitRUMViewsPredicateMock()
        predicate.resultByViewController = [
            fixture.primary: .init(name: "Primary"),
            fixture.secondaryRoot: .init(name: "Secondary"),
        ]
        let handler = createHandler(
            uiKitPredicate: predicate,
            isMultiSceneApplication: false,
            sceneIdentifierProvider: { _ in scene },
            uiKitSplitViewContextProvider: createUIKitSplitViewContextProvider(
                fixture: fixture,
                primaryIsStructural: true
            )
        )

        handler.notify_viewDidAppear(viewController: fixture.primary, animated: false)
        handler.notify_viewDidAppear(viewController: fixture.secondaryRoot, animated: false)

        let starts = commandSubscriber.receivedCommands.compactMap { $0 as? RUMStartViewCommand }
        XCTAssertEqual(starts.map(\.name), ["Primary", "Secondary"])
    }

    func testGivenMultiSceneSplitView_whenNewControllerAppearsBeforeOldDisappears_itKeepsDirectPath() throws {
        guard #available(iOS 27.0, *) else {
            return
        }
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let fixture = createUIKitSplitViewFixture()
        let detail = UIViewController()
        let predicate = UIKitRUMViewsPredicateMock(result: .init(name: "View"))
        var scheduledReconciliations: [() -> Void] = []
        let handler = createHandler(
            uiKitPredicate: predicate,
            isMultiSceneApplication: true,
            sceneIdentifierProvider: { _ in scene },
            uiKitSplitViewContextProvider: createUIKitSplitViewContextProvider(
                fixture: fixture,
                additionalSecondaryControllers: [detail]
            ),
            scheduleUIKitSplitViewReconciliation: { scheduledReconciliations.append($0) }
        )
        handler.notify_viewDidAppear(viewController: fixture.primary, animated: false)
        handler.notify_viewDidAppear(viewController: fixture.secondaryRoot, animated: false)
        fixture.secondaryNavigationController.setViewControllers(
            [fixture.secondaryRoot, detail],
            animated: false
        )

        handler.notify_viewDidAppear(viewController: detail, animated: false)
        handler.notify_viewDidDisappear(viewController: fixture.secondaryRoot, animated: false)
        scheduledReconciliations.forEach { $0() }

        XCTAssertTrue(scheduledReconciliations.isEmpty)
        let starts = commandSubscriber.receivedCommands.compactMap { $0 as? RUMStartViewCommand }
        XCTAssertEqual(starts.map(\.identity), [
            ViewIdentifier(fixture.primary),
            ViewIdentifier(fixture.secondaryRoot),
            ViewIdentifier(detail),
        ])
    }

    func testGivenMultiSceneSplitView_whenNoSuccessorAppears_itRestartsPrimaryOnReconciliation() throws {
        guard #available(iOS 27.0, *) else {
            return
        }
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let fixture = createUIKitSplitViewFixture()
        let predicate = UIKitRUMViewsPredicateMock(result: .init(name: "View"))
        var scheduledReconciliations: [() -> Void] = []
        let handler = createHandler(
            uiKitPredicate: predicate,
            isMultiSceneApplication: true,
            sceneIdentifierProvider: { _ in scene },
            uiKitSplitViewContextProvider: createUIKitSplitViewContextProvider(fixture: fixture),
            scheduleUIKitSplitViewReconciliation: { scheduledReconciliations.append($0) }
        )
        handler.notify_viewDidAppear(viewController: fixture.primary, animated: false)
        handler.notify_viewDidAppear(viewController: fixture.secondaryRoot, animated: false)

        handler.notify_viewDidDisappear(viewController: fixture.secondaryRoot, animated: false)
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)
        XCTAssertEqual(scheduledReconciliations.count, 1)
        let reconciliation = try XCTUnwrap(scheduledReconciliations.first)
        reconciliation()

        let starts = commandSubscriber.receivedCommands.compactMap { $0 as? RUMStartViewCommand }
        XCTAssertEqual(starts.map(\.identity), [
            ViewIdentifier(fixture.primary),
            ViewIdentifier(fixture.secondaryRoot),
            ViewIdentifier(fixture.primary),
        ])
    }

    func testGivenMultiSceneSplitView_whenPendingControllerReappears_itTreatsTransitionAsCancelled() throws {
        guard #available(iOS 27.0, *) else {
            return
        }
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let fixture = createUIKitSplitViewFixture()
        let predicate = UIKitRUMViewsPredicateMock(result: .init(name: "View"))
        var scheduledReconciliations: [() -> Void] = []
        let handler = createHandler(
            uiKitPredicate: predicate,
            isMultiSceneApplication: true,
            sceneIdentifierProvider: { _ in scene },
            uiKitSplitViewContextProvider: createUIKitSplitViewContextProvider(fixture: fixture),
            scheduleUIKitSplitViewReconciliation: { scheduledReconciliations.append($0) }
        )
        handler.notify_viewDidAppear(viewController: fixture.primary, animated: false)
        handler.notify_viewDidAppear(viewController: fixture.secondaryRoot, animated: false)

        handler.notify_viewDidDisappear(viewController: fixture.secondaryRoot, animated: true)
        handler.notify_viewDidAppear(viewController: fixture.secondaryRoot, animated: true)
        scheduledReconciliations.forEach { $0() }

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)
    }

    func testGivenConcurrentMultiSceneSplitViews_whenBothNavigate_itKeepsPendingHandoffsIsolated() throws {
        guard #available(iOS 27.0, *) else {
            return
        }
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
        let fixtureA = createUIKitSplitViewFixture()
        let fixtureB = createUIKitSplitViewFixture()
        let detailA = UIViewController()
        let detailB = UIViewController()
        let contextProviderA = createUIKitSplitViewContextProvider(
            fixture: fixtureA,
            additionalSecondaryControllers: [detailA]
        )
        let contextProviderB = createUIKitSplitViewContextProvider(
            fixture: fixtureB,
            additionalSecondaryControllers: [detailB]
        )
        let predicate = UIKitRUMViewsPredicateMock(result: .init(name: "View"))
        var scheduledReconciliations: [() -> Void] = []
        let handler = createHandler(
            uiKitPredicate: predicate,
            isMultiSceneApplication: true,
            sceneIdentifierProvider: { viewController in
                contextProviderA(viewController) == nil ? sceneB : sceneA
            },
            uiKitSplitViewContextProvider: { viewController in
                contextProviderA(viewController) ?? contextProviderB(viewController)
            },
            scheduleUIKitSplitViewReconciliation: { scheduledReconciliations.append($0) }
        )
        handler.notify_viewDidAppear(viewController: fixtureA.primary, animated: false)
        handler.notify_viewDidAppear(viewController: fixtureA.secondaryRoot, animated: false)
        handler.notify_viewDidAppear(viewController: fixtureB.primary, animated: false)
        handler.notify_viewDidAppear(viewController: fixtureB.secondaryRoot, animated: false)

        handler.notify_viewDidDisappear(viewController: fixtureA.secondaryRoot, animated: false)
        handler.notify_viewDidDisappear(viewController: fixtureB.secondaryRoot, animated: false)
        handler.notify_viewDidAppear(viewController: detailB, animated: false)
        handler.notify_viewDidAppear(viewController: detailA, animated: false)
        scheduledReconciliations.forEach { $0() }

        let starts = commandSubscriber.receivedCommands.compactMap { $0 as? RUMStartViewCommand }
        XCTAssertEqual(starts.map(\.identity), [
            ViewIdentifier(fixtureA.primary),
            ViewIdentifier(fixtureA.secondaryRoot),
            ViewIdentifier(fixtureB.primary),
            ViewIdentifier(fixtureB.secondaryRoot),
            ViewIdentifier(detailB),
            ViewIdentifier(detailA),
        ])
        XCTAssertEqual(starts.suffix(2).map(\.target), [.scene(sceneB), .scene(sceneA)])
    }

    func testGivenPendingMultiSceneSplitView_whenUnrelatedUIKitViewAppears_itDoesNotRevealSibling() throws {
        guard #available(iOS 27.0, *) else {
            return
        }
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let fixture = createUIKitSplitViewFixture()
        let unrelatedFixture = createUIKitSplitViewFixture()
        let detail = UIViewController()
        let contextProvider = createUIKitSplitViewContextProvider(
            fixture: fixture,
            additionalSecondaryControllers: [detail]
        )
        let unrelatedContextProvider = createUIKitSplitViewContextProvider(fixture: unrelatedFixture)
        let predicate = UIKitRUMViewsPredicateMock(result: .init(name: "View"))
        var scheduledReconciliations: [() -> Void] = []
        let handler = createHandler(
            uiKitPredicate: predicate,
            isMultiSceneApplication: true,
            sceneIdentifierProvider: { _ in scene },
            uiKitSplitViewContextProvider: { viewController in
                contextProvider(viewController) ?? unrelatedContextProvider(viewController)
            },
            scheduleUIKitSplitViewReconciliation: { scheduledReconciliations.append($0) }
        )
        handler.notify_viewDidAppear(viewController: fixture.primary, animated: false)
        handler.notify_viewDidAppear(viewController: fixture.secondaryRoot, animated: false)
        dateProvider.advance(bySeconds: 1)
        handler.notify_viewDidDisappear(viewController: fixture.secondaryRoot, animated: false)

        dateProvider.advance(bySeconds: 2)
        handler.notify_viewDidAppear(viewController: unrelatedFixture.primary, animated: false)
        handler.notify_viewDidAppear(viewController: detail, animated: false)
        scheduledReconciliations.forEach { $0() }

        let starts = commandSubscriber.receivedCommands.compactMap { $0 as? RUMStartViewCommand }
        XCTAssertEqual(starts.map(\.identity), [
            ViewIdentifier(fixture.primary),
            ViewIdentifier(fixture.secondaryRoot),
            ViewIdentifier(unrelatedFixture.primary),
            ViewIdentifier(detail),
        ])
        XCTAssertEqual(starts.filter { $0.identity == ViewIdentifier(fixture.primary) }.count, 1)
        let secondaryStop = try XCTUnwrap(
            commandSubscriber.receivedCommands.compactMap { $0 as? RUMStopViewCommand }.first(where: {
                $0.identity == ViewIdentifier(fixture.secondaryRoot)
            })
        )
        XCTAssertEqual(secondaryStop.time, .mockDecember15th2019At10AMUTC() + 1)
    }

    func testGivenPendingMultiSceneSplitView_whenSceneEntersBackground_itDoesNotRevealSibling() throws {
        guard #available(iOS 27.0, *) else {
            return
        }
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let fixture = createUIKitSplitViewFixture()
        let predicate = UIKitRUMViewsPredicateMock(result: .init(name: "View"))
        var scheduledReconciliations: [() -> Void] = []
        let handler = createHandler(
            uiKitPredicate: predicate,
            isMultiSceneApplication: true,
            sceneIdentifierProvider: { _ in scene },
            sceneIdentifierFromNotification: { notification in
                notification.object as? String == "scene-A" ? scene : nil
            },
            uiKitSplitViewContextProvider: createUIKitSplitViewContextProvider(fixture: fixture),
            scheduleUIKitSplitViewReconciliation: { scheduledReconciliations.append($0) }
        )
        handler.notify_viewDidAppear(viewController: fixture.primary, animated: false)
        handler.notify_viewDidAppear(viewController: fixture.secondaryRoot, animated: false)
        dateProvider.advance(bySeconds: 1)
        handler.notify_viewDidDisappear(viewController: fixture.secondaryRoot, animated: false)
        dateProvider.advance(bySeconds: 2)

        notificationCenter.post(name: UIScene.didEnterBackgroundNotification, object: "scene-A")
        scheduledReconciliations.forEach { $0() }

        let startsBeforeForeground = commandSubscriber.receivedCommands.compactMap { $0 as? RUMStartViewCommand }
        let stops = commandSubscriber.receivedCommands.compactMap { $0 as? RUMStopViewCommand }
        XCTAssertEqual(startsBeforeForeground.map(\.identity), [
            ViewIdentifier(fixture.primary),
            ViewIdentifier(fixture.secondaryRoot),
        ])
        XCTAssertEqual(stops.last?.identity, ViewIdentifier(fixture.secondaryRoot))
        XCTAssertEqual(stops.last?.time, .mockDecember15th2019At10AMUTC() + 1)

        notificationCenter.post(name: UIScene.willEnterForegroundNotification, object: "scene-A")

        let startsAfterForeground = commandSubscriber.receivedCommands.compactMap { $0 as? RUMStartViewCommand }
        XCTAssertEqual(startsAfterForeground.map(\.identity), [
            ViewIdentifier(fixture.primary),
            ViewIdentifier(fixture.secondaryRoot),
            ViewIdentifier(fixture.primary),
        ])
    }

    func testGivenPendingMultiSceneSplitView_whenApplicationEntersBackground_itDoesNotRevealSibling() throws {
        guard #available(iOS 27.0, *) else {
            return
        }
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let fixture = createUIKitSplitViewFixture()
        let predicate = UIKitRUMViewsPredicateMock(result: .init(name: "View"))
        var scheduledReconciliations: [() -> Void] = []
        let handler = createHandler(
            uiKitPredicate: predicate,
            isMultiSceneApplication: true,
            sceneIdentifierProvider: { _ in scene },
            sceneIdentifierFromNotification: { notification in
                notification.object as? String == "scene-A" ? scene : nil
            },
            uiKitSplitViewContextProvider: createUIKitSplitViewContextProvider(fixture: fixture),
            scheduleUIKitSplitViewReconciliation: { scheduledReconciliations.append($0) }
        )
        handler.notify_viewDidAppear(viewController: fixture.primary, animated: false)
        handler.notify_viewDidAppear(viewController: fixture.secondaryRoot, animated: false)
        dateProvider.advance(bySeconds: 1)
        handler.notify_viewDidDisappear(viewController: fixture.secondaryRoot, animated: false)
        dateProvider.advance(bySeconds: 2)

        notificationCenter.post(name: ApplicationNotifications.didEnterBackground, object: nil)
        scheduledReconciliations.forEach { $0() }

        let startsBeforeForeground = commandSubscriber.receivedCommands.compactMap { $0 as? RUMStartViewCommand }
        let stops = commandSubscriber.receivedCommands.compactMap { $0 as? RUMStopViewCommand }
        XCTAssertEqual(startsBeforeForeground.map(\.identity), [
            ViewIdentifier(fixture.primary),
            ViewIdentifier(fixture.secondaryRoot),
        ])
        XCTAssertEqual(stops.last?.identity, ViewIdentifier(fixture.secondaryRoot))
        XCTAssertEqual(stops.last?.time, .mockDecember15th2019At10AMUTC() + 1)

        notificationCenter.post(name: ApplicationNotifications.willEnterForeground, object: nil)
        notificationCenter.post(name: UIScene.willEnterForegroundNotification, object: "scene-A")

        let startsAfterForeground = commandSubscriber.receivedCommands.compactMap { $0 as? RUMStartViewCommand }
        XCTAssertEqual(startsAfterForeground.map(\.identity), [
            ViewIdentifier(fixture.primary),
            ViewIdentifier(fixture.secondaryRoot),
            ViewIdentifier(fixture.primary),
        ])
    }

    func testGivenPendingMultiSceneSplitView_whenSceneDisconnects_itDoesNotRestartSiblingColumn() throws {
        guard #available(iOS 27.0, *) else {
            return
        }
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
        let fixtureA = createUIKitSplitViewFixture()
        let fixtureB = createUIKitSplitViewFixture()
        let contextProviderA = createUIKitSplitViewContextProvider(fixture: fixtureA)
        let contextProviderB = createUIKitSplitViewContextProvider(fixture: fixtureB)
        let predicate = UIKitRUMViewsPredicateMock(result: .init(name: "View"))
        var scheduledReconciliations: [() -> Void] = []
        let handler = createHandler(
            uiKitPredicate: predicate,
            isMultiSceneApplication: true,
            sceneIdentifierProvider: { viewController in
                contextProviderA(viewController) == nil ? sceneB : sceneA
            },
            sceneIdentifierFromNotification: { notification in
                notification.object as? String == "scene-A" ? sceneA : nil
            },
            uiKitSplitViewContextProvider: { viewController in
                contextProviderA(viewController) ?? contextProviderB(viewController)
            },
            scheduleUIKitSplitViewReconciliation: { scheduledReconciliations.append($0) }
        )
        handler.notify_viewDidAppear(viewController: fixtureA.primary, animated: false)
        handler.notify_viewDidAppear(viewController: fixtureA.secondaryRoot, animated: false)
        handler.notify_viewDidAppear(viewController: fixtureB.primary, animated: false)
        handler.notify_viewDidAppear(viewController: fixtureB.secondaryRoot, animated: false)
        dateProvider.advance(bySeconds: 1)
        handler.notify_viewDidDisappear(viewController: fixtureA.secondaryRoot, animated: false)

        let commandCountBeforeDisconnect = commandSubscriber.receivedCommands.count
        dateProvider.advance(bySeconds: 2)
        notificationCenter.post(name: UIScene.didDisconnectNotification, object: "scene-A")
        scheduledReconciliations.forEach { $0() }

        let starts = commandSubscriber.receivedCommands.compactMap { $0 as? RUMStartViewCommand }
        XCTAssertEqual(starts.filter { $0.identity == ViewIdentifier(fixtureA.primary) }.count, 1)
        let teardownCommands = commandSubscriber.receivedCommands.dropFirst(commandCountBeforeDisconnect)
        XCTAssertFalse(teardownCommands.contains { command in
            (command as? RUMStopViewCommand)?.target == .scene(sceneB)
        })
        let lastStop = try XCTUnwrap(
            commandSubscriber.receivedCommands.compactMap { $0 as? RUMStopViewCommand }.last
        )
        XCTAssertTrue(lastStop.identity == ViewIdentifier(fixtureA.secondaryRoot))
        XCTAssertEqual(lastStop.target, .scene(sceneA))
        XCTAssertEqual(lastStop.time, .mockDecember15th2019At10AMUTC() + 1)
    }

    func testGivenOrdinaryApplication_whenSplitControllerDisappears_itKeepsLegacyImmediateRestart() throws {
        guard #available(iOS 27.0, *) else {
            return
        }
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let fixture = createUIKitSplitViewFixture()
        let predicate = UIKitRUMViewsPredicateMock(result: .init(name: "View"))
        var scheduledReconciliations: [() -> Void] = []
        let handler = createHandler(
            uiKitPredicate: predicate,
            isMultiSceneApplication: false,
            sceneIdentifierProvider: { _ in scene },
            scheduleUIKitSplitViewReconciliation: { scheduledReconciliations.append($0) }
        )
        handler.notify_viewDidAppear(viewController: fixture.primary, animated: false)
        handler.notify_viewDidAppear(viewController: fixture.secondaryRoot, animated: false)

        handler.notify_viewDidDisappear(viewController: fixture.secondaryRoot, animated: false)

        XCTAssertTrue(scheduledReconciliations.isEmpty)
        let starts = commandSubscriber.receivedCommands.compactMap { $0 as? RUMStartViewCommand }
        XCTAssertEqual(starts.map(\.identity), [
            ViewIdentifier(fixture.primary),
            ViewIdentifier(fixture.secondaryRoot),
            ViewIdentifier(fixture.primary),
        ])
    }
    #endif

    func testGivenConcurrentScenes_whenSceneLifecycleChanges_itOnlyChangesOwningScene() throws {
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
        let viewA = createMockViewInWindow()
        let viewB = createMockViewInWindow()
        let uiKitPredicate = UIKitRUMViewsPredicateMock(result: .init(name: .mockRandom()))
        let handler = createHandler(
            uiKitPredicate: uiKitPredicate,
            sceneIdentifierProvider: { $0 === viewA ? sceneA : sceneB },
            sceneIdentifierFromNotification: { notification in
                switch notification.object as? String {
                case "scene-A": return sceneA
                case "scene-B": return sceneB
                default: return nil
                }
            }
        )

        handler.notify_viewDidAppear(viewController: viewA, animated: false)
        handler.notify_viewDidAppear(viewController: viewB, animated: false)
        notificationCenter.post(name: UIScene.didEnterBackgroundNotification, object: "scene-A")
        notificationCenter.post(name: UIScene.didEnterBackgroundNotification, object: "scene-A")

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)
        XCTAssertEqual(
            (commandSubscriber.receivedCommands[2] as? RUMStopViewCommand)?.target,
            .scene(sceneA)
        )

        notificationCenter.post(name: ApplicationNotifications.didEnterBackground, object: nil)
        notificationCenter.post(name: ApplicationNotifications.willEnterForeground, object: nil)

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 6)
        XCTAssertEqual(
            (commandSubscriber.receivedCommands[3] as? RUMStopViewCommand)?.target,
            .scene(sceneB)
        )
        XCTAssertEqual(
            (commandSubscriber.receivedCommands[4] as? RUMHandleAppLifecycleEventCommand)?.event,
            .didEnterBackground
        )
        XCTAssertEqual(
            (commandSubscriber.receivedCommands[5] as? RUMHandleAppLifecycleEventCommand)?.event,
            .willEnterForeground
        )

        notificationCenter.post(name: UIScene.willEnterForegroundNotification, object: "scene-A")
        notificationCenter.post(name: UIScene.willEnterForegroundNotification, object: "scene-B")

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 8)
        XCTAssertEqual(
            (commandSubscriber.receivedCommands[6] as? RUMStartViewCommand)?.target,
            .scene(sceneA)
        )
        XCTAssertEqual(
            (commandSubscriber.receivedCommands[7] as? RUMStartViewCommand)?.target,
            .scene(sceneB)
        )
    }

    func testGivenSceneEnteredBackgroundBeforeItsFirstViewAppears_itWaitsForSceneForegroundToStartView() throws {
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let viewA = createMockViewInWindow()
        let handler = createHandler(
            uiKitPredicate: UIKitRUMViewsPredicateMock(result: .init(name: "View A")),
            sceneIdentifierProvider: { _ in sceneA },
            sceneIdentifierFromNotification: { notification in
                notification.object as? String == "scene-A" ? sceneA : nil
            }
        )

        notificationCenter.post(name: UIScene.didEnterBackgroundNotification, object: "scene-A")
        handler.notify_viewDidAppear(viewController: viewA, animated: false)

        XCTAssertTrue(commandSubscriber.receivedCommands.isEmpty)

        notificationCenter.post(name: UIScene.willEnterForegroundNotification, object: "scene-A")

        let start = try XCTUnwrap(commandSubscriber.receivedCommands.first as? RUMStartViewCommand)
        XCTAssertEqual(start.target, .scene(sceneA))
    }

    func testGivenApplicationEnteredBackgroundBeforeLegacyViewAppears_itWaitsForForegroundToStartView() throws {
        let view = createMockViewInWindow()
        let handler = createHandler(
            uiKitPredicate: UIKitRUMViewsPredicateMock(result: .init(name: "View"))
        )

        notificationCenter.post(name: ApplicationNotifications.didEnterBackground, object: nil)
        handler.notify_viewDidAppear(viewController: view, animated: false)

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 1)
        XCTAssertTrue(commandSubscriber.receivedCommands[0] is RUMHandleAppLifecycleEventCommand)

        notificationCenter.post(name: ApplicationNotifications.willEnterForeground, object: nil)

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)
        XCTAssertTrue(commandSubscriber.receivedCommands[1] is RUMStartViewCommand)
        XCTAssertTrue(commandSubscriber.receivedCommands[2] is RUMHandleAppLifecycleEventCommand)
    }

    func testGivenReusedViewControllerMovesToAnotherScene_whenItAppears_itMovesRUMViewOwnership() throws {
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
        let view = createMockViewInWindow()
        var currentScene = sceneA
        let handler = createHandler(
            uiKitPredicate: UIKitRUMViewsPredicateMock(result: .init(name: "Shared View")),
            sceneIdentifierProvider: { _ in currentScene }
        )

        handler.notify_viewDidAppear(viewController: view, animated: false)
        currentScene = sceneB
        handler.notify_viewDidAppear(viewController: view, animated: false)

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)
        XCTAssertEqual((commandSubscriber.receivedCommands[0] as? RUMStartViewCommand)?.target, .scene(sceneA))
        XCTAssertEqual((commandSubscriber.receivedCommands[1] as? RUMStopViewCommand)?.target, .scene(sceneA))
        XCTAssertEqual((commandSubscriber.receivedCommands[2] as? RUMStartViewCommand)?.target, .scene(sceneB))
    }

    func testGivenConcurrentScenes_whenSceneDisconnects_itStopsOnlyThatSceneOnce() throws {
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
        let viewA = createMockViewInWindow()
        let viewB = createMockViewInWindow()
        let handler = createHandler(
            uiKitPredicate: UIKitRUMViewsPredicateMock(result: .init(name: .mockRandom())),
            sceneIdentifierProvider: { $0 === viewA ? sceneA : sceneB },
            sceneIdentifierFromNotification: { notification in
                notification.object as? String == "scene-B" ? sceneB : nil
            }
        )

        handler.notify_viewDidAppear(viewController: viewA, animated: false)
        handler.notify_viewDidAppear(viewController: viewB, animated: false)
        notificationCenter.post(name: UIScene.didDisconnectNotification, object: "scene-B")
        handler.notify_viewDidDisappear(viewController: viewB, animated: false)

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)
        let stop = try XCTUnwrap(commandSubscriber.receivedCommands.last as? RUMStopViewCommand)
        XCTAssertTrue(stop.identity == ViewIdentifier(viewB))
        XCTAssertEqual(stop.target, .scene(sceneB))
        XCTAssertFalse(commandSubscriber.receivedCommands.contains { command in
            (command as? RUMStopViewCommand)?.identity == ViewIdentifier(viewA)
        })
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
        XCTAssertEqual(command.instrumentationType, .swiftuiAutomatic)
        XCTAssertEqual(command.time, .mockDecember15th2019At10AMUTC())
    }

    func testGivenExplicitSwiftUIAuthority_whenAutomaticViewDidAppear_itDoesNotStartView() {
        let viewController = createMockViewInWindow()
        var inspectedViewController: UIViewController?
        let handler = createHandler(
            swiftUIPredicate: SwiftUIRUMViewsPredicateMock(
                result: .init(name: "Automatic")
            ),
            swiftUIViewNameExtractor: SwiftUIViewNameExtractorMock(
                defaultResult: "Automatic"
            ),
            isSwiftUIAutomaticViewSuppressed: { candidate in
                inspectedViewController = candidate
                return true
            }
        )

        handler.notify_viewDidAppear(viewController: viewController, animated: false)

        XCTAssertTrue(inspectedViewController === viewController)
        XCTAssertTrue(commandSubscriber.receivedCommands.isEmpty)
    }

    func testGivenExplicitSwiftUIAuthority_whenUIKitPredicateAcceptsView_itStillStartsUIKitView() throws {
        let viewController = createMockViewInWindow()
        let handler = createHandler(
            uiKitPredicate: UIKitRUMViewsPredicateMock(result: .init(name: "UIKit")),
            swiftUIPredicate: SwiftUIRUMViewsPredicateMock(
                result: .init(name: "Automatic")
            ),
            swiftUIViewNameExtractor: SwiftUIViewNameExtractorMock(
                defaultResult: "Automatic"
            ),
            isSwiftUIAutomaticViewSuppressed: { _ in true }
        )

        handler.notify_viewDidAppear(viewController: viewController, animated: false)

        let start = try XCTUnwrap(
            commandSubscriber.receivedCommands.first as? RUMStartViewCommand
        )
        XCTAssertEqual(start.name, "UIKit")
        XCTAssertEqual(start.instrumentationType, .uikit)
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
        XCTAssertEqual(startCommand1.instrumentationType, .swiftuiAutomatic)
        XCTAssertTrue(stopCommand.identity == ViewIdentifier(view1))
        XCTAssertEqual(stopCommand.attributes as? [String: String], ["key1": "val1"])
        XCTAssertTrue(startCommand2.identity == ViewIdentifier(view2))
        XCTAssertEqual(startCommand2.attributes as? [String: String], ["key2": "val2"])
        XCTAssertEqual(startCommand2.instrumentationType, .swiftuiAutomatic)
    }

    #if os(iOS)
    @MainActor
    func testGivenAutomaticHome_whenTargetedManualViewStops_itRestartsHomeAsFreshOccurrence() throws {
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let home = createMockViewInWindow()
        let handler = createHandler(
            swiftUIPredicate: SwiftUIRUMViewsPredicateMock(result: .init(name: "Home")),
            swiftUIViewNameExtractor: SwiftUIViewNameExtractorMock(defaultResult: "Home"),
            sceneIdentifierProvider: { _ in scene }
        )

        handler.notify_viewDidAppear(viewController: home, animated: false)
        handler.startView(
            key: "compose",
            name: "Compose",
            attributes: ["started": true],
            sceneIdentifier: scene
        )
        handler.notify_viewDidAppear(viewController: home, animated: false)

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)

        handler.stopView(
            key: "compose",
            attributes: ["stopped": true],
            sceneIdentifier: scene
        )

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 5)
        let commands = commandSubscriber.receivedCommands
        let homeStart = try XCTUnwrap(commands[0] as? RUMStartViewCommand)
        let homeStop = try XCTUnwrap(commands[1] as? RUMStopViewCommand)
        let manualStart = try XCTUnwrap(commands[2] as? RUMStartViewCommand)
        let manualStop = try XCTUnwrap(commands[3] as? RUMStopViewCommand)
        let homeRestart = try XCTUnwrap(commands[4] as? RUMStartViewCommand)
        XCTAssertEqual(homeStart.identity, ViewIdentifier(home))
        XCTAssertEqual(homeStop.identity, ViewIdentifier(home))
        XCTAssertEqual(manualStart.identity, ViewIdentifier("compose"))
        XCTAssertEqual(manualStart.instrumentationType, .manual)
        XCTAssertEqual(manualStop.identity, ViewIdentifier("compose"))
        XCTAssertEqual(manualStop.attributes["stopped"] as? Bool, true)
        XCTAssertNil(manualStop.attributes["started"])
        XCTAssertEqual(homeRestart.identity, ViewIdentifier(home))
        XCTAssertEqual(homeRestart.instrumentationType, .swiftuiAutomatic)
        XCTAssertTrue(commands.allSatisfy { $0.target == .scene(scene) })
    }

    @MainActor
    func testGivenTargetedManualView_whenAutomaticDestinationAppears_itStagesDestinationUntilManualStop() throws {
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let home = createMockViewInWindow()
        let detail = createMockViewInWindow()
        let nameExtractor = SwiftUIViewNameExtractorMock()
        nameExtractor.resultByViewController = [home: "Home", detail: "Detail"]
        let predicate = SwiftUIRUMViewsPredicateMock()
        predicate.resultByViewName = [
            "Home": .init(name: "Home"),
            "Detail": .init(name: "Detail"),
        ]
        let handler = createHandler(
            swiftUIPredicate: predicate,
            swiftUIViewNameExtractor: nameExtractor,
            sceneIdentifierProvider: { _ in scene }
        )

        handler.notify_viewDidAppear(viewController: home, animated: false)
        handler.startView(key: "compose", name: "Compose", attributes: [:], sceneIdentifier: scene)
        handler.notify_viewDidAppear(viewController: detail, animated: false)
        handler.notify_viewDidDisappear(viewController: home, animated: false)

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)

        handler.stopView(key: "compose", attributes: [:], sceneIdentifier: scene)

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 5)
        let manualStop = try XCTUnwrap(commandSubscriber.receivedCommands[3] as? RUMStopViewCommand)
        let detailStart = try XCTUnwrap(commandSubscriber.receivedCommands[4] as? RUMStartViewCommand)
        XCTAssertEqual(manualStop.identity, ViewIdentifier("compose"))
        XCTAssertEqual(detailStart.identity, ViewIdentifier(detail))
        XCTAssertEqual(detailStart.name, "Detail")
        XCTAssertEqual(detailStart.instrumentationType, .swiftuiAutomatic)
    }

    @MainActor
    func testGivenTargetedManualView_whenGenericAutomaticFallbackAppears_itRevealsRetainedDestination() throws {
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let home = createMockViewInWindow()
        let fallback = createMockViewInWindow()
        let nameExtractor = SwiftUIViewNameExtractorMock()
        nameExtractor.resultByViewController = [
            home: "Home",
            fallback: "AutoTracked_HostingController_Fallback",
        ]
        let predicate = SwiftUIRUMViewsPredicateMock()
        predicate.resultByViewName = [
            "Home": .init(name: "Home"),
            "AutoTracked_HostingController_Fallback": .init(name: "Automatic Fallback"),
        ]
        let handler = createHandler(
            swiftUIPredicate: predicate,
            swiftUIViewNameExtractor: nameExtractor,
            sceneIdentifierProvider: { _ in scene }
        )

        handler.notify_viewDidAppear(viewController: home, animated: false)
        handler.startView(key: "compose", name: "Compose", attributes: [:], sceneIdentifier: scene)
        handler.notify_viewDidAppear(viewController: fallback, animated: false)
        handler.notify_viewDidDisappear(viewController: home, animated: false)

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)

        handler.stopView(key: "compose", attributes: [:], sceneIdentifier: scene)

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 5)
        let manualStop = try XCTUnwrap(commandSubscriber.receivedCommands[3] as? RUMStopViewCommand)
        let homeRestart = try XCTUnwrap(commandSubscriber.receivedCommands[4] as? RUMStartViewCommand)
        XCTAssertEqual(manualStop.identity, ViewIdentifier("compose"))
        XCTAssertEqual(homeRestart.identity, ViewIdentifier(home))
        XCTAssertEqual(homeRestart.name, "Home")
        XCTAssertFalse(commandSubscriber.receivedCommands.contains { command in
            (command as? RUMStartViewCommand)?.name == "Automatic Fallback"
        })
    }

    @MainActor
    func testGivenNestedTargetedManualViews_whenAutomaticDestinationAppears_itKeepsEntireManualSuffixAuthoritative() throws {
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let home = createMockViewInWindow()
        let detail = createMockViewInWindow()
        let nameExtractor = SwiftUIViewNameExtractorMock()
        nameExtractor.resultByViewController = [home: "Home", detail: "Detail"]
        let predicate = SwiftUIRUMViewsPredicateMock()
        predicate.resultByViewName = [
            "Home": .init(name: "Home"),
            "Detail": .init(name: "Detail"),
        ]
        let handler = createHandler(
            swiftUIPredicate: predicate,
            swiftUIViewNameExtractor: nameExtractor,
            sceneIdentifierProvider: { _ in scene }
        )

        handler.notify_viewDidAppear(viewController: home, animated: false)
        handler.startView(key: "manual-1", name: "Manual 1", attributes: [:], sceneIdentifier: scene)
        handler.startView(key: "manual-2", name: "Manual 2", attributes: [:], sceneIdentifier: scene)
        handler.notify_viewDidAppear(viewController: detail, animated: false)

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 5)

        handler.stopView(key: "manual-2", attributes: [:], sceneIdentifier: scene)
        handler.stopView(key: "manual-1", attributes: [:], sceneIdentifier: scene)

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 9)
        let restartedManual = try XCTUnwrap(commandSubscriber.receivedCommands[6] as? RUMStartViewCommand)
        let revealedDetail = try XCTUnwrap(commandSubscriber.receivedCommands[8] as? RUMStartViewCommand)
        XCTAssertEqual(restartedManual.identity, ViewIdentifier("manual-1"))
        XCTAssertEqual(restartedManual.instrumentationType, .manual)
        XCTAssertEqual(revealedDetail.identity, ViewIdentifier(detail))
        XCTAssertEqual(revealedDetail.instrumentationType, .swiftuiAutomatic)
        XCTAssertFalse(commandSubscriber.receivedCommands.prefix(8).contains { command in
            (command as? RUMStartViewCommand)?.identity == ViewIdentifier(detail)
        })
    }

    @MainActor
    func testGivenSeveralUnderlyingDestinationsDuringManualAuthority_whenItStops_itRevealsOnlyLatest() throws {
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let home = createMockViewInWindow()
        let detail = createMockViewInWindow()
        let alternate = createMockViewInWindow()
        let nameExtractor = SwiftUIViewNameExtractorMock()
        nameExtractor.resultByViewController = [
            home: "Home",
            detail: "Detail",
            alternate: "Alternate",
        ]
        let predicate = SwiftUIRUMViewsPredicateMock()
        predicate.resultByViewName = [
            "Home": .init(name: "Home"),
            "Detail": .init(name: "Detail"),
            "Alternate": .init(name: "Alternate"),
        ]
        let handler = createHandler(
            swiftUIPredicate: predicate,
            swiftUIViewNameExtractor: nameExtractor,
            sceneIdentifierProvider: { _ in scene }
        )

        handler.notify_viewDidAppear(viewController: home, animated: false)
        handler.startView(key: "compose", name: "Compose", attributes: [:], sceneIdentifier: scene)
        handler.notify_viewDidAppear(viewController: detail, animated: false)
        handler.notify_viewDidAppear(viewController: alternate, animated: false)

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)

        handler.stopView(key: "compose", attributes: [:], sceneIdentifier: scene)

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 5)
        let revealed = try XCTUnwrap(
            commandSubscriber.receivedCommands.last as? RUMStartViewCommand
        )
        XCTAssertEqual(revealed.identity, ViewIdentifier(alternate))
        XCTAssertFalse(commandSubscriber.receivedCommands.contains { command in
            (command as? RUMStartViewCommand)?.identity == ViewIdentifier(detail)
        })
    }

    @MainActor
    func testGivenNestedTargetedManualViews_whenPreviewStops_itStartsFreshComposeOccurrence() throws {
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let handler = createHandler()

        handler.startView(key: "compose", name: "Compose", attributes: [:], sceneIdentifier: scene)
        handler.startView(key: "preview", name: "Attachment Preview", attributes: [:], sceneIdentifier: scene)
        handler.stopView(key: "preview", attributes: [:], sceneIdentifier: scene)

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 5)
        XCTAssertEqual(
            (commandSubscriber.receivedCommands[0] as? RUMStartViewCommand)?.identity,
            ViewIdentifier("compose")
        )
        XCTAssertEqual(
            (commandSubscriber.receivedCommands[1] as? RUMStopViewCommand)?.identity,
            ViewIdentifier("compose")
        )
        XCTAssertEqual(
            (commandSubscriber.receivedCommands[2] as? RUMStartViewCommand)?.identity,
            ViewIdentifier("preview")
        )
        XCTAssertEqual(
            (commandSubscriber.receivedCommands[3] as? RUMStopViewCommand)?.identity,
            ViewIdentifier("preview")
        )
        XCTAssertEqual(
            (commandSubscriber.receivedCommands[4] as? RUMStartViewCommand)?.identity,
            ViewIdentifier("compose")
        )
    }

    @MainActor
    func testGivenActiveTargetedManualView_whenSameSceneAndKeyStartsAgain_itRemainsCrashSafeAndDoesNotRestart() throws {
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let home = createMockViewInWindow()
        let handler = createHandler(
            swiftUIPredicate: SwiftUIRUMViewsPredicateMock(result: .init(name: "Home")),
            swiftUIViewNameExtractor: SwiftUIViewNameExtractorMock(defaultResult: "Home"),
            sceneIdentifierProvider: { _ in scene }
        )
        handler.notify_viewDidAppear(viewController: home, animated: false)
        handler.startView(key: "compose", name: "Compose", attributes: [:], sceneIdentifier: scene)

        handler.startView(
            key: "compose",
            name: "Duplicate Compose",
            attributes: ["duplicate": true],
            sceneIdentifier: scene
        )

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)

        handler.stopView(key: "compose", attributes: [:], sceneIdentifier: scene)

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 5)
        XCTAssertEqual(
            commandSubscriber.receivedCommands.compactMap {
                ($0 as? RUMStartViewCommand)?.identity
            },
            [ViewIdentifier(home), ViewIdentifier("compose"), ViewIdentifier(home)]
        )
    }

    @MainActor
    func testGivenSameTargetedManualKeyInTwoScenes_whenOneStops_itDoesNotAffectPeer() throws {
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
        let handler = createHandler()

        handler.startView(key: "compose", name: "Compose A", attributes: [:], sceneIdentifier: sceneA)
        handler.startView(key: "compose", name: "Compose B", attributes: [:], sceneIdentifier: sceneB)
        handler.stopView(key: "compose", attributes: [:], sceneIdentifier: sceneA)

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)
        XCTAssertEqual(commandSubscriber.receivedCommands[0].target, .scene(sceneA))
        XCTAssertEqual(commandSubscriber.receivedCommands[1].target, .scene(sceneB))
        XCTAssertEqual(commandSubscriber.receivedCommands[2].target, .scene(sceneA))

        handler.stopView(key: "compose", attributes: [:], sceneIdentifier: sceneB)

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 4)
        XCTAssertEqual(commandSubscriber.receivedCommands[3].target, .scene(sceneB))
    }

    @MainActor
    func testGivenTargetedManualView_whenWrongSceneStops_itRemainsActive() throws {
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
        let handler = createHandler()
        handler.startView(key: "compose", name: "Compose", attributes: [:], sceneIdentifier: sceneA)

        handler.stopView(key: "compose", attributes: [:], sceneIdentifier: sceneB)

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 1)

        handler.stopView(key: "compose", attributes: [:], sceneIdentifier: sceneA)

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 2)
        let stop = try XCTUnwrap(commandSubscriber.receivedCommands[1] as? RUMStopViewCommand)
        XCTAssertEqual(stop.target, .scene(sceneA))
    }

    @MainActor
    func testGivenTargetedManualView_whenSceneDisconnects_itDoesNotRevealUnderlyingView() throws {
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let home = createMockViewInWindow()
        let handler = createHandler(
            swiftUIPredicate: SwiftUIRUMViewsPredicateMock(result: .init(name: "Home")),
            swiftUIViewNameExtractor: SwiftUIViewNameExtractorMock(defaultResult: "Home"),
            sceneIdentifierProvider: { _ in scene },
            sceneIdentifierFromNotification: { notification in
                notification.object as? String == "scene-A" ? scene : nil
            }
        )
        handler.notify_viewDidAppear(viewController: home, animated: false)
        handler.startView(key: "compose", name: "Compose", attributes: [:], sceneIdentifier: scene)

        notificationCenter.post(name: UIScene.didDisconnectNotification, object: "scene-A")

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 4)
        let last = try XCTUnwrap(commandSubscriber.receivedCommands.last as? RUMStopViewCommand)
        XCTAssertEqual(last.identity, ViewIdentifier("compose"))
        XCTAssertFalse(commandSubscriber.receivedCommands.dropFirst(3).contains { command in
            (command as? RUMStartViewCommand)?.identity == ViewIdentifier(home)
        })
    }
    #endif

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
        handler.notify_viewDidDisappear(viewController: view, animated: .mockAny())

        // When
        notificationCenter.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        dateProvider.advance(bySeconds: 1)
        notificationCenter.post(name: UIApplication.willEnterForegroundNotification, object: nil)

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

    func testWhenOnAppearInScene_itTargetsThatScene() throws {
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let handler = createHandler()

        handler.notify_onAppear(
            identity: "view-A",
            name: "View A",
            path: "View A",
            attributes: [:],
            sceneIdentifier: scene
        )

        let command = try XCTUnwrap(commandSubscriber.receivedCommands.first as? RUMStartViewCommand)
        XCTAssertEqual(command.target, .scene(scene))
    }

    func testGivenSameSwiftUIIdentityInTwoScenes_whenOneDisappears_itStopsOnlyThatScene() throws {
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
        let handler = createHandler()

        handler.notify_onAppear(
            identity: "shared-view",
            name: "Shared View A",
            path: "Shared View",
            attributes: [:],
            sceneIdentifier: sceneA
        )
        handler.notify_onAppear(
            identity: "shared-view",
            name: "Shared View B",
            path: "Shared View",
            attributes: [:],
            sceneIdentifier: sceneB
        )
        handler.notify_onDisappear(identity: "shared-view", sceneIdentifier: sceneA)

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)
        let stopA = try XCTUnwrap(commandSubscriber.receivedCommands.last as? RUMStopViewCommand)
        XCTAssertEqual(stopA.target, .scene(sceneA))

        handler.notify_onDisappear(identity: "shared-view", sceneIdentifier: sceneB)

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 4)
        let stopB = try XCTUnwrap(commandSubscriber.receivedCommands.last as? RUMStopViewCommand)
        XCTAssertEqual(stopB.target, .scene(sceneB))
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

    func testWhenActiveSwiftUIOccurrenceIsReplaced_itDoesNotRestartUnderlyingView() throws {
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let handler = createHandler()
        handler.notify_onAppear(
            identity: "home",
            name: "Home",
            path: "Home",
            attributes: [:],
            sceneIdentifier: scene
        )
        handler.notify_onAppear(
            identity: "detail-1",
            name: "Detail",
            path: "Detail",
            attributes: ["instance": 1],
            sceneIdentifier: scene
        )

        handler.notify_replaceOccurrence(
            oldIdentity: "detail-1",
            newIdentity: "detail-2",
            name: "Detail",
            path: "Detail",
            attributes: ["instance": 2],
            sceneIdentifier: scene
        )

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 5)
        let stop = try XCTUnwrap(commandSubscriber.receivedCommands[3] as? RUMStopViewCommand)
        let start = try XCTUnwrap(commandSubscriber.receivedCommands[4] as? RUMStartViewCommand)
        XCTAssertTrue(stop.identity == ViewIdentifier("detail-1"))
        XCTAssertTrue(start.identity == ViewIdentifier("detail-2"))
        XCTAssertEqual(start.name, "Detail")
        XCTAssertEqual(start.attributes["instance"] as? Int, 2)
        XCTAssertEqual(stop.target, .scene(scene))
        XCTAssertEqual(start.target, .scene(scene))
        XCTAssertFalse(commandSubscriber.receivedCommands.dropFirst(3).contains { command in
            (command as? RUMStartViewCommand)?.identity == ViewIdentifier("home")
        })

        handler.notify_onDisappear(identity: "detail-2", sceneIdentifier: scene)

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 7)
        let replacementStop = try XCTUnwrap(commandSubscriber.receivedCommands[5] as? RUMStopViewCommand)
        let homeRestart = try XCTUnwrap(commandSubscriber.receivedCommands[6] as? RUMStartViewCommand)
        XCTAssertTrue(replacementStop.identity == ViewIdentifier("detail-2"))
        XCTAssertTrue(homeRestart.identity == ViewIdentifier("home"))
    }

    #if os(iOS) || os(visionOS)
    func testWhenKeyedStatePublishesReplacement_itUsesCommittedOccurrenceDescriptor() throws {
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        var generatedIdentities = ["detail-1", "detail-2"]
        let state = RUMViewTrackingState(
            identity: "platform-detail",
            occurrenceIdentityGenerator: { generatedIdentities.removeFirst() }
        )
        let initial = RUMViewTrackingState.Configuration(
            occurrenceKey: RUMViewOccurrenceKey(1),
            bindingGeneration: 1,
            descriptor: .init(
                name: "Detail 1",
                path: "/detail/1",
                attributes: ["instance": 1]
            )
        )
        let replacement = RUMViewTrackingState.Configuration(
            occurrenceKey: RUMViewOccurrenceKey(2),
            bindingGeneration: 2,
            descriptor: .init(
                name: "Detail 2",
                path: "/detail/2",
                attributes: ["instance": 2]
            )
        )
        let fallback = RUMViewTrackingState.Configuration.Descriptor(
            name: "Stale Detail",
            path: "/stale",
            attributes: ["instance": -1]
        )
        let handler = createHandler()

        RUMSwiftUIViewTransitionPublisher.publish(
            state.mount(in: scene, configuration: initial),
            state: state,
            fallback: fallback,
            to: handler
        )
        RUMSwiftUIViewTransitionPublisher.publish(
            state.reconcile(
                configuration: replacement,
                attachment: .attached(scene),
                isAppeared: true
            ),
            state: state,
            fallback: fallback,
            to: handler
        )

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)
        let firstStart = try XCTUnwrap(
            commandSubscriber.receivedCommands[0] as? RUMStartViewCommand
        )
        let stop = try XCTUnwrap(commandSubscriber.receivedCommands[1] as? RUMStopViewCommand)
        let secondStart = try XCTUnwrap(
            commandSubscriber.receivedCommands[2] as? RUMStartViewCommand
        )
        XCTAssertEqual(firstStart.name, "Detail 1")
        XCTAssertEqual(firstStart.path, "/detail/1")
        XCTAssertEqual(firstStart.attributes["instance"] as? Int, 1)
        XCTAssertEqual(firstStart.target, .scene(scene))
        XCTAssertTrue(stop.identity == ViewIdentifier("detail-1"))
        XCTAssertEqual(stop.target, .scene(scene))
        XCTAssertEqual(secondStart.name, "Detail 2")
        XCTAssertEqual(secondStart.path, "/detail/2")
        XCTAssertEqual(secondStart.attributes["instance"] as? Int, 2)
        XCTAssertTrue(secondStart.identity == ViewIdentifier("detail-2"))
        XCTAssertEqual(secondStart.target, .scene(scene))
    }

    #if os(iOS)
    @MainActor
    func testDisconnectedSceneRegistriesRetireAfterRepeatedControllerLifetimes() {
        let handler = createHandler(
            uiKitPredicate: UIKitRUMViewsPredicateMock(result: RUMView(name: "Lifetime")),
            isMultiSceneApplication: true,
            sceneIdentifierProvider: { controller in
                controller.restorationIdentifier.map(RUMSceneIdentifier.init(rawValue:))
            },
            sceneIdentifierFromNotification: { notification in
                (notification.object as? String).map(RUMSceneIdentifier.init(rawValue:))
            }
        )
        for index in 0..<220 {
            weak var releasedController: UIViewController?
            autoreleasepool {
                let controller = UIViewController()
                controller.restorationIdentifier = "retired-\(index)"
                releasedController = controller
                notificationCenter.post(name: UIScene.willConnectNotification, object: controller.restorationIdentifier)
                notificationCenter.post(name: UIScene.willEnterForegroundNotification, object: controller.restorationIdentifier)
                handler.notify_viewDidAppear(viewController: controller, animated: false)
                notificationCenter.post(name: UIScene.didDisconnectNotification, object: controller.restorationIdentifier)
            }
            XCTAssertNil(releasedController)
        }
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 440)
        XCTAssertEqual(nonemptyHandlerCollections(handler), [:])
        notificationCenter.post(name: UIScene.didEnterBackgroundNotification, object: "retired-0")
        XCTAssertFalse(handler.notify_semanticDestinationAppear(
            identity: "stale",
            name: "Stale",
            path: "/stale",
            attributes: [:],
            sceneIdentifier: RUMSceneIdentifier(rawValue: "retired-0")
        ))
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 440)
        XCTAssertEqual(nonemptyHandlerCollections(handler), [:])
    }

    @MainActor
    func testDisconnectWithoutTrackedViewRetiresStateAndRejectsLateBackground() {
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let handler = createHandler(sceneIdentifierFromNotification: { _ in scene })
        notificationCenter.post(name: UIScene.willConnectNotification, object: nil)
        notificationCenter.post(name: UIScene.didDisconnectNotification, object: nil)
        notificationCenter.post(name: UIScene.didEnterBackgroundNotification, object: nil)
        XCTAssertEqual(nonemptyHandlerCollections(handler), [:])
        XCTAssertFalse(handler.notify_semanticDestinationAppear(
            identity: "stale", name: "Stale", path: "/stale", attributes: [:], sceneIdentifier: scene
        ))
        XCTAssertTrue(commandSubscriber.receivedCommands.isEmpty)
        notificationCenter.post(name: UIScene.willConnectNotification, object: nil)
        notificationCenter.post(name: UIScene.willEnterForegroundNotification, object: nil)
        XCTAssertTrue(handler.notify_semanticDestinationAppear(
            identity: "fresh", name: "Fresh", path: "/fresh", attributes: [:], sceneIdentifier: scene
        ))
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 1)
        notificationCenter.post(name: UIScene.didDisconnectNotification, object: nil)
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 2)
        XCTAssertEqual(nonemptyHandlerCollections(handler), [:])
    }

    @MainActor
    func testStaleUIKitAppearanceCannotRecreateDisconnectedSplitMetadata() {
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let fixture = createUIKitSplitViewFixture()
        let handler = createHandler(
            uiKitPredicate: UIKitRUMViewsPredicateMock(result: RUMView(name: "Detail")),
            isMultiSceneApplication: true,
            sceneIdentifierProvider: { _ in scene },
            sceneIdentifierFromNotification: { _ in scene },
            uiKitSplitViewContextProvider: createUIKitSplitViewContextProvider(fixture: fixture)
        )
        handler.notify_viewDidAppear(viewController: fixture.secondaryRoot, animated: false)
        XCTAssertEqual(nonemptyHandlerCollections(handler)["uiKitSplitViewContexts"], 1)
        notificationCenter.post(name: UIScene.didDisconnectNotification, object: nil)
        XCTAssertNil(nonemptyHandlerCollections(handler)["uiKitSplitViewContexts"])
        handler.notify_viewDidAppear(viewController: fixture.secondaryRoot, animated: false)
        handler.notify_viewDidDisappear(viewController: fixture.secondaryRoot, animated: false)
        XCTAssertNil(nonemptyHandlerCollections(handler)["uiKitSplitViewContexts"])
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 2)
    }

    @MainActor
    func testInitialConnectedPeerWithoutViewSurvivesAnotherSceneDisconnect() {
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
        for peerIsActive in [true, false] {
            commandSubscriber.receivedCommands = []
            var inventoryReads = 0
            let handler = createHandler(
                sceneIdentifierFromNotification: { notification in
                    (notification.object as? String).map(RUMSceneIdentifier.init(rawValue:))
                },
                initialSceneActivityProvider: {
                    XCTAssertTrue(Thread.isMainThread)
                    inventoryReads += 1
                    return [sceneA: true, sceneB: peerIsActive]
                }
            )
            notificationCenter.post(name: UIScene.didDisconnectNotification, object: "scene-A")
            XCTAssertTrue(handler.notify_semanticDestinationAppear(
                identity: "peer", name: "Peer", path: "/peer", attributes: [:], sceneIdentifier: sceneB
            ))
            XCTAssertEqual(commandSubscriber.receivedCommands.count, peerIsActive ? 1 : 0)
            notificationCenter.post(name: UIScene.willEnterForegroundNotification, object: "scene-B")
            XCTAssertEqual(commandSubscriber.receivedCommands.count, 1)
            XCTAssertEqual((commandSubscriber.receivedCommands[0] as? RUMStartViewCommand)?.target, .scene(sceneB))
            XCTAssertFalse(handler.canTrackViews(in: sceneA))
            notificationCenter.post(name: UIScene.didDisconnectNotification, object: "scene-B")
            XCTAssertEqual(nonemptyHandlerCollections(handler), [:])
            XCTAssertEqual(inventoryReads, 1)
        }
    }

    @MainActor
    func testBootstrapPeerRemainsKnownAfterFirstSceneLifecycleBoundary() {
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
        let handler = createHandler(sceneIdentifierFromNotification: { _ in sceneA })
        for (scene, identity) in [(sceneA, "first"), (sceneB, "peer")] {
            handler.notify_onAppear(identity: identity, name: identity, path: identity, attributes: [:], sceneIdentifier: scene)
        }
        notificationCenter.post(name: UIScene.didDisconnectNotification, object: nil)
        XCTAssertFalse(handler.canTrackViews(in: sceneA))
        XCTAssertTrue(handler.canTrackViews(in: sceneB))
        handler.notify_onAppear(identity: "peer-next", name: "Peer Next", path: "/peer", attributes: [:], sceneIdentifier: sceneB)
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 5)
        XCTAssertEqual((commandSubscriber.receivedCommands.last as? RUMStartViewCommand)?.target, .scene(sceneB))
    }

    @MainActor
    func testAllSceneViewSourcesRejectRetiredIdentityUntilReconnection() {
        let scene = RUMSceneIdentifier(rawValue: "reused")
        let controller = UIViewController()
        let handler = createHandler(
            uiKitPredicate: UIKitRUMViewsPredicateMock(result: RUMView(name: "UIKit")),
            sceneIdentifierProvider: { _ in scene },
            sceneIdentifierFromNotification: { _ in scene }
        )
        for index in 0..<20 {
            notificationCenter.post(name: UIScene.willConnectNotification, object: nil)
            handler.startView(key: "manual", name: "Manual", attributes: [:], sceneIdentifier: scene)
            XCTAssertEqual(commandSubscriber.receivedCommands.count, index * 2)
            notificationCenter.post(name: UIScene.willEnterForegroundNotification, object: nil)
            notificationCenter.post(name: UIScene.didDisconnectNotification, object: nil)
            handler.notify_viewDidAppear(viewController: controller, animated: false)
            handler.notify_onAppear(identity: "late", name: "Late", path: "/late", attributes: [:], sceneIdentifier: scene)
            handler.startView(key: "late-manual", name: "Late", attributes: [:], sceneIdentifier: scene)
            XCTAssertFalse(handler.notify_semanticDestinationAppear(
                identity: "late-semantic", name: "Late", path: "/late", attributes: [:], sceneIdentifier: scene
            ))
            handler.notify_replaceOccurrence(
                oldIdentity: "manual", newIdentity: "late-replace", name: "Late", path: "/late", attributes: [:], sceneIdentifier: scene
            )
            notificationCenter.post(name: UIScene.didEnterBackgroundNotification, object: nil)
            XCTAssertEqual(commandSubscriber.receivedCommands.count, (index + 1) * 2)
            XCTAssertEqual(nonemptyHandlerCollections(handler), [:])
        }
    }

    @MainActor
    func testBackgroundInitializationReadsInitialSceneInventoryOnceOnMain() async {
        let seeded = expectation(description: "main-thread scene inventory")
        let scene = RUMSceneIdentifier(rawValue: "initial")
        let handler: RUMViewsHandler = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let handler = RUMViewsHandler(
                    dateProvider: SystemDateProvider(),
                    uiKitPredicate: nil,
                    swiftUIPredicate: nil,
                    swiftUIViewNameExtractor: nil,
                    notificationCenter: NotificationCenter(),
                    initialSceneActivityProvider: {
                        XCTAssertTrue(Thread.isMainThread)
                        seeded.fulfill()
                        return [scene: true]
                    }
                )
                continuation.resume(returning: handler)
            }
        }
        await fulfillment(of: [seeded], timeout: 5)
        XCTAssertTrue(handler.canTrackViews(in: scene))
        XCTAssertEqual(nonemptyHandlerCollections(handler), ["sceneActivityByIdentifier": 1])
    }

    @MainActor
    func testPendingInitialSceneInventoryDoesNotRetainHandler() async {
        weak var releasedHandler: RUMViewsHandler?
        let initialized = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            XCTAssertFalse(Thread.isMainThread)
            autoreleasepool {
                let handler = RUMViewsHandler(
                    dateProvider: SystemDateProvider(),
                    uiKitPredicate: nil,
                    swiftUIPredicate: nil,
                    swiftUIViewNameExtractor: nil,
                    notificationCenter: NotificationCenter(),
                    initialSceneActivityProvider: {
                        XCTFail("Released handler must not read scene inventory")
                        return [:]
                    }
                )
                releasedHandler = handler
            }
            initialized.signal()
        }
        XCTAssertEqual(initialized.wait(timeout: .now() + 5), .success)
        XCTAssertNil(releasedHandler)
        await Task.yield()
        XCTAssertNil(releasedHandler)
    }

    private func nonemptyHandlerCollections(_ handler: RUMViewsHandler) -> [String: Int] {
        var result: [String: Int] = [:]
        for child in Mirror(reflecting: handler).children {
            let value = Mirror(reflecting: child.value)
            if let label = child.label,
               [.collection, .dictionary, .set].contains(value.displayStyle),
               !value.children.isEmpty {
                result[label] = value.children.count
            }
        }
        return result
    }

    func testWhenSceneDisconnects_itRejectsStaleStateUntilFreshSceneConnection() throws {
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
        let state = RUMViewTrackingState(identity: "home-A")
        let descriptor = RUMViewTrackingState.Configuration.Descriptor(
            name: "Home A",
            path: "/home/A",
            attributes: [:]
        )
        let handler = createHandler(
            sceneIdentifierFromNotification: { notification in
                notification.object as? String == "scene-A" ? sceneA : nil
            }
        )
        let arbiter = RUMSwiftUIInteractiveTransitionArbiter(
            notificationCenter: notificationCenter,
            coordinatorProvider: { _, _ in nil }
        )
        let observer = RUMSceneIdentifierReader.ObserverView { _ in }
        arbiter.register(observer: observer, for: state)

        RUMSwiftUIViewTransitionPublisher.publish(
            state.mount(in: sceneA),
            state: state,
            fallback: descriptor,
            to: handler
        )
        handler.notify_onAppear(
            identity: "home-B",
            name: "Home B",
            path: "/home/B",
            attributes: [:],
            sceneIdentifier: sceneB
        )
        notificationCenter.post(name: UIScene.didDisconnectNotification, object: "scene-A")
        arbiter.discard(sceneIdentifier: sceneA)
        RUMSwiftUIViewTransitionPublisher.publish(
            state.appear(),
            state: state,
            fallback: descriptor,
            to: handler
        )
        RUMSwiftUIViewTransitionPublisher.publish(
            state.mount(in: sceneA),
            state: state,
            fallback: descriptor,
            to: handler
        )

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)
        let firstAStart = try XCTUnwrap(
            commandSubscriber.receivedCommands[0] as? RUMStartViewCommand
        )
        let bStart = try XCTUnwrap(
            commandSubscriber.receivedCommands[1] as? RUMStartViewCommand
        )
        let aStop = try XCTUnwrap(
            commandSubscriber.receivedCommands[2] as? RUMStopViewCommand
        )
        XCTAssertTrue(firstAStart.identity == ViewIdentifier("home-A"))
        XCTAssertEqual(firstAStart.target, .scene(sceneA))
        XCTAssertTrue(bStart.identity == ViewIdentifier("home-B"))
        XCTAssertEqual(bStart.target, .scene(sceneB))
        XCTAssertTrue(aStop.identity == ViewIdentifier("home-A"))
        XCTAssertEqual(aStop.target, .scene(sceneA))
        XCTAssertEqual(state.lifecycleGeneration, 2)
        XCTAssertFalse(commandSubscriber.receivedCommands.contains { command in
            (command as? RUMStopViewCommand)?.target == .scene(sceneB)
        })

        notificationCenter.post(
            name: UIScene.willConnectNotification,
            object: "scene-A"
        )
        notificationCenter.post(
            name: UIScene.willEnterForegroundNotification,
            object: "scene-A"
        )
        let reconnectedState = RUMViewTrackingState(identity: "home-A-reconnected")
        RUMSwiftUIViewTransitionPublisher.publish(
            reconnectedState.mount(in: sceneA),
            state: reconnectedState,
            fallback: descriptor,
            to: handler
        )

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 4)
        let reconnectedAStart = try XCTUnwrap(
            commandSubscriber.receivedCommands.last as? RUMStartViewCommand
        )
        XCTAssertTrue(
            reconnectedAStart.identity == ViewIdentifier("home-A-reconnected")
        )
        XCTAssertEqual(reconnectedAStart.target, .scene(sceneA))
    }
    #endif
    #endif

    func testWhenCoveredSwiftUIOccurrenceIsReplaced_itDoesNotDisturbVisibleView() throws {
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let handler = createHandler()
        handler.notify_onAppear(
            identity: "home-1",
            name: "Home",
            path: "Home",
            attributes: [:],
            sceneIdentifier: scene
        )
        handler.notify_onAppear(
            identity: "detail",
            name: "Detail",
            path: "Detail",
            attributes: [:],
            sceneIdentifier: scene
        )

        handler.notify_replaceOccurrence(
            oldIdentity: "home-1",
            newIdentity: "home-2",
            name: "Home",
            path: "Home",
            attributes: ["instance": 2],
            sceneIdentifier: scene
        )

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)

        handler.notify_onDisappear(identity: "detail", sceneIdentifier: scene)

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 5)
        let stop = try XCTUnwrap(commandSubscriber.receivedCommands[3] as? RUMStopViewCommand)
        let start = try XCTUnwrap(commandSubscriber.receivedCommands[4] as? RUMStartViewCommand)
        XCTAssertTrue(stop.identity == ViewIdentifier("detail"))
        XCTAssertTrue(start.identity == ViewIdentifier("home-2"))
        XCTAssertEqual(start.attributes["instance"] as? Int, 2)

        handler.notify_onDisappear(identity: "home-2", sceneIdentifier: scene)

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 6)
        let finalStop = try XCTUnwrap(commandSubscriber.receivedCommands[5] as? RUMStopViewCommand)
        XCTAssertTrue(finalStop.identity == ViewIdentifier("home-2"))
        XCTAssertFalse(commandSubscriber.receivedCommands.dropFirst(5).contains { command in
            (command as? RUMStartViewCommand)?.identity == ViewIdentifier("home-1")
        })
    }

    func testWhenSameNamedSwiftUIOccurrenceIsReplaced_itUsesFreshIdentity() throws {
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let handler = createHandler()
        handler.notify_onAppear(
            identity: "detail-1",
            name: "Detail",
            path: "Detail",
            attributes: [:],
            sceneIdentifier: scene
        )

        handler.notify_replaceOccurrence(
            oldIdentity: "detail-1",
            newIdentity: "detail-2",
            name: "Detail",
            path: "Detail",
            attributes: [:],
            sceneIdentifier: scene
        )

        let startCommands = commandSubscriber.receivedCommands.compactMap { $0 as? RUMStartViewCommand }
        XCTAssertEqual(startCommands.count, 2)
        XCTAssertEqual(startCommands.map(\.name), ["Detail", "Detail"])
        XCTAssertTrue(startCommands[0].identity == ViewIdentifier("detail-1"))
        XCTAssertTrue(startCommands[1].identity == ViewIdentifier("detail-2"))
    }

    func testWhenSwiftUIOccurrencesShareIdentityAcrossScenes_replacementTouchesOnlyTargetScene() throws {
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
        let handler = createHandler()
        for scene in [sceneA, sceneB] {
            handler.notify_onAppear(
                identity: "detail-1",
                name: "Detail",
                path: "Detail",
                attributes: [:],
                sceneIdentifier: scene
            )
        }

        handler.notify_replaceOccurrence(
            oldIdentity: "detail-1",
            newIdentity: "detail-2",
            name: "Detail",
            path: "Detail",
            attributes: [:],
            sceneIdentifier: sceneA
        )

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 4)
        let stop = try XCTUnwrap(commandSubscriber.receivedCommands[2] as? RUMStopViewCommand)
        let start = try XCTUnwrap(commandSubscriber.receivedCommands[3] as? RUMStartViewCommand)
        XCTAssertTrue(stop.identity == ViewIdentifier("detail-1"))
        XCTAssertTrue(start.identity == ViewIdentifier("detail-2"))
        XCTAssertEqual(stop.target, .scene(sceneA))
        XCTAssertEqual(start.target, .scene(sceneA))
        XCTAssertFalse(commandSubscriber.receivedCommands.dropFirst(2).contains { command in
            command.target == .scene(sceneB)
        })

        handler.notify_onDisappear(identity: "detail-1", sceneIdentifier: sceneB)

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 5)
        let sceneBStop = try XCTUnwrap(commandSubscriber.receivedCommands[4] as? RUMStopViewCommand)
        XCTAssertTrue(sceneBStop.identity == ViewIdentifier("detail-1"))
        XCTAssertEqual(sceneBStop.target, .scene(sceneB))
    }

    func testWhenOldSwiftUIOccurrenceIsMissing_replacementDoesNotMaterializeNewOccurrence() {
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let handler = createHandler()
        handler.notify_onAppear(
            identity: "current",
            name: "Current",
            path: "Current",
            attributes: [:],
            sceneIdentifier: scene
        )

        handler.notify_replaceOccurrence(
            oldIdentity: "missing",
            newIdentity: "candidate",
            name: "Candidate",
            path: "Candidate",
            attributes: [:],
            sceneIdentifier: scene
        )

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 1)
        XCTAssertTrue(
            (commandSubscriber.receivedCommands[0] as? RUMStartViewCommand)?.identity
                == ViewIdentifier("current")
        )

        handler.notify_onDisappear(identity: "current", sceneIdentifier: scene)

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 2)
        XCTAssertTrue(
            (commandSubscriber.receivedCommands[1] as? RUMStopViewCommand)?.identity
                == ViewIdentifier("current")
        )
    }

    func testWhenInactiveSwiftUIOccurrenceIsReplaced_itStartsReplacementOnForeground() throws {
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let handler = createHandler(
            sceneIdentifierFromNotification: { notification in
                notification.object as? String == "scene-A" ? scene : nil
            }
        )
        handler.notify_onAppear(
            identity: "home-1",
            name: "Home",
            path: "Home",
            attributes: ["instance": 1],
            sceneIdentifier: scene
        )
        notificationCenter.post(name: UIScene.didEnterBackgroundNotification, object: "scene-A")

        handler.notify_replaceOccurrence(
            oldIdentity: "home-1",
            newIdentity: "home-2",
            name: "Home",
            path: "Home",
            attributes: ["instance": 2],
            sceneIdentifier: scene
        )

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 2)

        notificationCenter.post(name: UIScene.willEnterForegroundNotification, object: "scene-A")

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)
        let start = try XCTUnwrap(commandSubscriber.receivedCommands[2] as? RUMStartViewCommand)
        XCTAssertTrue(start.identity == ViewIdentifier("home-2"))
        XCTAssertEqual(start.attributes["instance"] as? Int, 2)
        XCTAssertEqual(start.target, .scene(scene))
    }

    func testWhenReplacementTargetsAnotherScene_itDoesNotMigrateOrMaterializeOccurrence() throws {
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
        let handler = createHandler()
        handler.notify_onAppear(
            identity: "detail-1",
            name: "Detail",
            path: "Detail",
            attributes: [:],
            sceneIdentifier: sceneA
        )

        handler.notify_replaceOccurrence(
            oldIdentity: "detail-1",
            newIdentity: "detail-2",
            name: "Detail",
            path: "Detail",
            attributes: [:],
            sceneIdentifier: sceneB
        )

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 1)

        handler.notify_onDisappear(identity: "detail-1", sceneIdentifier: sceneA)

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 2)
        let stop = try XCTUnwrap(commandSubscriber.receivedCommands[1] as? RUMStopViewCommand)
        XCTAssertTrue(stop.identity == ViewIdentifier("detail-1"))
        XCTAssertEqual(stop.target, .scene(sceneA))
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

        notificationCenter.post(name: ApplicationNotifications.didEnterBackground, object: nil)
        dateProvider.advance(bySeconds: 1)
        notificationCenter.post(name: ApplicationNotifications.willEnterForeground, object: nil)

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

        notificationCenter.post(name: ApplicationNotifications.willResignActive, object: nil)
        dateProvider.advance(bySeconds: 1)
        notificationCenter.post(name: ApplicationNotifications.didBecomeActive, object: nil)

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 0)
    }

    #if os(iOS)
    @available(iOS 27.0, *)
    @MainActor
    func testPresentationBindingRejectsDismissalWithoutStoppingAcceptedOwner() {
        let handler = createHandler()
        let state = RUMSwiftUISemanticNavigationState<String, SemanticPresentation>()
        let item = SemanticPresentation(id: "document", name: "Document", style: .sheet)
        state.reconcilePresentation(item, descriptor: semanticDescriptor(for:), viewsHandler: handler)
        state.mountPresentation(state.presentationOccurrence(for: item, style: item.style), in: RUMSceneIdentifier(rawValue: "scene"), viewsHandler: handler)
        var writes = 0
        var commandsInsideSetter = 0
        var transactionForwarded = false
        let binding = state.presentationBinding(
            for: .sheet,
            to: Binding(get: { item }, set: { _, transaction in
                writes += 1
                commandsInsideSetter = self.commandSubscriber.receivedCommands.count
                transactionForwarded = transaction.disablesAnimations
            }),
            descriptor: semanticDescriptor(for:),
            viewsHandler: { handler }
        )
        var transaction = Transaction()
        transaction.disablesAnimations = true
        binding.transaction(transaction).wrappedValue = nil
        XCTAssertEqual(writes, 1)
        XCTAssertTrue(transactionForwarded)
        XCTAssertEqual(commandsInsideSetter, 1)
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 1)
        XCTAssertEqual(binding.wrappedValue, item)
        XCTAssertNil(state.consumeDismissed(style: .sheet))
    }

    @available(iOS 27.0, *)
    @MainActor
    func testPresentationBindingCanonicalizesProposedItemBeforeTrackingReplacement() {
        let handler = createHandler()
        let state = RUMSwiftUISemanticNavigationState<String, SemanticPresentation>()
        let original = SemanticPresentation(id: "original", name: "Original", style: .sheet)
        let proposal = SemanticPresentation(id: "proposal", name: "Proposal", style: .sheet)
        let canonical = SemanticPresentation(id: "canonical", name: "Canonical", style: .fullScreenCover)
        var accepted: SemanticPresentation? = original
        state.reconcilePresentation(original, descriptor: semanticDescriptor(for:), viewsHandler: handler)
        let scene = RUMSceneIdentifier(rawValue: "scene")
        state.mountPresentation(state.presentationOccurrence(for: original, style: original.style), in: scene, viewsHandler: handler)
        let binding = state.presentationBinding(
            for: .sheet,
            to: Binding(get: { accepted }, set: { _ in accepted = canonical }),
            descriptor: semanticDescriptor(for:),
            viewsHandler: { handler }
        )
        binding.wrappedValue = proposal
        XCTAssertEqual(accepted, canonical)
        XCTAssertEqual(state.presentationStyle(for: canonical), .fullScreenCover)
        XCTAssertNil(state.presentationStyle(for: proposal))
        state.mountPresentation(state.presentationOccurrence(for: canonical, style: canonical.style), in: scene, viewsHandler: handler)
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)
        XCTAssertEqual((commandSubscriber.receivedCommands.last as? RUMStartViewCommand)?.name, "Canonical")
        XCTAssertNil(state.consumeDismissed(style: .sheet))
    }

    @available(iOS 27.0, *)
    @MainActor
    func testPresentationBindingRejectsReplacementWithoutChangingAcceptedDescriptor() {
        let handler = createHandler()
        let state = RUMSwiftUISemanticNavigationState<String, SemanticPresentation>()
        let item = SemanticPresentation(id: "accepted", name: "Accepted", style: .sheet)
        let proposal = SemanticPresentation(id: "proposal", name: "Proposal", style: .fullScreenCover)
        state.reconcilePresentation(item, descriptor: semanticDescriptor(for:), viewsHandler: handler)
        state.mountPresentation(state.presentationOccurrence(for: item, style: item.style), in: RUMSceneIdentifier(rawValue: "scene"), viewsHandler: handler)
        let binding = state.presentationBinding(
            for: .sheet,
            to: Binding(get: { item }, set: { _ in }),
            descriptor: semanticDescriptor(for:),
            viewsHandler: { handler }
        )
        binding.wrappedValue = proposal
        XCTAssertEqual(binding.wrappedValue, item)
        XCTAssertEqual(state.presentationStyle(for: item), .sheet)
        XCTAssertNil(state.presentationStyle(for: proposal))
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 1)
    }

    @available(iOS 27.0, *)
    @MainActor
    func testOldSameIDSheetDisappearanceCannotStopReplacementCover() {
        let handler = createHandler()
        let state = RUMSwiftUISemanticNavigationState<String, SemanticPresentation>()
        let sheet = SemanticPresentation(id: "same", name: "Sheet", style: .sheet)
        let cover = SemanticPresentation(id: "same", name: "Cover", style: .fullScreenCover)
        let scene = RUMSceneIdentifier(rawValue: "scene")
        state.reconcilePresentation(sheet, descriptor: semanticDescriptor(for:), viewsHandler: handler)
        state.mountPresentation(state.presentationOccurrence(for: sheet, style: sheet.style), in: scene, viewsHandler: handler)
        let oldOccurrence = state.presentationOccurrence(for: sheet, style: sheet.style)
        let oldDisappear = { state.presentationDidDisappear(oldOccurrence, viewsHandler: handler) }
        state.reconcilePresentation(cover, descriptor: semanticDescriptor(for:), viewsHandler: handler)
        XCTAssertNotNil(oldOccurrence)
        XCTAssertFalse(state.mountPresentation(oldOccurrence, in: scene, viewsHandler: handler))
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 1)
        state.mountPresentation(state.presentationOccurrence(for: cover, style: cover.style), in: scene, viewsHandler: handler)
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)
        oldDisappear()
        XCTAssertFalse(state.mountPresentation(oldOccurrence, in: scene, viewsHandler: handler))
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)
    }

    @available(iOS 27.0, *)
    @MainActor
    func testEarlierPresentationACallbackCannotStopLaterAOccurrence() {
        let handler = createHandler()
        let state = RUMSwiftUISemanticNavigationState<String, SemanticPresentation>()
        let first = SemanticPresentation(id: "A", name: "A", style: .sheet)
        let second = SemanticPresentation(id: "B", name: "B", style: .sheet)
        let scene = RUMSceneIdentifier(rawValue: "scene")
        state.reconcilePresentation(first, descriptor: semanticDescriptor(for:), viewsHandler: handler)
        state.mountPresentation(state.presentationOccurrence(for: first, style: first.style), in: scene, viewsHandler: handler)
        let oldOccurrence = state.presentationOccurrence(for: first, style: first.style)
        let oldDisappear = { state.presentationDidDisappear(oldOccurrence, viewsHandler: handler) }
        for item in [second, first] {
            state.reconcilePresentation(item, descriptor: semanticDescriptor(for:), viewsHandler: handler)
            state.mountPresentation(state.presentationOccurrence(for: item, style: item.style), in: scene, viewsHandler: handler)
        }
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 5)
        oldDisappear()
        XCTAssertNotNil(oldOccurrence)
        XCTAssertFalse(state.mountPresentation(oldOccurrence, in: scene, viewsHandler: handler))
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 5)
    }

    @available(iOS 27.0, *)
    @MainActor
    func testRejectedPresentationMountCanRetryAfterSceneReconnect() {
        let scene = RUMSceneIdentifier(rawValue: "scene")
        let handler = createHandler(sceneIdentifierFromNotification: { _ in scene })
        let state = RUMSwiftUISemanticNavigationState<String, SemanticPresentation>()
        let item = SemanticPresentation(id: "sheet", name: "Sheet", style: .sheet)
        notificationCenter.post(name: UIScene.didDisconnectNotification, object: nil)
        state.reconcilePresentation(item, descriptor: semanticDescriptor(for:), viewsHandler: handler)
        state.mountPresentation(state.presentationOccurrence(for: item, style: item.style), in: scene, viewsHandler: handler)
        XCTAssertTrue(commandSubscriber.receivedCommands.isEmpty)
        notificationCenter.post(name: UIScene.willConnectNotification, object: nil)
        notificationCenter.post(name: UIScene.willEnterForegroundNotification, object: nil)
        state.mountPresentation(state.presentationOccurrence(for: item, style: item.style), in: scene, viewsHandler: handler)
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 1)
        state.reconcilePresentation(nil, descriptor: semanticDescriptor(for:), viewsHandler: handler)
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 2)
        XCTAssertEqual(state.consumeDismissed(style: .sheet), item)
    }

    @available(iOS 27.0, *)
    @MainActor
    func testAcceptedPresentationDismissalRevealsBeforeSetterReturnsToCaller() throws {
        let handler = createHandler()
        let state = RUMSwiftUISemanticNavigationState<String, SemanticPresentation>()
        let item = SemanticPresentation(id: "sheet", name: "Sheet", style: .sheet)
        let scene = RUMSceneIdentifier(rawValue: "scene")
        var accepted: SemanticPresentation? = item
        handler.notify_onAppear(identity: "home", name: "Home", path: "/home", attributes: [:], sceneIdentifier: scene)
        state.reconcilePresentation(item, descriptor: semanticDescriptor(for:), viewsHandler: handler)
        let occurrence = state.presentationOccurrence(for: item, style: item.style)
        state.mountPresentation(occurrence, in: scene, viewsHandler: handler)
        var writes = 0
        let binding = state.presentationBinding(
            for: .sheet,
            to: Binding(get: { accepted }, set: { proposal in
                writes += 1
                XCTAssertEqual(self.commandSubscriber.receivedCommands.count, 3)
                accepted = proposal
            }),
            descriptor: semanticDescriptor(for:),
            viewsHandler: { handler }
        )
        binding.wrappedValue = nil
        XCTAssertEqual(writes, 1)
        XCTAssertNil(accepted)
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 5)
        let reveal = try XCTUnwrap(commandSubscriber.receivedCommands.last as? RUMStartViewCommand)
        XCTAssertEqual(reveal.name, "Home")
        XCTAssertEqual(reveal.target, .scene(scene))
        XCTAssertEqual(state.consumeDismissed(style: .sheet), item)
        XCTAssertNil(state.consumeDismissed(style: .sheet))
        state.presentationDidDisappear(occurrence, viewsHandler: handler)
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 5)
    }

    @available(iOS 27.0, *)
    @MainActor
    func testCanonicalizedDismissalKeepsMountedOwnerUntilAcceptedCoverMounts() {
        let handler = createHandler()
        let state = RUMSwiftUISemanticNavigationState<String, SemanticPresentation>()
        let sheet = SemanticPresentation(id: "same", name: "Sheet", style: .sheet)
        let cover = SemanticPresentation(id: "same", name: "Cover", style: .fullScreenCover)
        let scene = RUMSceneIdentifier(rawValue: "scene")
        var accepted: SemanticPresentation? = sheet
        state.reconcilePresentation(sheet, descriptor: semanticDescriptor(for:), viewsHandler: handler)
        let sheetOccurrence = state.presentationOccurrence(for: sheet, style: sheet.style)
        state.mountPresentation(sheetOccurrence, in: scene, viewsHandler: handler)
        var writes = 0
        let binding = state.presentationBinding(
            for: .sheet,
            to: Binding(get: { accepted }, set: { _ in
                writes += 1
                accepted = cover
            }),
            descriptor: semanticDescriptor(for:),
            viewsHandler: { handler }
        )
        binding.wrappedValue = nil
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 1)
        XCTAssertNil(state.consumeDismissed(style: .sheet))
        let coverOccurrence = state.presentationOccurrence(for: cover, style: cover.style)
        state.mountPresentation(coverOccurrence, in: scene, viewsHandler: handler)
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)
        binding.wrappedValue = nil
        XCTAssertEqual(writes, 1)
        state.presentationDidDisappear(sheetOccurrence, viewsHandler: handler)
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)
    }

    @available(iOS 27.0, *)
    @MainActor
    func testPresentationDescriptorRefreshKeepsOccurrenceAndDuplicateMountIsIdempotent() {
        let handler = createHandler()
        let state = RUMSwiftUISemanticNavigationState<String, SemanticPresentation>()
        let first = SemanticPresentation(id: "same", name: "First", style: .sheet)
        let latest = SemanticPresentation(id: "same", name: "Latest", style: .sheet)
        let scene = RUMSceneIdentifier(rawValue: "scene")
        state.reconcilePresentation(first, descriptor: semanticDescriptor(for:), viewsHandler: handler)
        let occurrence = state.presentationOccurrence(for: first, style: first.style)
        XCTAssertFalse(state.mountPresentation(occurrence, in: scene, viewsHandler: nil))
        XCTAssertNil(state.consumeDismissed(style: .sheet))
        state.reconcilePresentation(latest, descriptor: semanticDescriptor(for:), viewsHandler: handler)
        XCTAssertEqual(state.presentationOccurrence(for: latest, style: latest.style), occurrence)
        XCTAssertTrue(state.mountPresentation(occurrence, in: scene, viewsHandler: handler))
        XCTAssertTrue(state.mountPresentation(occurrence, in: scene, viewsHandler: handler))
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 1)
        XCTAssertEqual((commandSubscriber.receivedCommands.last as? RUMStartViewCommand)?.name, "Latest")
        state.reconcilePresentation(nil, descriptor: semanticDescriptor(for:), viewsHandler: handler)
        XCTAssertEqual(state.consumeDismissed(style: .sheet), latest)
        XCTAssertNil(state.consumeDismissed(style: .sheet))
    }

    @available(iOS 27.0, *)
    @MainActor
    func testRejectedPresentationMigrationPreservesOwnerAndDisconnectInvalidatesToken() {
        let sceneA = RUMSceneIdentifier(rawValue: "A")
        let sceneB = RUMSceneIdentifier(rawValue: "B")
        let handler = createHandler(sceneIdentifierFromNotification: { notification in
            (notification.object as? String).map(RUMSceneIdentifier.init(rawValue:))
        })
        let state = RUMSwiftUISemanticNavigationState<String, SemanticPresentation>()
        let item = SemanticPresentation(id: "sheet", name: "Sheet", style: .sheet)
        state.reconcilePresentation(item, descriptor: semanticDescriptor(for:), viewsHandler: handler)
        let old = state.presentationOccurrence(for: item, style: item.style)
        XCTAssertTrue(state.mountPresentation(old, in: sceneA, viewsHandler: handler))
        notificationCenter.post(name: UIScene.didDisconnectNotification, object: "B")
        XCTAssertFalse(state.mountPresentation(old, in: sceneB, viewsHandler: handler))
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 1)
        notificationCenter.post(name: UIScene.didDisconnectNotification, object: "A")
        state.sceneDidDisconnect(sceneA)
        state.reconcilePresentation(item, descriptor: semanticDescriptor(for:), viewsHandler: handler)
        let fresh = state.presentationOccurrence(for: item, style: item.style)
        XCTAssertNotEqual(old, fresh)
        notificationCenter.post(name: UIScene.willConnectNotification, object: "A")
        notificationCenter.post(name: UIScene.willEnterForegroundNotification, object: "A")
        XCTAssertFalse(state.mountPresentation(old, in: sceneA, viewsHandler: handler))
        XCTAssertTrue(state.mountPresentation(fresh, in: sceneA, viewsHandler: handler))
        state.presentationDidDisappear(old, viewsHandler: handler)
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)
    }

    @available(iOS 27.0, *)
    @MainActor
    func testSemanticPresentationThatNeverMounts_doesNotPublishOrReportDismissal() {
        let handler = createHandler()
        let state = RUMSwiftUISemanticNavigationState<String, SemanticPresentation>()
        let presentation = SemanticPresentation(
            id: "sheet",
            name: "Sheet",
            style: .sheet
        )

        state.reconcilePresentation(
            presentation,
            descriptor: semanticDescriptor(for:),
            viewsHandler: handler
        )
        state.reconcilePresentation(
            nil,
            descriptor: semanticDescriptor(for:),
            viewsHandler: handler
        )

        XCTAssertTrue(commandSubscriber.receivedCommands.isEmpty)
        XCTAssertNil(state.consumeDismissed(style: .sheet))
    }

    @available(iOS 27.0, *)
    @MainActor
    func testMountedSemanticPresentation_stopsBeforeRevealingUnderlyingDestination() throws {
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let handler = createHandler()
        let state = RUMSwiftUISemanticNavigationState<String, SemanticPresentation>()
        let presentation = SemanticPresentation(
            id: "sheet",
            name: "Sheet",
            style: .sheet
        )

        handler.notify_onAppear(
            identity: "home",
            name: "Home",
            path: "/home",
            attributes: [:],
            sceneIdentifier: scene
        )
        state.reconcilePresentation(
            presentation,
            descriptor: semanticDescriptor(for:),
            viewsHandler: handler
        )
        state.mountPresentation(state.presentationOccurrence(for: presentation, style: presentation.style), in: scene, viewsHandler: handler)
        state.mountPresentation(state.presentationOccurrence(for: presentation, style: presentation.style), in: scene, viewsHandler: handler)
        state.reconcilePresentation(
            nil,
            descriptor: semanticDescriptor(for:),
            viewsHandler: handler
        )

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 5)
        let homeStart = try XCTUnwrap(commandSubscriber.receivedCommands[0] as? RUMStartViewCommand)
        let homeStop = try XCTUnwrap(commandSubscriber.receivedCommands[1] as? RUMStopViewCommand)
        let presentationStart = try XCTUnwrap(commandSubscriber.receivedCommands[2] as? RUMStartViewCommand)
        let presentationStop = try XCTUnwrap(commandSubscriber.receivedCommands[3] as? RUMStopViewCommand)
        let revealedHome = try XCTUnwrap(commandSubscriber.receivedCommands[4] as? RUMStartViewCommand)
        XCTAssertEqual(homeStart.identity, ViewIdentifier("home"))
        XCTAssertEqual(homeStop.identity, ViewIdentifier("home"))
        XCTAssertEqual(presentationStart.identity, presentationStop.identity)
        XCTAssertEqual(presentationStart.name, "Sheet")
        XCTAssertEqual(presentationStart.path, "/semantic/sheet")
        XCTAssertEqual(presentationStart.instrumentationType, .manual)
        XCTAssertEqual(revealedHome.identity, ViewIdentifier("home"))
        XCTAssertEqual(revealedHome.instrumentationType, .swiftui)
        XCTAssertTrue(commandSubscriber.receivedCommands.allSatisfy { $0.target == .scene(scene) })
        XCTAssertEqual(state.consumeDismissed(style: .sheet), presentation)
        XCTAssertNil(state.consumeDismissed(style: .sheet))
    }

    @available(iOS 27.0, *)
    @MainActor
    func testMountedSemanticPresentation_revealsOnlyLatestUnderlyingDestination() throws {
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let handler = createHandler()
        let state = RUMSwiftUISemanticNavigationState<String, SemanticPresentation>()
        let presentation = SemanticPresentation(
            id: "sheet",
            name: "Sheet",
            style: .sheet
        )

        handler.notify_onAppear(
            identity: "home",
            name: "Home",
            path: "/home",
            attributes: [:],
            sceneIdentifier: scene
        )
        state.reconcilePresentation(
            presentation,
            descriptor: semanticDescriptor(for:),
            viewsHandler: handler
        )
        state.mountPresentation(state.presentationOccurrence(for: presentation, style: presentation.style), in: scene, viewsHandler: handler)
        handler.notify_onAppear(
            identity: "detail",
            name: "Detail",
            path: "/detail",
            attributes: [:],
            sceneIdentifier: scene
        )
        handler.notify_onDisappear(identity: "home", sceneIdentifier: scene)

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)

        state.reconcilePresentation(
            nil,
            descriptor: semanticDescriptor(for:),
            viewsHandler: handler
        )

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 5)
        let presentationStart = try XCTUnwrap(
            commandSubscriber.receivedCommands[2] as? RUMStartViewCommand
        )
        let presentationStop = try XCTUnwrap(
            commandSubscriber.receivedCommands[3] as? RUMStopViewCommand
        )
        let revealedDetail = try XCTUnwrap(
            commandSubscriber.receivedCommands[4] as? RUMStartViewCommand
        )
        XCTAssertEqual(presentationStart.identity, presentationStop.identity)
        XCTAssertEqual(presentationStart.instrumentationType, .manual)
        XCTAssertEqual(revealedDetail.identity, ViewIdentifier("detail"))
        XCTAssertEqual(revealedDetail.name, "Detail")
        XCTAssertEqual(revealedDetail.instrumentationType, .swiftui)
        XCTAssertFalse(commandSubscriber.receivedCommands.prefix(4).contains { command in
            (command as? RUMStartViewCommand)?.identity == ViewIdentifier("detail")
        })
        XCTAssertTrue(commandSubscriber.receivedCommands.allSatisfy { $0.target == .scene(scene) })
    }

    @available(iOS 27.0, *)
    @MainActor
    func testMountedSemanticPresentationReplacement_doesNotRevealUnderlyingDestination() throws {
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let handler = createHandler()
        let state = RUMSwiftUISemanticNavigationState<String, SemanticPresentation>()
        let sheet = SemanticPresentation(id: "sheet", name: "Sheet", style: .sheet)
        let cover = SemanticPresentation(
            id: "cover",
            name: "Cover",
            style: .fullScreenCover
        )

        handler.notify_onAppear(
            identity: "home",
            name: "Home",
            path: "/home",
            attributes: [:],
            sceneIdentifier: scene
        )
        state.reconcilePresentation(
            sheet,
            descriptor: semanticDescriptor(for:),
            viewsHandler: handler
        )
        state.mountPresentation(state.presentationOccurrence(for: sheet, style: sheet.style), in: scene, viewsHandler: handler)
        state.reconcilePresentation(
            cover,
            descriptor: semanticDescriptor(for:),
            viewsHandler: handler
        )

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)

        state.mountPresentation(state.presentationOccurrence(for: cover, style: cover.style), in: scene, viewsHandler: handler)

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 5)
        let sheetStart = try XCTUnwrap(
            commandSubscriber.receivedCommands[2] as? RUMStartViewCommand
        )
        let sheetStop = try XCTUnwrap(
            commandSubscriber.receivedCommands[3] as? RUMStopViewCommand
        )
        let coverStart = try XCTUnwrap(
            commandSubscriber.receivedCommands[4] as? RUMStartViewCommand
        )
        XCTAssertEqual(sheetStop.identity, sheetStart.identity)
        XCTAssertEqual(coverStart.name, "Cover")
        XCTAssertEqual(coverStart.instrumentationType, .manual)
        XCTAssertFalse(
            commandSubscriber.receivedCommands[3...4].contains { command in
                (command as? RUMStartViewCommand)?.identity == ViewIdentifier("home")
            }
        )

        state.reconcilePresentation(
            nil,
            descriptor: semanticDescriptor(for:),
            viewsHandler: handler
        )

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 7)
        let coverStop = try XCTUnwrap(
            commandSubscriber.receivedCommands[5] as? RUMStopViewCommand
        )
        let revealedHome = try XCTUnwrap(
            commandSubscriber.receivedCommands[6] as? RUMStartViewCommand
        )
        XCTAssertEqual(coverStop.identity, coverStart.identity)
        XCTAssertEqual(revealedHome.identity, ViewIdentifier("home"))
        XCTAssertEqual(revealedHome.instrumentationType, .swiftui)
    }

    @available(iOS 27.0, *)
    @MainActor
    func testUnmountedSemanticPresentationReplacement_keepsLastMountedPresentation() throws {
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let handler = createHandler()
        let state = RUMSwiftUISemanticNavigationState<String, SemanticPresentation>()
        let sheet = SemanticPresentation(id: "sheet", name: "Sheet", style: .sheet)
        let cover = SemanticPresentation(
            id: "cover",
            name: "Cover",
            style: .fullScreenCover
        )

        handler.notify_onAppear(
            identity: "home",
            name: "Home",
            path: "/home",
            attributes: [:],
            sceneIdentifier: scene
        )
        state.reconcilePresentation(
            sheet,
            descriptor: semanticDescriptor(for:),
            viewsHandler: handler
        )
        state.mountPresentation(state.presentationOccurrence(for: sheet, style: sheet.style), in: scene, viewsHandler: handler)
        state.reconcilePresentation(
            cover,
            descriptor: semanticDescriptor(for:),
            viewsHandler: handler
        )
        state.reconcilePresentation(
            nil,
            descriptor: semanticDescriptor(for:),
            viewsHandler: handler
        )

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 5)
        let sheetStart = try XCTUnwrap(
            commandSubscriber.receivedCommands[2] as? RUMStartViewCommand
        )
        let sheetStop = try XCTUnwrap(
            commandSubscriber.receivedCommands[3] as? RUMStopViewCommand
        )
        let revealedHome = try XCTUnwrap(
            commandSubscriber.receivedCommands[4] as? RUMStartViewCommand
        )
        XCTAssertEqual(sheetStart.identity, sheetStop.identity)
        XCTAssertEqual(revealedHome.identity, ViewIdentifier("home"))
        XCTAssertFalse(
            commandSubscriber.receivedCommands.contains { command in
                (command as? RUMStartViewCommand)?.name == "Cover"
            }
        )
    }

    @available(iOS 27.0, *)
    @MainActor
    func testPendingSemanticPresentationReplacement_whenContainerCancels_stopsLastMountedPresentation() throws {
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let handler = createHandler()
        let state = RUMSwiftUISemanticNavigationState<String, SemanticPresentation>()
        let sheet = SemanticPresentation(id: "sheet", name: "Sheet", style: .sheet)
        let cover = SemanticPresentation(
            id: "cover",
            name: "Cover",
            style: .fullScreenCover
        )

        state.reconcilePresentation(
            sheet,
            descriptor: semanticDescriptor(for:),
            viewsHandler: handler
        )
        state.mountPresentation(state.presentationOccurrence(for: sheet, style: sheet.style), in: scene, viewsHandler: handler)
        state.reconcilePresentation(
            cover,
            descriptor: semanticDescriptor(for:),
            viewsHandler: handler
        )

        let pendingOccurrence = state.presentationOccurrence(for: cover, style: cover.style)
        XCTAssertNotNil(pendingOccurrence)
        state.cancelPresentations(viewsHandler: handler)
        XCTAssertFalse(state.mountPresentation(pendingOccurrence, in: scene, viewsHandler: handler))

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 2)
        let sheetStart = try XCTUnwrap(
            commandSubscriber.receivedCommands[0] as? RUMStartViewCommand
        )
        let sheetStop = try XCTUnwrap(
            commandSubscriber.receivedCommands[1] as? RUMStopViewCommand
        )
        XCTAssertEqual(sheetStart.identity, sheetStop.identity)
        XCTAssertEqual(sheetStart.name, "Sheet")
        XCTAssertTrue(commandSubscriber.receivedCommands.allSatisfy { $0.target == .scene(scene) })
        XCTAssertNil(state.consumeDismissed(style: .sheet))
        XCTAssertNil(state.consumeDismissed(style: .fullScreenCover))
    }

    @available(iOS 27.0, *)
    @MainActor
    func testMountedSemanticPresentationThatMovesScenes_followsItsActualScene() throws {
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
        let handler = createHandler()
        let state = RUMSwiftUISemanticNavigationState<String, SemanticPresentation>()
        let presentation = SemanticPresentation(
            id: "cover",
            name: "Cover",
            style: .fullScreenCover
        )

        state.reconcilePresentation(
            presentation,
            descriptor: semanticDescriptor(for:),
            viewsHandler: handler
        )
        state.mountPresentation(state.presentationOccurrence(for: presentation, style: presentation.style), in: sceneA, viewsHandler: handler)
        state.mountPresentation(state.presentationOccurrence(for: presentation, style: presentation.style), in: sceneB, viewsHandler: handler)

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)
        let startA = try XCTUnwrap(commandSubscriber.receivedCommands[0] as? RUMStartViewCommand)
        let stopA = try XCTUnwrap(commandSubscriber.receivedCommands[1] as? RUMStopViewCommand)
        let startB = try XCTUnwrap(commandSubscriber.receivedCommands[2] as? RUMStartViewCommand)
        XCTAssertEqual(startA.identity, stopA.identity)
        XCTAssertEqual(startA.identity, startB.identity)
        XCTAssertEqual(startA.target, .scene(sceneA))
        XCTAssertEqual(stopA.target, .scene(sceneA))
        XCTAssertEqual(startB.target, .scene(sceneB))
    }

    @available(iOS 27.0, *)
    @MainActor
    func testSemanticHostSource_commitsFreshOccurrencesAndIgnoresCancellation() throws {
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let handler = createHandler()
        let source = RUMNavigationTransitions(
            currentDestination: rumView(name: "Home", path: "/home")
        )
        let hostState = RUMSemanticNavigationHostState()

        hostState.reconcile(transitions: source, viewsHandler: handler)
        hostState.reconcile(attachment: .attached(scene))

        source.willNavigate(
            id: "cancelled-detail",
            destination: rumView(name: "Detail", path: "/detail")
        )
        source.cancel(id: "cancelled-detail")
        source.commit(id: "cancelled-detail")

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 1)

        source.willNavigate(
            id: "detail",
            destination: rumView(name: "Detail", path: "/detail")
        )
        source.commit(id: "detail")
        source.willNavigate(
            id: "home-return",
            destination: rumView(name: "Home", path: "/home")
        )
        source.commit(id: "home-return")

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 5)
        let home1 = try XCTUnwrap(commandSubscriber.receivedCommands[0] as? RUMStartViewCommand)
        let detail = try XCTUnwrap(commandSubscriber.receivedCommands[2] as? RUMStartViewCommand)
        let home2 = try XCTUnwrap(commandSubscriber.receivedCommands[4] as? RUMStartViewCommand)
        XCTAssertEqual(home1.name, "Home")
        XCTAssertEqual(detail.name, "Detail")
        XCTAssertEqual(home2.name, "Home")
        XCTAssertNotEqual(home1.identity, home2.identity)
        XCTAssertTrue(commandSubscriber.receivedCommands.allSatisfy { $0.target == .scene(scene) })
        XCTAssertEqual(home1.instrumentationType, .manual)
        XCTAssertEqual(detail.instrumentationType, .manual)
        XCTAssertEqual(home2.instrumentationType, .manual)
    }

    @available(iOS 27.0, *)
    @MainActor
    func testSemanticHostSource_updatesBelowManualExceptionUntilItStops() throws {
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let handler = createHandler()
        let source = RUMNavigationTransitions(
            currentDestination: rumView(name: "Home", path: "/home")
        )
        let hostState = RUMSemanticNavigationHostState()

        hostState.reconcile(transitions: source, viewsHandler: handler)
        hostState.reconcile(attachment: .attached(scene))
        handler.startView(
            key: "compose",
            name: "Compose",
            attributes: [:],
            sceneIdentifier: scene
        )

        source.willNavigate(
            id: "detail-below-compose",
            destination: rumView(name: "Detail", path: "/detail")
        )
        source.commit(id: "detail-below-compose")

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)
        XCTAssertFalse(commandSubscriber.receivedCommands.contains { command in
            (command as? RUMStartViewCommand)?.name == "Detail"
        })

        handler.stopView(key: "compose", attributes: [:], sceneIdentifier: scene)

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 5)
        let composeStop = try XCTUnwrap(
            commandSubscriber.receivedCommands[3] as? RUMStopViewCommand
        )
        let revealedDetail = try XCTUnwrap(
            commandSubscriber.receivedCommands[4] as? RUMStartViewCommand
        )
        XCTAssertEqual(composeStop.identity, ViewIdentifier("compose"))
        XCTAssertEqual(revealedDetail.name, "Detail")
        XCTAssertEqual(revealedDetail.target, .scene(scene))
    }

    @available(iOS 27.0, *)
    @MainActor
    func testSemanticHostSources_inDifferentScenesRemainIsolated() throws {
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
        let handler = createHandler()
        let sourceA = RUMNavigationTransitions(
            currentDestination: rumView(name: "Home A", path: "/a")
        )
        let sourceB = RUMNavigationTransitions(
            currentDestination: rumView(name: "Home B", path: "/b")
        )
        let hostA = RUMSemanticNavigationHostState()
        let hostB = RUMSemanticNavigationHostState()

        hostA.reconcile(transitions: sourceA, viewsHandler: handler)
        hostB.reconcile(transitions: sourceB, viewsHandler: handler)
        hostA.reconcile(attachment: .attached(sceneA))
        hostB.reconcile(attachment: .attached(sceneB))
        sourceA.willNavigate(
            id: "detail-a",
            destination: rumView(name: "Detail A", path: "/a/detail")
        )
        sourceA.commit(id: "detail-a")

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 4)
        let startB = try XCTUnwrap(commandSubscriber.receivedCommands[1] as? RUMStartViewCommand)
        XCTAssertEqual(startB.name, "Home B")
        XCTAssertEqual(startB.target, .scene(sceneB))
        XCTAssertFalse(commandSubscriber.receivedCommands.dropFirst(2).contains { command in
            command.target == .scene(sceneB)
        })
    }

    @available(iOS 27.0, *)
    @MainActor
    func testSemanticHostTransientDetachAndReattach_preservesOccurrenceAndSource()
        async throws {
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let handler = createHandler()
        let source = RUMNavigationTransitions(
            currentDestination: rumView(name: "Home", path: "/home")
        )
        let hostState = RUMSemanticNavigationHostState()
        let lifetimeState = RUMSemanticNavigationContainerLifetimeState()

        hostState.reconcile(transitions: source, viewsHandler: handler)
        hostState.reconcile(attachment: .attached(scene))
        hostState.reconcile(attachment: .detached)
        lifetimeState.reconcile(attachment: .detached) {
            hostState.finalDetach()
        }
        hostState.reconcile(attachment: .attached(scene))
        lifetimeState.reconcile(attachment: .attached(scene)) {
            XCTFail("An attachment must not schedule final detach")
        }

        let drained = expectation(description: "queued final detach considered")
        DispatchQueue.main.async { drained.fulfill() }
        await fulfillment(of: [drained], timeout: 1)

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 1)
        XCTAssertTrue(hostState.selectedTransitions === source)
        XCTAssertTrue(hostState.suppressionState.isActive)

        source.willNavigate(
            id: "detail-after-reattach",
            destination: rumView(name: "Detail", path: "/detail")
        )
        source.commit(id: "detail-after-reattach")

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)
        let homeStart = try XCTUnwrap(
            commandSubscriber.receivedCommands[0] as? RUMStartViewCommand
        )
        let homeStop = try XCTUnwrap(
            commandSubscriber.receivedCommands[1] as? RUMStopViewCommand
        )
        let detailStart = try XCTUnwrap(
            commandSubscriber.receivedCommands[2] as? RUMStartViewCommand
        )
        XCTAssertEqual(homeStart.identity, homeStop.identity)
        XCTAssertEqual(detailStart.name, "Detail")
        XCTAssertEqual(detailStart.target, .scene(scene))
    }

    @available(iOS 27.0, *)
    @MainActor
    func testSemanticHostFinalDetach_isolatedBySceneAndUnsubscribesSource() throws {
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
        let handler = createHandler()
        let sourceA = RUMNavigationTransitions(
            currentDestination: rumView(name: "Home A", path: "/a")
        )
        let sourceB = RUMNavigationTransitions(
            currentDestination: rumView(name: "Home B", path: "/b")
        )
        let hostA = RUMSemanticNavigationHostState()
        let hostB = RUMSemanticNavigationHostState()

        hostA.reconcile(transitions: sourceA, viewsHandler: handler)
        hostB.reconcile(transitions: sourceB, viewsHandler: handler)
        hostA.reconcile(attachment: .attached(sceneA))
        hostB.reconcile(attachment: .attached(sceneB))

        hostA.finalDetach()
        sourceA.willNavigate(
            id: "ignored-a",
            destination: rumView(name: "Ignored A", path: "/a/ignored")
        )
        sourceA.commit(id: "ignored-a")
        sourceB.willNavigate(
            id: "detail-b",
            destination: rumView(name: "Detail B", path: "/b/detail")
        )
        sourceB.commit(id: "detail-b")

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 5)
        XCTAssertNil(hostA.selectedTransitions)
        XCTAssertFalse(hostA.suppressionState.isActive)
        XCTAssertTrue(hostB.selectedTransitions === sourceB)
        XCTAssertTrue(hostB.suppressionState.isActive)
        XCTAssertFalse(commandSubscriber.receivedCommands.contains { command in
            (command as? RUMStartViewCommand)?.name == "Ignored A"
        })
        let stopA = try XCTUnwrap(
            commandSubscriber.receivedCommands[2] as? RUMStopViewCommand
        )
        let stopB = try XCTUnwrap(
            commandSubscriber.receivedCommands[3] as? RUMStopViewCommand
        )
        let detailB = try XCTUnwrap(
            commandSubscriber.receivedCommands[4] as? RUMStartViewCommand
        )
        XCTAssertEqual(stopA.target, .scene(sceneA))
        XCTAssertEqual(stopB.target, .scene(sceneB))
        XCTAssertEqual(detailB.target, .scene(sceneB))
        XCTAssertEqual(detailB.name, "Detail B")
    }

    @available(iOS 27.0, *)
    @MainActor
    func testSemanticHostSceneDisconnect_releasesOnlyExactSceneWithoutResurrection()
        throws {
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
        let handler = createHandler(
            sceneIdentifierFromNotification: { notification in
                switch notification.object as? String {
                case "scene-A": sceneA
                case "scene-B": sceneB
                default: nil
                }
            }
        )
        let sourceA = RUMNavigationTransitions(
            currentDestination: rumView(name: "Home A", path: "/a")
        )
        let sourceB = RUMNavigationTransitions(
            currentDestination: rumView(name: "Home B", path: "/b")
        )
        let hostA = RUMSemanticNavigationHostState()
        let hostB = RUMSemanticNavigationHostState()

        hostA.reconcile(transitions: sourceA, viewsHandler: handler)
        hostB.reconcile(transitions: sourceB, viewsHandler: handler)
        hostA.reconcile(attachment: .attached(sceneA))
        hostB.reconcile(attachment: .attached(sceneB))

        notificationCenter.post(
            name: UIScene.didDisconnectNotification,
            object: "scene-A"
        )
        hostA.sceneDidDisconnect(sceneA)
        sourceA.willNavigate(
            id: "ignored-a",
            destination: rumView(name: "Ignored A", path: "/a/ignored")
        )
        sourceA.commit(id: "ignored-a")
        sourceB.willNavigate(
            id: "detail-b",
            destination: rumView(name: "Detail B", path: "/b/detail")
        )
        sourceB.commit(id: "detail-b")

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 5)
        XCTAssertNil(hostA.engine.sceneIdentifier)
        XCTAssertNil(hostA.selectedTransitions)
        XCTAssertFalse(hostA.suppressionState.isActive)
        XCTAssertTrue(hostB.selectedTransitions === sourceB)
        XCTAssertTrue(hostB.suppressionState.isActive)
        XCTAssertFalse(commandSubscriber.receivedCommands.contains { command in
            (command as? RUMStartViewCommand)?.name == "Ignored A"
        })
        let stops = commandSubscriber.receivedCommands.compactMap {
            $0 as? RUMStopViewCommand
        }
        XCTAssertEqual(stops.filter { $0.target == .scene(sceneA) }.count, 1)
        XCTAssertEqual(stops.filter { $0.target == .scene(sceneB) }.count, 1)
        let detailB = try XCTUnwrap(
            commandSubscriber.receivedCommands.last as? RUMStartViewCommand
        )
        XCTAssertEqual(detailB.name, "Detail B")
        XCTAssertEqual(detailB.target, .scene(sceneB))
    }

    @available(iOS 27.0, *)
    @MainActor
    func testSemanticReconnectRejectedReaderDoesNotConsumeGeneration() throws {
        try assertSemanticReconnect(earlyReader: true, advanceSource: false)
    }

    @available(iOS 27.0, *)
    @MainActor
    func testSemanticReconnectPublishesLatestInputOnceAfterRejection() throws {
        try assertSemanticReconnect(earlyReader: true, advanceSource: true)
    }

    @available(iOS 27.0, *)
    @MainActor
    func testSemanticReconnectWithoutStaleCallbackUsesFreshIdentity() throws {
        try assertSemanticReconnect(earlyReader: false, advanceSource: false)
    }

    @available(iOS 27.0, *)
    @MainActor
    func testSemanticReconnectIgnoresInheritedTraitUntilLiveReaderMount() throws {
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let handler = createHandler(sceneIdentifierFromNotification: { _ in scene })
        let source = RUMNavigationTransitions(currentDestination: RUMView(name: "Home"))
        let host = RUMSemanticNavigationHostState()
        host.reconcile(transitions: source, viewsHandler: handler)
        host.reconcile(initialSceneIdentifier: scene)
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 1, "First trait must retain early attribution")
        for _ in 0..<3 {
            notificationCenter.post(name: UIScene.didDisconnectNotification, object: nil)
            host.sceneDidDisconnect(scene)
            let disconnectedCount = commandSubscriber.receivedCommands.count
            host.reconcile(transitions: source, viewsHandler: handler)
            host.reconcile(initialSceneIdentifier: scene)
            XCTAssertNil(host.engine.sceneIdentifier)
            XCTAssertFalse(host.suppressionState.isActive)
            notificationCenter.post(name: UIScene.willConnectNotification, object: nil)
            notificationCenter.post(name: UIScene.willEnterForegroundNotification, object: nil)
            host.reconcile(initialSceneIdentifier: scene)
            host.reconcile(transitions: source, viewsHandler: handler)
            XCTAssertNil(host.engine.sceneIdentifier)
            XCTAssertFalse(host.suppressionState.isActive)
            XCTAssertEqual(commandSubscriber.receivedCommands.count, disconnectedCount)
            host.reconcile(attachment: .attached(scene))
            host.reconcile(initialSceneIdentifier: scene)
            host.reconcile(attachment: .attached(scene))
            XCTAssertTrue(host.suppressionState.isActive)
            XCTAssertEqual(commandSubscriber.receivedCommands.count, disconnectedCount + 1)
        }
        let starts = commandSubscriber.receivedCommands.compactMap { $0 as? RUMStartViewCommand }
        XCTAssertEqual(starts.count, 4)
        for (index, start) in starts.enumerated() {
            XCTAssertFalse(starts.prefix(index).contains { $0.identity == start.identity })
        }
    }

    @available(iOS 27.0, *)
    @MainActor
    func testSemanticFinalDetachRequiresReaderAndAcceptsLateInputAndHandler() throws {
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let handler = createHandler()
        let host = RUMSemanticNavigationHostState()
        let oldSource = RUMNavigationTransitions(currentDestination: RUMView(name: "Old"))
        host.reconcile(transitions: oldSource, viewsHandler: handler)
        host.reconcile(initialSceneIdentifier: scene)
        host.finalDetach()
        let newSource = RUMNavigationTransitions()
        host.reconcile(transitions: newSource, viewsHandler: nil)
        host.reconcile(initialSceneIdentifier: scene)
        XCTAssertNil(host.engine.sceneIdentifier)
        XCTAssertFalse(host.suppressionState.isActive)
        host.reconcile(attachment: .attached(scene))
        newSource.setInitialDestination(RUMView(name: "New"))
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 2)
        XCTAssertFalse(host.suppressionState.isActive)
        host.reconcile(transitions: newSource, viewsHandler: handler)
        let restored = try XCTUnwrap(commandSubscriber.receivedCommands.last as? RUMStartViewCommand)
        XCTAssertEqual(restored.name, "New")
        XCTAssertEqual(restored.target, .scene(scene))
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)
        host.reconcile(attachment: .attached(scene))
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)
    }

    @available(iOS 27.0, *)
    @MainActor
    func testSemanticPublicationReportsRejectionAndInactiveAcceptance() {
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let handler = createHandler(sceneIdentifierFromNotification: { _ in scene })
        notificationCenter.post(name: UIScene.didDisconnectNotification, object: nil)
        XCTAssertFalse(handler.notify_semanticDestinationAppear(
            identity: "rejected", name: "Rejected", path: "/rejected", attributes: [:], sceneIdentifier: scene
        ))
        notificationCenter.post(name: UIScene.willConnectNotification, object: nil)
        XCTAssertTrue(handler.notify_semanticDestinationAppear(
            identity: "staged", name: "Staged", path: "/staged", attributes: [:], sceneIdentifier: scene
        ))
        XCTAssertTrue(commandSubscriber.receivedCommands.isEmpty)
        notificationCenter.post(name: UIScene.willEnterForegroundNotification, object: nil)
        let starts = commandSubscriber.receivedCommands.compactMap { $0 as? RUMStartViewCommand }
        XCTAssertEqual(starts.map(\.name), ["Staged"])
        XCTAssertEqual(starts.first?.target, .scene(scene))
    }

    @available(iOS 27.0, *)
    @MainActor
    func testRejectedSemanticReplacementPreservesAcceptedScene() throws {
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
        let handler = createHandler(sceneIdentifierFromNotification: { _ in sceneB })
        XCTAssertTrue(handler.notify_semanticDestinationAppear(
            identity: "accepted", name: "Accepted", path: "/a", attributes: [:], sceneIdentifier: sceneA
        ))
        notificationCenter.post(name: UIScene.didDisconnectNotification, object: nil)
        XCTAssertFalse(handler.notify_semanticDestinationReplace(
            identity: "accepted",
            sceneIdentifier: sceneA,
            replacementIdentity: "rejected",
            replacementName: "Rejected",
            replacementPath: "/b",
            replacementAttributes: [:],
            replacementSceneIdentifier: sceneB
        ))
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 1)
        handler.notify_semanticDestinationDisappear(identity: "accepted", sceneIdentifier: sceneA)
        let stop = try XCTUnwrap(commandSubscriber.receivedCommands.last as? RUMStopViewCommand)
        XCTAssertEqual(stop.identity, ViewIdentifier("accepted"))
        XCTAssertEqual(stop.target, .scene(sceneA))
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 2)
    }

    @available(iOS 27.0, *)
    @MainActor
    func testRetainedSemanticReaderRemountsAfterFinalDetachWithoutBody() throws {
        try assertRetainedSemanticReader(disconnect: false)
    }

    @available(iOS 27.0, *)
    @MainActor
    func testRetainedSemanticReaderRemountsAfterSceneReconnectWithoutBody() throws {
        try assertRetainedSemanticReader(disconnect: true)
    }

    @available(iOS 27.0, *)
    @MainActor
    func testRetainedSemanticConfigurationDoesNotKeepSourceOrHandlerAlive() {
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let host = RUMSemanticNavigationHostState()
        weak var releasedSource: RUMNavigationTransitions?
        weak var releasedHandler: RUMViewsHandler?
        autoreleasepool {
            let source = RUMNavigationTransitions(currentDestination: RUMView(name: "Initial"))
            let handler = createHandler()
            releasedSource = source
            releasedHandler = handler
            host.reconcile(transitions: source, viewsHandler: handler)
            host.reconcile(attachment: .attached(scene))
            host.finalDetach()
        }
        XCTAssertNil(releasedSource)
        XCTAssertNil(releasedHandler)
        host.reconcile(attachment: .attached(scene))
        XCTAssertNil(host.selectedTransitions)
        XCTAssertFalse(host.suppressionState.isActive)
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 2)
    }

    @available(iOS 27.0, *)
    @MainActor
    func testRetainedSemanticReaderDoesNotRestoreWithdrawnSource() {
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let handler = createHandler()
        let source = RUMNavigationTransitions(currentDestination: RUMView(name: "Initial"))
        let host = RUMSemanticNavigationHostState()
        host.reconcile(transitions: source, viewsHandler: handler)
        host.reconcile(attachment: .attached(scene))
        host.finalDetach()
        host.reconcile(transitions: nil, viewsHandler: handler)
        host.reconcile(attachment: .attached(scene))
        source.willNavigate(id: "withdrawn", destination: RUMView(name: "Withdrawn"))
        source.commit(id: "withdrawn")
        XCTAssertNil(host.selectedTransitions)
        XCTAssertFalse(host.suppressionState.isActive)
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 2)
    }

    @available(iOS 27.0, *)
    @MainActor
    private func assertRetainedSemanticReader(disconnect: Bool) throws {
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
        let handler = createHandler(sceneIdentifierFromNotification: { _ in sceneA })
        let source = RUMNavigationTransitions(currentDestination: RUMView(name: "Initial"))
        let host = RUMSemanticNavigationHostState()
        host.reconcile(transitions: source, viewsHandler: handler)
        let reader = RUMSceneIdentifierReader.ObserverView(
            onChange: host.reconcile(attachment:),
            onMount: { host.reconcile(attachment: .attached($0)) },
            applicationSupportsMultipleScenes: true
        )
        reader.notify(attachment: .attached(sceneA))
        let initial = try XCTUnwrap(commandSubscriber.receivedCommands.first as? RUMStartViewCommand)
        handler.notify_semanticDestinationAppear(
            identity: "peer", name: "Peer", path: "/peer", attributes: [:], sceneIdentifier: sceneB
        )
        if disconnect {
            notificationCenter.post(name: UIScene.didDisconnectNotification, object: nil)
            host.sceneDidDisconnect(sceneA)
            reader.markSceneDisconnected(sceneA)
        } else {
            reader.notify(attachment: .detached)
            host.finalDetach()
        }
        XCTAssertNil(host.selectedTransitions)
        XCTAssertFalse(host.suppressionState.isActive)
        source.willNavigate(id: "latest", destination: RUMView(name: "Latest"))
        source.commit(id: "latest")
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)
        if disconnect {
            reader.notify(attachment: .attached(sceneA))
            XCTAssertFalse(host.suppressionState.isActive)
            XCTAssertNil(host.selectedTransitions)
            notificationCenter.post(name: UIScene.willConnectNotification, object: nil)
            notificationCenter.post(name: UIScene.willEnterForegroundNotification, object: nil)
            reader.markSceneDisconnected(sceneA)
        }
        // Existing callbacks only: no body/source reconciliation repairs this boundary.
        reader.notify(attachment: .attached(sceneA))
        reader.notify(attachment: .attached(sceneA))
        let starts = commandSubscriber.receivedCommands.compactMap { $0 as? RUMStartViewCommand }
        XCTAssertEqual(starts.filter { $0.target == .scene(sceneA) }.count, 2)
        let restored = try XCTUnwrap(starts.last { $0.target == .scene(sceneA) })
        XCTAssertEqual(restored.name, "Latest")
        XCTAssertNotEqual(restored.identity, initial.identity)
        XCTAssertTrue(host.selectedTransitions === source)
        XCTAssertTrue(host.suppressionState.isActive)
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 4)
        host.finalDetach()
        let stops = commandSubscriber.receivedCommands.compactMap { $0 as? RUMStopViewCommand }
        XCTAssertEqual(stops.filter { $0.target == .scene(sceneA) }.map(\.identity), [initial.identity, restored.identity])
        XCTAssertFalse(stops.contains { $0.target == .scene(sceneB) })
    }

    @available(iOS 27.0, *)
    @MainActor
    private func assertSemanticReconnect(earlyReader: Bool, advanceSource: Bool) throws {
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
        let handler = createHandler(sceneIdentifierFromNotification: { notification in
            notification.object as? String == "scene-A" ? sceneA : nil
        })
        let source = RUMNavigationTransitions(currentDestination: RUMView(name: "Home"))
        let host = RUMSemanticNavigationHostState()
        host.reconcile(transitions: source, viewsHandler: handler)
        host.reconcile(attachment: .attached(sceneA))
        let initial = try XCTUnwrap(commandSubscriber.receivedCommands.first as? RUMStartViewCommand)
        handler.notify_semanticDestinationAppear(
            identity: "peer", name: "Peer", path: "/peer", attributes: [:], sceneIdentifier: sceneB
        )
        notificationCenter.post(name: UIScene.didDisconnectNotification, object: "scene-A")
        host.sceneDidDisconnect(sceneA)
        host.reconcile(transitions: source, viewsHandler: handler)
        if earlyReader { host.reconcile(attachment: .attached(sceneA)) }
        XCTAssertFalse(host.suppressionState.isActive)
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)
        if advanceSource {
            source.willNavigate(id: "latest", destination: RUMView(name: "Latest"))
            source.commit(id: "latest")
            XCTAssertFalse(host.suppressionState.isActive)
            XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)
        }
        notificationCenter.post(name: UIScene.willConnectNotification, object: "scene-A")
        notificationCenter.post(name: UIScene.willEnterForegroundNotification, object: "scene-A")
        host.reconcile(attachment: .attached(sceneA))
        host.reconcile(attachment: .attached(sceneA))
        host.reconcile(transitions: source, viewsHandler: handler)
        let starts = commandSubscriber.receivedCommands.compactMap { $0 as? RUMStartViewCommand }
        let restored = try XCTUnwrap(starts.last { $0.target == .scene(sceneA) })
        XCTAssertEqual(starts.filter { $0.target == .scene(sceneA) }.count, 2)
        XCTAssertNotEqual(restored.identity, initial.identity)
        XCTAssertEqual(restored.name, advanceSource ? "Latest" : "Home")
        XCTAssertTrue(host.suppressionState.isActive)
        XCTAssertEqual(starts.filter { $0.target == .scene(sceneB) }.count, 1)
        host.finalDetach()
        let stops = commandSubscriber.receivedCommands.compactMap { $0 as? RUMStopViewCommand }
        XCTAssertEqual(stops.filter { $0.target == .scene(sceneA) }.map(\.identity), [initial.identity, restored.identity])
        XCTAssertFalse(stops.contains { $0.target == .scene(sceneB) })
        XCTAssertFalse(host.suppressionState.isActive)
    }

    @available(iOS 27.0, *)
    @MainActor
    func testObservedNavigationMetadata_usesSafeAutomaticCaseNamesAndSparseOverrides() {
        let thread = RUMNavigationDestination.route(
            ObservedNavigationRoute.thread(42)
        )
        let automatic = RUMNavigationMetadata.automatic(in: "messages")
        let threadView = automatic.view(for: thread)

        XCTAssertEqual(thread.automaticKey, "thread")
        XCTAssertEqual(threadView.name, "Thread")
        XCTAssertEqual(threadView.path, "/messages/thread")
        XCTAssertFalse(threadView.name.contains("42"))
        XCTAssertFalse(threadView.name.contains("customer-secret"))

        let preferences = RUMNavigationDestination.route(
            ObservedNavigationRoute.preferences
        )
        let overridden = RUMNavigationMetadata
            .automatic(in: "settings")
            .overriding(
                ObservedNavigationRoute.preferences,
                name: "Account preferences"
            )
            .view(for: preferences)

        XCTAssertEqual(overridden.name, "Account preferences")
        XCTAssertEqual(overridden.path, "/settings/preferences")
    }

    @available(iOS 27.0, *)
    @MainActor
    func testObservedNavigationTransitions_emitsInitialAndFreshReturnedOccurrences() throws {
        let initial = ObservedNavigationState(
            root: .messages,
            marker: "initial"
        )
        let updates = CurrentValueSubject<ObservedNavigationState, Never>(initial)
        let adapter = RUMNavigationObservedTransitions(
            updates: updates,
            destination: { state in
                if let presentation = state.presentation {
                    return .presentation(presentation)
                }
                if let route = state.route {
                    return .route(route)
                }
                return .root(state.root)
            },
            metadata: .automatic(in: "messages")
        )
        let transitions = try XCTUnwrap(adapter.transitions)
        var snapshots: [RUMNavigationTransitions.Snapshot] = []
        let observationID = transitions.observe { snapshots.append($0) }
        defer { transitions.removeObserver(observationID) }

        updates.send(
            ObservedNavigationState(root: .messages, marker: "same destination")
        )
        updates.send(
            ObservedNavigationState(
                root: .messages,
                route: .thread(42),
                marker: "thread"
            )
        )
        updates.send(
            ObservedNavigationState(root: .messages, marker: "returned root")
        )

        XCTAssertEqual(snapshots.map(\.generation), [0, 1, 2])
        XCTAssertEqual(snapshots.map(\.destination.name), ["Messages", "Thread", "Messages"])
        XCTAssertEqual(
            snapshots.map(\.destination.path),
            ["/messages", "/messages/thread", "/messages"]
        )
    }

    @available(iOS 27.0, *)
    @MainActor
    func testObservedNavigationTransitions_emitsFreshEqualRouteOccurrences() throws {
        let initial = ObservedNavigationState(
            root: .messages,
            route: .thread(42),
            routeDepth: 1,
            marker: "first route"
        )
        let updates = CurrentValueSubject<ObservedNavigationState, Never>(initial)
        let adapter = RUMNavigationObservedTransitions(
            updates: updates,
            destination: { state in
                guard let route = state.route else {
                    return .root(state.root)
                }
                return .route(route, occurrence: state.routeDepth)
            },
            metadata: .automatic(in: "messages")
        )
        let transitions = try XCTUnwrap(adapter.transitions)
        var snapshots: [RUMNavigationTransitions.Snapshot] = []
        let observationID = transitions.observe { snapshots.append($0) }
        defer { transitions.removeObserver(observationID) }

        updates.send(
            ObservedNavigationState(
                root: .messages,
                route: .thread(42),
                routeDepth: 2,
                marker: "equal route pushed"
            )
        )
        updates.send(
            ObservedNavigationState(
                root: .messages,
                route: .thread(42),
                routeDepth: 1,
                marker: "equal route revealed"
            )
        )

        XCTAssertEqual(snapshots.map(\.generation), [0, 1, 2])
        XCTAssertEqual(
            snapshots.map(\.destination.name),
            ["Thread", "Thread", "Thread"]
        )
    }

    @available(iOS 27.0, *)
    @MainActor
    func testObservedNavigationTransitions_waitsForInitialDestinationBeforeAuthority() {
        let updates = PassthroughSubject<ObservedNavigationState, Never>()
        let adapter = RUMNavigationObservedTransitions(
            updates: updates,
            destination: { .root($0.root) },
            metadata: .automatic(in: "messages")
        )

        XCTAssertNil(adapter.transitions)

        updates.send(
            ObservedNavigationState(root: .messages, marker: "accepted root")
        )

        XCTAssertNotNil(adapter.transitions)
    }

    @available(iOS 27.0, *)
    @MainActor
    func testObservedNavigationTransitions_preservesBackgroundEmissionOrder() async throws {
        let updates = CurrentValueSubject<ObservedNavigationState, Never>(
            ObservedNavigationState(root: .messages, marker: "initial")
        )
        let adapter = RUMNavigationObservedTransitions(
            updates: updates,
            destination: { state in
                if let route = state.route {
                    return .route(route)
                }
                return .root(state.root)
            },
            metadata: .automatic(in: "messages")
        )
        let transitions = try XCTUnwrap(adapter.transitions)
        var snapshots: [RUMNavigationTransitions.Snapshot] = []
        let observationID = transitions.observe { snapshots.append($0) }
        defer { transitions.removeObserver(observationID) }
        let delivered = expectation(description: "background emissions delivered")

        DispatchQueue(label: "rum-navigation-observed-transitions-test").async {
            updates.send(
                ObservedNavigationState(
                    root: .messages,
                    route: .thread(1),
                    marker: "thread"
                )
            )
            updates.send(
                ObservedNavigationState(
                    root: .messages,
                    route: .preferences,
                    marker: "preferences"
                )
            )
            updates.send(
                ObservedNavigationState(root: .messages, marker: "returned root")
            )
            DispatchQueue.main.async {
                delivered.fulfill()
            }
        }

        await fulfillment(of: [delivered], timeout: 1)

        XCTAssertEqual(snapshots.map(\.generation), [0, 1, 2, 3])
        XCTAssertEqual(
            snapshots.map(\.destination.name),
            ["Messages", "Thread", "Preferences", "Messages"]
        )
    }

    @available(iOS 27.0, *)
    @MainActor
    func testObservedNavigationTransitions_ignoresHiddenStateWhilePresentationRemainsCurrent()
        throws {
        let updates = CurrentValueSubject<ObservedNavigationState, Never>(
            ObservedNavigationState(
                root: .messages,
                route: .thread(1),
                presentation: .compose(7),
                marker: "presented"
            )
        )
        let adapter = RUMNavigationObservedTransitions(
            updates: updates,
            destination: { state in
                if let presentation = state.presentation {
                    return .presentation(presentation)
                }
                if let route = state.route {
                    return .route(route)
                }
                return .root(state.root)
            },
            metadata: .automatic(in: "messages")
        )
        let transitions = try XCTUnwrap(adapter.transitions)
        var snapshots: [RUMNavigationTransitions.Snapshot] = []
        let observationID = transitions.observe { snapshots.append($0) }
        defer { transitions.removeObserver(observationID) }

        updates.send(
            ObservedNavigationState(
                root: .messages,
                route: .preferences,
                presentation: .compose(7),
                marker: "hidden route changed"
            )
        )
        updates.send(
            ObservedNavigationState(
                root: .messages,
                route: .preferences,
                marker: "dismissed"
            )
        )

        XCTAssertEqual(snapshots.map(\.generation), [0, 1])
        XCTAssertEqual(snapshots.map(\.destination.name), ["Compose", "Preferences"])
    }

    @available(iOS 27.0, *)
    @MainActor
    func testObservedNavigationHosts_areIsolatedBySceneAndDisconnectExactSource()
        throws {
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
        let handler = createHandler(
            sceneIdentifierFromNotification: { notification in
                switch notification.object as? String {
                case "scene-A": sceneA
                case "scene-B": sceneB
                default: nil
                }
            }
        )
        let updatesA = CurrentValueSubject<ObservedNavigationState, Never>(
            ObservedNavigationState(root: .messages, marker: "initial-a")
        )
        let updatesB = CurrentValueSubject<ObservedNavigationState, Never>(
            ObservedNavigationState(root: .settings, marker: "initial-b")
        )
        let adapterA = RUMNavigationObservedTransitions(
            updates: updatesA,
            destination: { state in
                if let route = state.route {
                    return .route(route)
                }
                return .root(state.root)
            },
            metadata: .automatic(in: "scene-a")
        )
        let adapterB = RUMNavigationObservedTransitions(
            updates: updatesB,
            destination: { state in
                if let route = state.route {
                    return .route(route)
                }
                return .root(state.root)
            },
            metadata: .automatic(in: "scene-b")
        )
        let transitionsA = try XCTUnwrap(adapterA.transitions)
        let transitionsB = try XCTUnwrap(adapterB.transitions)
        let hostA = RUMSemanticNavigationHostState()
        let hostB = RUMSemanticNavigationHostState()

        hostA.reconcile(transitions: transitionsA, viewsHandler: handler)
        hostB.reconcile(transitions: transitionsB, viewsHandler: handler)
        hostA.reconcile(attachment: .attached(sceneA))
        hostB.reconcile(attachment: .attached(sceneB))

        notificationCenter.post(
            name: UIScene.didDisconnectNotification,
            object: "scene-A"
        )
        hostA.sceneDidDisconnect(sceneA)
        updatesA.send(
            ObservedNavigationState(
                root: .messages,
                route: .thread(42),
                marker: "ignored-a"
            )
        )
        updatesB.send(
            ObservedNavigationState(
                root: .settings,
                route: .preferences,
                marker: "accepted-b"
            )
        )

        XCTAssertEqual(commandSubscriber.receivedCommands.count, 5)
        XCTAssertNil(hostA.engine.sceneIdentifier)
        XCTAssertNil(hostA.selectedTransitions)
        XCTAssertFalse(hostA.suppressionState.isActive)
        XCTAssertTrue(hostB.selectedTransitions === transitionsB)
        XCTAssertTrue(hostB.suppressionState.isActive)
        XCTAssertFalse(commandSubscriber.receivedCommands.contains { command in
            (command as? RUMStartViewCommand)?.name == "Thread"
        })
        let starts = commandSubscriber.receivedCommands.compactMap {
            $0 as? RUMStartViewCommand
        }
        XCTAssertEqual(starts.map(\.name), ["Messages", "Settings", "Preferences"])
        XCTAssertEqual(
            starts.map(\.target),
            [.scene(sceneA), .scene(sceneB), .scene(sceneB)]
        )
        let stops = commandSubscriber.receivedCommands.compactMap {
            $0 as? RUMStopViewCommand
        }
        XCTAssertEqual(stops.filter { $0.target == .scene(sceneA) }.count, 1)
        XCTAssertEqual(stops.filter { $0.target == .scene(sceneB) }.count, 1)
    }

    @available(iOS 27.0, *)
    @MainActor
    private func rumView(name: String, path: String) -> RUMView {
        var view = RUMView(name: name)
        view.path = path
        return view
    }
    #endif
}
