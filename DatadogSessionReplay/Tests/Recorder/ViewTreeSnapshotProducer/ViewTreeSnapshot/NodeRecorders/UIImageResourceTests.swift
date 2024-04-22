/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay

// Soft checks, because different iOS versions may produce different image data or hashing
final class UIImageResourceTests: XCTestCase {
    func testWhenUIImageResourceIsInitializedWithEmptyImage() {
        let imageResource = UIImageResource(image: UIImage(), tintColor: nil)

        XCTAssertEqual(imageResource.calculateIdentifier(), "")
        XCTAssertEqual(imageResource.calculateData(), Data())
    }

    func testWhenUIImageResourceIsInitializedWithoutTintColor() {
        let image = createSinglePixelImage()
        let imageResource = UIImageResource(image: image, tintColor: nil)

        XCTAssertEqual(imageResource.calculateIdentifier(), "eab6bf754eb6a790cc1240262c1c3a29")
        XCTAssertGreaterThan(imageResource.calculateData().count, 0)
    }

    func testWhenUIImageResourceIsInitializedWithTintColor() {
        let image = createSinglePixelImage()
        let tintColor = UIColor.red
        let imageResource = UIImageResource(image: image, tintColor: tintColor)

        XCTAssertEqual(imageResource.calculateIdentifier(), "eab6bf754eb6a790cc1240262c1c3a29FF0000FF")
        XCTAssertGreaterThan(imageResource.calculateData().count, 0)
    }

    @available(iOS 13.0, *)
    func testWhenUIImageResourceIsInitializedWithSystemIconWithoutTintColor() {
        let image = UIImage(systemName: "circle.fill")!
        let imageResource = UIImageResource(image: image, tintColor: nil)

        XCTAssertEqual(imageResource.calculateIdentifier(), "d918588dd612a9e8a13d9eedb5b57f78")
        XCTAssertGreaterThan(imageResource.calculateData().count, 0)
    }

    @available(iOS 13.0, *)
    func testWhenUIImageResourceIsInitializedWithSystemIconWithTintColor() {
        let image = UIImage(systemName: "circle.fill")!
        let tintColor = UIColor.red
        let imageResource = UIImageResource(image: image, tintColor: tintColor)

        XCTAssertEqual(imageResource.calculateIdentifier(), "d918588dd612a9e8a13d9eedb5b57f78FF0000FF")
        XCTAssertGreaterThan(imageResource.calculateData().count, 0)
    }

    private func createSinglePixelImage() -> UIImage {
        UIGraphicsBeginImageContext(CGSize(width: 1, height: 1))
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return image
    }
}
