/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@_spi(objc)
@testable import DatadogRUM

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
        XCTAssertTrue(objc_RUMMonitor.shared().swiftRUMMonitor is NOPMonitor)
    }

    func testWhenEnabled() {
        objc_RUM.enable(with: objc_RUMConfiguration(applicationID: "app-id"))
        XCTAssertTrue(objc_RUMMonitor.shared().swiftRUMMonitor is Monitor)
    }
}
