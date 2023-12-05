/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import UIKit
import TestUtilities
import DatadogInternal
@testable import DatadogRUM

// TODO: RUMM-2034 Remove this flag once we have a host application for tests
#if !os(tvOS)

class RUMDebuggingTests: XCTestCase {
    func testWhenOneRUMViewIsActive_itDisplaysSingleRUMViewOutline() throws {
        let expectation = self.expectation(description: "Render RUMDebugging")

        // when
        let applicationScope = RUMApplicationScope(
            dependencies: .mockWith(rumApplicationID: "rum-123")
        )
        _ = applicationScope.process(
            command: RUMStartViewCommand.mockWith(identity: mockViewIdentity, name: "FirstView"),
            context: .mockAny(),
            writer: FileWriterMock()
        )

        let debugging = RUMDebugging()
        debugging.debug(applicationScope: applicationScope)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { expectation.fulfill() }
        waitForExpectations(timeout: 2, handler: nil)

        // then
        let canvas = try XCTUnwrap(
            UIApplication.shared.keyWindow?.subviews.first { $0 is RUMDebugView },
            "Cannot find `RUMDebugging` canvas."
        )

        XCTAssertEqual(canvas.subviews.count, 1)
        let viewOutline = try XCTUnwrap(canvas.subviews.first)
        let viewOutlineLabel = try XCTUnwrap(viewOutline.subviews.first as? UILabel)
        XCTAssertEqual(viewOutlineLabel.text, "FirstView # ACTIVE")
    }

    func testWhenOneRUMViewIsInactive_andSecondIsActive_itDisplaysTwoRUMViewOutlines() throws {
        let context: DatadogContext = .mockAny()
        let writer = FileWriterMock()

        let expectation = self.expectation(description: "Render RUMDebugging")

        // when
        let applicationScope = RUMApplicationScope(
            dependencies: .mockWith(rumApplicationID: "rum-123")
        )
        _ = applicationScope.process(
            command: RUMStartViewCommand.mockWith(identity: mockViewIdentity, name: "FirstView"),
            context: context,
            writer: writer
        )
        _ = applicationScope.process(
            command: RUMStartResourceCommand.mockAny(),
            context: context,
            writer: writer
        )
        _ = applicationScope.process(
            command: RUMStartViewCommand.mockWith(identity: mockViewIdentity, name: "SecondView"),
            context: context,
            writer: writer
        )

        let debugging = RUMDebugging()
        debugging.debug(applicationScope: applicationScope)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { expectation.fulfill() }
        waitForExpectations(timeout: 2, handler: nil)

        // then
        let canvas = try XCTUnwrap(
            UIApplication.shared.keyWindow?.subviews.first { $0 is RUMDebugView },
            "Cannot find `RUMDebugging` canvas."
        )

        XCTAssertEqual(canvas.subviews.count, 2)
        let firstViewOutline = try XCTUnwrap(canvas.subviews.first)
        let firstViewOutlineLabel = try XCTUnwrap(firstViewOutline.subviews.first as? UILabel)
        XCTAssertEqual(firstViewOutlineLabel.text, "FirstView # INACTIVE")
        let secondViewOutline = try XCTUnwrap(canvas.subviews.dropFirst().first)
        let secondViewOutlineLabel = try XCTUnwrap(secondViewOutline.subviews.first as? UILabel)
        XCTAssertEqual(secondViewOutlineLabel.text, "SecondView # ACTIVE")
        XCTAssertLessThan(firstViewOutlineLabel.alpha, secondViewOutlineLabel.alpha)
    }
}

#endif
