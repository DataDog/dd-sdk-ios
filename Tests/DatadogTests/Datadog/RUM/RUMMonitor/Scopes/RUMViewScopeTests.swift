/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import UIKit
@testable import Datadog

private class ViewControllerMock: UIViewController {}

class RUMViewScopeTests: XCTestCase {
//    private var mockOutput: RUMEventOutput!
//    private var parentScope: RUMScope!
//    private var scope: RUMViewScope!
//    private var dependencies: RUMScopeDependencies!


    func testWhenFirstViewIsStarted_itSendsApplicationStartActionAndViewUpdateEvent() throws {
        let output = RUMEventOutputMock()
        let parent = RUMScopeMock()
        let scope = RUMViewScope(
            parent: parent,
            dependencies: .mockWith(
//                dateProvider: RelativeDateProvider(using: .mockDecember15th2019At10AMUTC()),
                eventOutput: output
            ),
            identity: ViewControllerMock(),
            attributes: [:],
            startTime: .mockDecember15th2019At10AMUTC()
        )
    }
}
