/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import UIKit
@testable import DatadogSessionReplay

/// Make sure to run on iPhone 11
class UIImageViewRecordingTests: XCTestCase {
    var frame: CGRect = .zero
    var imageView: UIImageView = .init()

    override func setUp() {
        super.setUp()
        frame = CGRect(x: 10, y: 10, width: 100, height: 100)
        imageView = UIImageView(frame: frame)
        if #available(iOS 13.0, *) {
            imageView.image = UIImage(systemName: "testtube.2")
        }
    }

    override func tearDown() {
        imageView = .init()
        frame = .zero
        super.tearDown()
    }

    func testImageFrameForScaleAspectFit() {
        imageView.contentMode = .scaleAspectFit

        let imageFrame = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrame, CGRect(x: 10.0, y: 13.57142857142857, width: 100.0, height: 92.85714285714286))

        imageView.clipsToBounds = true
        let imageFrameClipped = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrameClipped, CGRect(x: 10.0, y: 13.57142857142857, width: 100.0, height: 92.85714285714286))
    }

    func testImageFrameForScaleAspectFill() {
        imageView.contentMode = .scaleAspectFill

        let imageFrame = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrame, CGRect(x: 6.153846153846146, y: 9.999999999999993, width: 107.69230769230771, height: 100.00000000000001))

        imageView.clipsToBounds = true
        let imageFrameClipped = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrameClipped, CGRect(x: 10, y: 10, width: 100, height: 100))
    }

    func testImageFrameForScaleToFill() {
        imageView.contentMode = .scaleToFill

        let imageFrame = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrame, CGRect(x: 10, y: 10, width: 100, height: 100))

        imageView.clipsToBounds = true
        let imageFrameClipped = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrameClipped, CGRect(x: 10, y: 10, width: 100, height: 100))
    }

    func testImageFrameForRedraw() {
        imageView.contentMode = .redraw

        let imageFrame = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrame, CGRect(x: 49.5, y: 50.25, width: 21.0, height: 19.5))

        imageView.clipsToBounds = true
        let imageFrameClipped = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrameClipped, CGRect(x: 49.5, y: 50.25, width: 21.0, height: 19.5))
    }

    func testImageFrameForCenter() {
        imageView.contentMode = .center

        let imageFrame = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrame, CGRect(x: 49.5, y: 50.25, width: 21.0, height: 19.5))

        imageView.clipsToBounds = true
        let imageFrameClipped = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrameClipped, CGRect(x: 49.5, y: 50.25, width: 21.0, height: 19.5))
    }

    func testImageFrameForLeft() {
        imageView.contentMode = .left

        let imageFrame = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrame, CGRect(x: 10.0, y: 50.25, width: 21.0, height: 19.5))

        imageView.clipsToBounds = true
        let imageFrameClipped = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrameClipped, CGRect(x: 10.0, y: 50.25, width: 21.0, height: 19.5))
    }

    func testImageFrameForRight() {
        imageView.contentMode = .right

        let imageFrame = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrame, CGRect(x: 89.0, y: 50.25, width: 21.0, height: 19.5))

        imageView.clipsToBounds = true
        let imageFrameClipped = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrameClipped, CGRect(x: 89.0, y: 50.25, width: 21.0, height: 19.5))
    }

    func testImageFrameForTop() {
        imageView.contentMode = .top

        let imageFrame = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrame, CGRect(x: 49.5, y: 10.0, width: 21.0, height: 19.5))

        imageView.clipsToBounds = true
        let imageFrameClipped = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrameClipped, CGRect(x: 49.5, y: 10.0, width: 21.0, height: 19.5))
    }

    func testImageFrameForBottom() {
        imageView.contentMode = .bottom

        let imageFrame = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrame, CGRect(x: 49.5, y: 90.5, width: 21.0, height: 19.5))

        imageView.clipsToBounds = true
        let imageFrameClipped = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrameClipped, CGRect(x: 49.5, y: 90.5, width: 21.0, height: 19.5))
    }

    func testImageFrameForBottomLeft() {
        imageView.contentMode = .bottomLeft

        let imageFrame = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrame, CGRect(x: 10.0, y: 90.5, width: 21.0, height: 19.5))

        imageView.clipsToBounds = true
        let imageFrameClipped = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrameClipped, CGRect(x: 10.0, y: 90.5, width: 21.0, height: 19.5))
    }

    func testImageFrameForBottomRight() {
        imageView.contentMode = .bottomRight

        let imageFrame = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrame, CGRect(x: 89.0, y: 90.5, width: 21.0, height: 19.5))

        imageView.clipsToBounds = true
        let imageFrameClipped = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrameClipped, CGRect(x: 89.0, y: 90.5, width: 21.0, height: 19.5))
    }

    func testImageFrameForTopLeft() {
        imageView.contentMode = .topLeft

        let imageFrame = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrame, CGRect(x: 10.0, y: 10.0, width: 21.0, height: 19.5))

        imageView.clipsToBounds = true
        let imageFrameClipped = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrameClipped, CGRect(x: 10.0, y: 10.0, width: 21.0, height: 19.5))
    }

    func testImageFrameForTopRight() {
        imageView.contentMode = .topRight

        let imageFrame = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrame, CGRect(x: 89.0, y: 10.0, width: 21.0, height: 19.5))

        imageView.clipsToBounds = true
        let imageFrameClipped = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrameClipped, CGRect(x: 89.0, y: 10.0, width: 21.0, height: 19.5))
    }
}
