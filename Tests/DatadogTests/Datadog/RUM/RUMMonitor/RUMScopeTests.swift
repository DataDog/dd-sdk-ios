/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class RUMScopeTests: XCTestCase {
    /// A mock `RUMScope` that completes or not based on the configuration.
    private class CompletableScope: RUMScope {
        let isCompleted: Bool

        init(isCompleted: Bool) {
            self.isCompleted = isCompleted
        }

        let context = RUMContext.mockWith(rumApplicationID: .mockAny(), sessionID: .nullUUID)
        func process(command: RUMCommand) -> Bool { !isCompleted }
    }

    private class AnyScope: RUMScope {
        func process(command: RUMCommand) -> Bool { .mockAny() }
    }

    func testWhenPropagatingCommand_itRemovesCompletedScope() {
        // Direct reference
        var scope: CompletableScope? = CompletableScope(isCompleted: true)
        scope = AnyScope().manage(childScope: scope, byPropagatingCommand: RUMCommandMock())
        XCTAssertNil(scope)
    }

    func testWhenPropagatingCommand_itKeepsNonCompletedScope() {
        // Direct reference
        var scope: CompletableScope? = CompletableScope(isCompleted: false)
        scope = AnyScope().manage(childScope: scope, byPropagatingCommand: RUMCommandMock())
        XCTAssertNotNil(scope)
    }

    func testWhenPropagatingCommand_itRemovesCompletedScopes() {
        var scopes: [CompletableScope] = [
            CompletableScope(isCompleted: true),
            CompletableScope(isCompleted: false),
            CompletableScope(isCompleted: true),
            CompletableScope(isCompleted: false)
        ]

        scopes = AnyScope().manage(childScopes: scopes, byPropagatingCommand: RUMCommandMock())

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
