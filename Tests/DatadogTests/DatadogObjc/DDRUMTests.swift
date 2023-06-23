/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogRUM
@testable import DatadogObjc

class DDRUMTests: XCTestCase {
    private var core: FeatureRegistrationCoreMock! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = FeatureRegistrationCoreMock()
        CoreRegistry.register(default: core)
    }

    override func tearDown() {
        CoreRegistry.unregisterDefault()
        core = nil
        super.tearDown()
    }

    func testWhenNotEnabled() {
        XCTAssertTrue(DDRUMMonitor.shared().swiftRUMMonitor is NOPMonitor)
    }

    func testWhenEnabled() {
        DDRUM.enable(with: DDRUMConfiguration(applicationID: "app-id"))
        XCTAssertTrue(DDRUMMonitor.shared().swiftRUMMonitor is Monitor)
    }
}
