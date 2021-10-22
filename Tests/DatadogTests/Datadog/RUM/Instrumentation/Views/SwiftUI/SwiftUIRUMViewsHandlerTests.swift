/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class SwiftUIRUMViewsHandlerTests: XCTestCase {
    private let dateProvider = RelativeDateProvider(using: .mockDecember15th2019At10AMUTC())
    private let commandSubscriber = RUMCommandSubscriberMock()
    private let notificationCenter = NotificationCenter()

    private lazy var handler: SwiftUIRUMViewsHandler = {
        let handler = SwiftUIRUMViewsHandler(
            dateProvider: dateProvider,
            notificationCenter: notificationCenter
        )
        handler.publish(to: commandSubscriber)
        return handler
    }()

    // MARK: - Handling `.onAppear`

    func testWhenOnAppear_itStartsRUMView() throws {
        // Given
        let viewKey: String = UUID().uuidString
        let viewName: String = .mockRandom()
        let viewPath: String = .mockRandom()
        let viewAttributes = mockRandomAttributes()

        // When
        handler.onAppear(
            identity: viewKey,
            name: viewName,
            path: viewPath,
            attributes: viewAttributes
        )

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 1)

        let command = try XCTUnwrap(commandSubscriber.receivedCommands[0] as? RUMStartViewCommand)
        XCTAssertEqual(command.time, .mockDecember15th2019At10AMUTC())
        XCTAssertTrue(command.identity.equals(viewKey))
        XCTAssertEqual(command.name, viewName)
        XCTAssertEqual(command.path, viewPath)
        AssertDictionariesEqual(command.attributes, viewAttributes)
    }

    func testWhenOnAppear_itStopsPreviousRUMView() throws {
        // Given
        let view1Key: String = UUID().uuidString
        let view1Name: String = .mockRandom()
        let view1Path: String = .mockRandom()
        let view1Attributes = mockRandomAttributes()

        let view2Key: String = UUID().uuidString
        let view2Name: String = .mockRandom()
        let view2Path: String = .mockRandom()
        let view2Attributes = mockRandomAttributes()

        // When
        handler.onAppear(
            identity: view1Key,
            name: view1Name,
            path: view1Path,
            attributes: view1Attributes
        )

        handler.onAppear(
            identity: view2Key,
            name: view2Name,
            path: view2Path,
            attributes: view2Attributes
        )

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)

        let startCommand1 = try XCTUnwrap(commandSubscriber.receivedCommands[0] as? RUMStartViewCommand)
        let stopCommand = try XCTUnwrap(commandSubscriber.receivedCommands[1] as? RUMStopViewCommand)
        let startCommand2 = try XCTUnwrap(commandSubscriber.receivedCommands[2] as? RUMStartViewCommand)

        XCTAssertTrue(startCommand1.identity.equals(view1Key))
        AssertDictionariesEqual(startCommand1.attributes, view1Attributes)
        XCTAssertTrue(stopCommand.identity.equals(view1Key))
        XCTAssertEqual(stopCommand.attributes.count, 0)
        XCTAssertTrue(startCommand2.identity.equals(view2Key))
        AssertDictionariesEqual(startCommand2.attributes, view2Attributes)
    }

    func testWhenOnAppear_itDoesNotStartTheSameRUMViewTwice() throws {
        // Given
        let viewKey: String = UUID().uuidString
        let viewName: String = .mockRandom()
        let viewPath: String = .mockRandom()
        let viewAttributes = mockRandomAttributes()

        // When
        handler.onAppear(
            identity: viewKey,
            name: viewName,
            path: viewPath,
            attributes: viewAttributes
        )

        handler.onAppear(
            identity: viewKey,
            name: viewName,
            path: viewPath,
            attributes: viewAttributes
        )

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 1)
        XCTAssertTrue(commandSubscriber.receivedCommands[0] is RUMStartViewCommand)
    }

    // MARK: - Handling `onDisappear`

    func testWhenOnDisappear_itDoesNotSendAnyCommand() {
        // Given
        let viewKey: String = UUID().uuidString

        // When
        handler.onDisappear(identity: viewKey)

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 0)
    }

    func testGivenAppearedView_whenOnDisappear_itSopsTheRUMView() throws {
        // Given
        let viewKey: String = UUID().uuidString
        let viewName: String = .mockRandom()
        let viewPath: String = .mockRandom()
        let viewAttributes = mockRandomAttributes()

        // When
        handler.onAppear(
            identity: viewKey,
            name: viewName,
            path: viewPath,
            attributes: viewAttributes
        )

        handler.onDisappear(identity: viewKey)

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 2)

        let startCommand = try XCTUnwrap(commandSubscriber.receivedCommands[0] as? RUMStartViewCommand)
        let stopCommand = try XCTUnwrap(commandSubscriber.receivedCommands[1] as? RUMStopViewCommand)

        XCTAssertTrue(startCommand.identity.equals(viewKey))
        AssertDictionariesEqual(startCommand.attributes, viewAttributes)
        XCTAssertTrue(stopCommand.identity.equals(viewKey))
        XCTAssertEqual(stopCommand.attributes.count, 0)
    }

    func testGiven2AppearedView_whenTheFirstDisappears_itDoesNotStopItTwice() throws {
        // Given
        let view1Key: String = UUID().uuidString
        let view1Name: String = .mockRandom()
        let view1Path: String = .mockRandom()
        let view1Attributes = mockRandomAttributes()

        let view2Key: String = UUID().uuidString
        let view2Name: String = .mockRandom()
        let view2Path: String = .mockRandom()
        let view2Attributes = mockRandomAttributes()

        // When
        handler.onAppear(
            identity: view1Key,
            name: view1Name,
            path: view1Path,
            attributes: view1Attributes
        )

        handler.onAppear(
            identity: view2Key,
            name: view2Name,
            path: view2Path,
            attributes: view2Attributes
        )

        handler.onDisappear(identity: view1Key)

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 3)

        let startCommand1 = try XCTUnwrap(commandSubscriber.receivedCommands[0] as? RUMStartViewCommand)
        let stopCommand1 = try XCTUnwrap(commandSubscriber.receivedCommands[1] as? RUMStopViewCommand)
        let startCommand2 = try XCTUnwrap(commandSubscriber.receivedCommands[2] as? RUMStartViewCommand)

        XCTAssertTrue(startCommand1.identity.equals(view1Key))
        AssertDictionariesEqual(startCommand1.attributes, view1Attributes)
        XCTAssertTrue(stopCommand1.identity.equals(view1Key))
        XCTAssertTrue(startCommand2.identity.equals(view2Key))
        AssertDictionariesEqual(startCommand2.attributes, view2Attributes)
    }

    func testGiven2AppearedView_whenTheLastDisappears_itRestartsThePreviousRUMView() throws {
        // Given
        let view1Key: String = UUID().uuidString
        let view1Name: String = .mockRandom()
        let view1Path: String = .mockRandom()
        let view1Attributes = mockRandomAttributes()

        let view2Key: String = UUID().uuidString
        let view2Name: String = .mockRandom()
        let view2Path: String = .mockRandom()
        let view2Attributes = mockRandomAttributes()

        // When
        handler.onAppear(
            identity: view1Key,
            name: view1Name,
            path: view1Path,
            attributes: view1Attributes
        )

        handler.onAppear(
            identity: view2Key,
            name: view2Name,
            path: view2Path,
            attributes: view2Attributes
        )

        handler.onDisappear(identity: view2Key)

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 5)

        let startCommand1 = try XCTUnwrap(commandSubscriber.receivedCommands[0] as? RUMStartViewCommand)
        let stopCommand1 = try XCTUnwrap(commandSubscriber.receivedCommands[1] as? RUMStopViewCommand)
        let startCommand2 = try XCTUnwrap(commandSubscriber.receivedCommands[2] as? RUMStartViewCommand)
        let stopCommand2 = try XCTUnwrap(commandSubscriber.receivedCommands[3] as? RUMStopViewCommand)
        let startCommand3 = try XCTUnwrap(commandSubscriber.receivedCommands[4] as? RUMStartViewCommand)

        XCTAssertTrue(startCommand1.identity.equals(view1Key))
        AssertDictionariesEqual(startCommand1.attributes, view1Attributes)
        XCTAssertTrue(stopCommand1.identity.equals(view1Key))
        XCTAssertTrue(startCommand2.identity.equals(view2Key))
        AssertDictionariesEqual(startCommand2.attributes, view2Attributes)
        XCTAssertTrue(stopCommand2.identity.equals(view2Key))
        XCTAssertTrue(startCommand3.identity.equals(view1Key))
        AssertDictionariesEqual(startCommand1.attributes, view1Attributes)
    }

    // MARK: - Handling Application Activity

    func testGivenRUMViewStarted_whenAppStateChanges_itStopsAndRestartsRUMView() throws {
        // Given
        let viewKey: String = UUID().uuidString
        let viewName: String = .mockRandom()
        let viewPath: String = .mockRandom()
        let viewAttributes = mockRandomAttributes()

        // When
        handler.onAppear(
            identity: viewKey,
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
        XCTAssertTrue(stopCommand.identity.equals(viewKey))
        XCTAssertEqual(stopCommand.attributes.count, 0)
        XCTAssertEqual(stopCommand.time, .mockDecember15th2019At10AMUTC())
        XCTAssertTrue(startCommand.identity.equals(viewKey))
        XCTAssertEqual(startCommand.path, viewPath)
        XCTAssertEqual(startCommand.name, viewName)
        AssertDictionariesEqual(startCommand.attributes, viewAttributes)
        XCTAssertEqual(startCommand.time, .mockDecember15th2019At10AMUTC() + 1)
    }

    func testGivenRUMViewDidNotStart_whenAppStateChanges_itDoesNothing() throws {
        // Given
        let viewKey: String = UUID().uuidString

        // When
        handler.onDisappear(identity: viewKey)

        notificationCenter.post(name: UIApplication.willResignActiveNotification, object: nil)
        dateProvider.advance(bySeconds: 1)
        notificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, 0)
    }
}
