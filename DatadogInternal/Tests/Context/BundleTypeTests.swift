/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal

class BundleTypeTests: XCTestCase {
    func testiOSAppBundleType() {
        let bundle: Bundle = .mockWith(bundlePath: "bundle.path.app")
        let bundleType = BundleType(bundle: bundle)
        XCTAssertEqual(bundleType, .iOSApp)
    }

    func testiOSAppExtensionBundleType() {
        let bundle: Bundle = .mockWith(bundlePath: "bundle.path.appex")
        let bundleType = BundleType(bundle: bundle)
        XCTAssertEqual(bundleType, .iOSAppExtension)
    }
}
