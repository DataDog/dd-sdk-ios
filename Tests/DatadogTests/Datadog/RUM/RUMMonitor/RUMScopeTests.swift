/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import Datadog

class RUMScopeTests: XCTestCase {
    /// A mock `RUMScope` that completes or not based on the configuration.
    private class CompletableScope: RUMScope {
        let isCompleted: Bool

        init(isCompleted: Bool) {
            self.isCompleted = isCompleted
        }

        let context = RUMContext.mockWith(rumApplicationID: .mockAny(), sessionID: .nullUUID)
        func process(command: RUMCommand, context: DatadogContext, writer: Writer) -> Bool { !isCompleted }
    }

    func testWhenPropagatingCommand_itRemovesCompletedScope() {
        // Direct reference
        var scope: CompletableScope? = CompletableScope(isCompleted: true)
        scope = scope?.scope(byPropagating: RUMCommandMock(), context: .mockAny(), writer: FileWriterMock())
        XCTAssertNil(scope)
    }

    func testWhenPropagatingCommand_itKeepsNonCompletedScope() {
        // Direct reference
        var scope: CompletableScope? = CompletableScope(isCompleted: false)
        scope = scope?.scope(byPropagating: RUMCommandMock(), context: .mockAny(), writer: FileWriterMock())
        XCTAssertNotNil(scope)
    }

    func testWhenPropagatingCommand_itRemovesCompletedScopes() {
        var scopes: [CompletableScope] = [
            CompletableScope(isCompleted: true),
            CompletableScope(isCompleted: false),
            CompletableScope(isCompleted: true),
            CompletableScope(isCompleted: false)
        ]

        scopes = scopes.scopes(byPropagating: RUMCommandMock(), context: .mockAny(), writer: FileWriterMock())

        XCTAssertEqual(scopes.count, 2)
        XCTAssertEqual(scopes.filter { !$0.isCompleted }.count, 2)
    }

    func testMergingRUMAttributes() {
        var attributes: [AttributeKey: AttributeValue] = ["foo": "bar", "fizz": "buzz"]
        let additionalAttributes: [AttributeKey: AttributeValue] = ["foo": "bar 2", "baz": "qux"]

        attributes.merge(rumCommandAttributes: additionalAttributes)
        XCTAssertEqual(attributes as? [String: String], ["foo": "bar 2", "fizz": "buzz", "baz": "qux"], "`bar` should be overwritten")

        attributes.merge(rumCommandAttributes: nil)
        XCTAssertEqual(attributes as? [String: String], ["foo": "bar 2", "fizz": "buzz", "baz": "qux"])
    }
}
