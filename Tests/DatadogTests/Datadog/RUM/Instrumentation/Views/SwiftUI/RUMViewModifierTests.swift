/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import SwiftUI

@testable import Datadog

class RUMViewModifierTests: XCTestCase {
    let swiftUIHandler = SwiftUIViewHandlerMock()
    let subscriber = RUMCommandSubscriberMock()

    @available(iOS 13, *)
    struct TestView: View {
        let name: String
        let attributes: [AttributeKey: AttributeValue]
        var body: some View {
            EmptyView()
                .trackRUMView(
                    name: name,
                    attributes: attributes
                )
        }
    }

    override func setUp() {
        super.setUp()

        RUMInstrumentation.instance = RUMInstrumentation(
            viewsAutoInstrumentation: nil,
            swiftUIViewInstrumentation: swiftUIHandler,
            userActionsAutoInstrumentation: nil,
            longTasks: nil
        )

        RUMInstrumentation.instance?.publish(to: subscriber)
    }

    override func tearDown() {
        RUMInstrumentation.instance?.deinitialize()
    }

    func testGivenASwiftUIView_WhenItAppearsAndDisappears_ItNotifiesTheRUMInstrumentation() throws {
        guard #available(iOS 13, *) else {
            return
        }

        let expectOnAppear = expectation(description: "SwiftUI.View.onAppear")
        let expectOnDisappear = expectation(description: "SwiftUI.View.onDisappear")

        // Given
        let viewName: String = .mockRandom()
        let viewAttributes = mockRandomAttributes()
        let animated = Bool.random()

        var host: UIHostingController? = UIHostingController(
            rootView: TestView(
                name: viewName,
                attributes: viewAttributes
            )
        )

        var viewIdentity: String?

        swiftUIHandler.notifyOnAppear = { identity, name, path, attributes in
            viewIdentity = identity
            XCTAssertTrue(identity.matches(regex: .uuidRegex))
            XCTAssertEqual(name, viewName)
            XCTAssertTrue(path.matches(regex: "\(viewName)\\/[0-9]*"))
            self.AssertDictionariesEqual(attributes, viewAttributes)
            expectOnAppear.fulfill()
        }

        swiftUIHandler.notifyOnDisappear = { identity in
            XCTAssertEqual(viewIdentity, identity)
            expectOnDisappear.fulfill()
        }

        // When
        // Trigger the `.onAppear`
        host?.viewWillAppear(animated)
        host?.viewDidAppear(animated)

        // Then
        wait(for: [expectOnAppear], timeout: 5)

        // When
        host = nil // Trigger the `.onDisappear`
        wait(for: [expectOnDisappear], timeout: 5)
    }
}
