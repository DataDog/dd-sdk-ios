/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class UIKitRUMViewsHandlerTests: XCTestCase {
    private let dateProvider = RelativeDateProvider(using: .mockDecember15th2019At10AMUTC())
    private let commandSubscriber = RUMCommandSubscriberMock()
    private let predicate = UIKitRUMViewsPredicateMock()

    private lazy var handler: UIKitRUMViewsHandler = {
        let handler = UIKitRUMViewsHandler(predicate: predicate, dateProvider: dateProvider)
        handler.subscribe(commandsSubscriber: commandSubscriber)
        return handler
    }()

    func testGivenAcceptingPredicate_whenViewWillAppear_itSendsRUMStartViewCommand() {
        // Given
        predicate.result = .init(name: "Foo", attributes: ["foo": "bar"])

        // When
        handler.notify_viewWillAppear(viewController: mockView, animated: .mockAny())

        // Then
        let command = commandSubscriber.receivedCommand as? RUMStartViewCommand
        XCTAssertTrue(command?.identity === mockView)
        XCTAssertEqual(command?.path, "Foo")
        XCTAssertEqual(command?.attributes as? [String: String], ["foo": "bar"])
        XCTAssertEqual(command?.time, .mockDecember15th2019At10AMUTC())
    }

    func testGivenRejectingPredicate_whenViewWillAppear_itSendsRUMStartViewCommand() {
        // Given
        predicate.result = nil

        // When
        handler.notify_viewWillAppear(viewController: mockView, animated: .mockAny())

        // Then
        XCTAssertNil(commandSubscriber.receivedCommand)
    }

    func testGivenAcceptingPredicate_whenViewWillDisappear_itSendsRUMStopViewCommand() {
        // Given
        predicate.result = .init(name: "Foo", attributes: ["foo": "bar"])

        // When
        handler.notify_viewWillDisappear(viewController: mockView, animated: .mockAny())

        // Then
        let command = commandSubscriber.receivedCommand as? RUMStopViewCommand
        XCTAssertTrue(command?.identity === mockView)
        XCTAssertEqual(command?.attributes as? [String: String], ["foo": "bar"])
        XCTAssertEqual(command?.time, .mockDecember15th2019At10AMUTC())
    }

    func testGivenRejectingPredicate_whenViewWillDisappear_itSendsRUMStopViewCommand() {
        // Given
        predicate.result = nil

        // When
        handler.notify_viewWillDisappear(viewController: mockView, animated: .mockAny())

        // Then
        XCTAssertNil(commandSubscriber.receivedCommand)
    }
}
