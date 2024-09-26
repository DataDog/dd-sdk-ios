/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
@testable import DatadogSessionReplay

// Soft checks, because different iOS versions may produce different image data or hashing
final class UIImageResourceTests: XCTestCase {
    func testWhenUIImageResourceIsInitializedWithEmptyImage() {
        let image = UIImage()
        let imageResource = UIImageResource(image: image, tintColor: nil)

        XCTAssertEqual(imageResource.calculateIdentifier(), "\(image.hash)")
        XCTAssertEqual(imageResource.calculateData(), Data())
    }

    func testWhenUIImageResourceIsInitializedWithoutTintColor() {
        let image = createSinglePixelImage()
        let imageResource = UIImageResource(image: image, tintColor: nil)

        XCTAssertEqual(imageResource.calculateIdentifier().count, 32)
        XCTAssertGreaterThan(imageResource.calculateData().count, 0)
    }

    func testWhenUIImageResourceIsInitializedWithTintColor() {
        let image = createSinglePixelImage()
        let tintColor = UIColor.red
        let imageResource = UIImageResource(image: image, tintColor: tintColor)

        XCTAssertEqual(imageResource.calculateIdentifier().count, 40)
        XCTAssertTrue(imageResource.calculateIdentifier().contains("FF0000FF"))
        XCTAssertGreaterThan(imageResource.calculateData().count, 0)
    }

    @available(iOS 13.0, *)
    func testWhenUIImageResourceIsInitializedWithSystemIconWithoutTintColor() {
        let image = UIImage(systemName: "circle.fill")!
        let imageResource = UIImageResource(image: image, tintColor: nil)

        XCTAssertEqual(imageResource.calculateIdentifier().count, 32)
        XCTAssertGreaterThan(imageResource.calculateData().count, 0)
    }

    @available(iOS 13.0, *)
    func testWhenUIImageResourceIsInitializedWithSystemIconWithTintColor() {
        let image = UIImage(systemName: "circle.fill")!
        let tintColor = UIColor.red
        let imageResource = UIImageResource(image: image, tintColor: tintColor)

        XCTAssertEqual(imageResource.calculateIdentifier().count, 40)
        XCTAssertTrue(imageResource.calculateIdentifier().contains("FF0000FF"))
        XCTAssertGreaterThan(imageResource.calculateData().count, 0)
    }

    private func createSinglePixelImage() -> UIImage {
        UIGraphicsBeginImageContext(CGSize(width: 1, height: 1))
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return image
    }
}
#endif
