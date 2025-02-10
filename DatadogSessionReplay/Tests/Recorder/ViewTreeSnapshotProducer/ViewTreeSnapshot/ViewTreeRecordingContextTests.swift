/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
import SafariServices
import SwiftUI

@_spi(Internal)
@testable import DatadogSessionReplay

class ViewTreeRecordingContextTests: XCTestCase {
    @available(iOS 13, tvOS 13, *)
    func testViewControllerTypeInit() {
        let alertVC = UIAlertController()
        let activityVC = UIActivityViewController(activityItems: [], applicationActivities: nil)
        let safariVC = SFSafariViewController(url: .mockRandom())
        let swiftUIVC = UIHostingController<EmptyView>(rootView: EmptyView())
        let otherVC = UIViewController()

        let alertVCType = ViewTreeRecordingContext.ViewControllerContext.ViewControllerType(alertVC)
        let activityVCType = ViewTreeRecordingContext.ViewControllerContext.ViewControllerType(activityVC)
        let safariVCType = ViewTreeRecordingContext.ViewControllerContext.ViewControllerType(safariVC)
        let swiftUIVCType = ViewTreeRecordingContext.ViewControllerContext.ViewControllerType(swiftUIVC)
        let otherVCType = ViewTreeRecordingContext.ViewControllerContext.ViewControllerType(otherVC)

        XCTAssertEqual(alertVCType, .alert)
        XCTAssertEqual(activityVCType, .activity)
        XCTAssertEqual(safariVCType, .safari)
        XCTAssertEqual(swiftUIVCType, .swiftUI)
        XCTAssertEqual(otherVCType, .other)
    }

    func testIsRootView() {
        var viewControllerContext = ViewTreeRecordingContext.ViewControllerContext()
        viewControllerContext.parentType = .alert
        viewControllerContext.isRootView = true

        XCTAssertTrue(viewControllerContext.isRootView(of: .alert))
        XCTAssertFalse(viewControllerContext.isRootView(of: .activity))
        XCTAssertFalse(viewControllerContext.isRootView(of: .safari))
        XCTAssertFalse(viewControllerContext.isRootView(of: .swiftUI))
        XCTAssertFalse(viewControllerContext.isRootView(of: .other))
    }

    func testName() {
        var viewControllerContext = ViewTreeRecordingContext.ViewControllerContext()
        viewControllerContext.parentType = .alert
        viewControllerContext.isRootView = true

        XCTAssertEqual(viewControllerContext.name, "Alert")

        viewControllerContext.parentType = .activity
        XCTAssertEqual(viewControllerContext.name, "Activity")

        viewControllerContext.parentType = .safari
        XCTAssertEqual(viewControllerContext.name, "Safari")

        viewControllerContext.parentType = .swiftUI
        XCTAssertEqual(viewControllerContext.name, "SwiftUI")

        viewControllerContext.parentType = .other
        XCTAssertNil(viewControllerContext.name)

        viewControllerContext.isRootView = false
        XCTAssertNil(viewControllerContext.name)
    }
}
#endif
