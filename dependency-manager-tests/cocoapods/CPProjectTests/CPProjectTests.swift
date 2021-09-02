/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

import XCTest
#if COMPILING_FOR_USE_FRAMEWORKS
@testable import CPProjectUseFrameworks
#else
@testable import CPProjectNoUseFrameworks
#endif

class CPProjectTests: XCTestCase {
    func testCallingLogicThatLoadsSDK() throws {
        let viewController = ViewController()
        viewController.viewDidLoad()
        XCTAssertNotNil(viewController.view)
    }
}
