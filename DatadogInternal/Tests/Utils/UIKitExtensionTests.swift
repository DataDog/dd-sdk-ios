/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

#if canImport(UIKit) && !os(watchOS)
import UIKit
@testable import DatadogInternal

final class UIKitExtensionTests: XCTestCase {
    func testItRecognizesSwiftUIRuntimeClassNames() {
        XCTAssertTrue(UIView.dd.isSwiftUIRuntimeClassName("SwiftUI.UIKitTabBarController"))
        XCTAssertTrue(UIView.dd.isSwiftUIRuntimeClassName("_TtGC7SwiftUI19UIHostingControllerVVS_7TabItem8RootView_"))
        XCTAssertTrue(UIView.dd.isSwiftUIRuntimeClassName("_TtCV7SwiftUIP33_D74FE142C3C5A6C2CEA4987A69AEBD7522SystemSegmentedControl18UISegmentedControl"))
    }

    func testItDoesNotTreatAppClassNamesContainingSwiftUIAsSwiftUIRuntimeClasses() {
        XCTAssertFalse(UIView.dd.isSwiftUIRuntimeClassName("DatadogTests.MySwiftUIView"))
    }
}
#endif
