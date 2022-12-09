/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import UIKit
@testable import DatadogSessionReplay

class UIImageViewRecordingTests: XCTestCase {
    var frame: CGRect!
    var imageView: UIImageView!

    override func setUp() {
        super.setUp()
        frame = CGRect(x: 10, y: 10, width: 100, height: 100)
        imageView = UIImageView(frame: frame)
        if #available(iOS 13.0, *) {
            imageView.image = UIImage(systemName: "testtube.2")
        }
    }

    override func tearDown() {
        imageView = nil
        frame = nil
        super.tearDown()
    }

    func testImageFrameForScaleAspectFit() {
        imageView.contentMode = .scaleAspectFit

        let imageFrame = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrame, CGRect(x: 10, y: 13.174603174603178, width: 100, height: 93.65079365079364))

        imageView.clipsToBounds = true
        let imageFrameClipped = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrameClipped, CGRect(x: 10, y: 13.174603174603178, width: 100, height: 93.65079365079364))
    }

    func testImageFrameForScaleAspectFill() {
        imageView.contentMode = .scaleAspectFill

        let imageFrame = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrame, CGRect(x: 6.610169491525426, y: 10.0, width: 106.77966101694915, height: 100.0))

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
        XCTAssertEqual(imageFrame, CGRect(x: 49.5, y: 50.166666666666664, width: 21.0, height: 19.666666666666668))

        imageView.clipsToBounds = true
        let imageFrameClipped = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrameClipped, CGRect(x: 49.5, y: 50.166666666666664, width: 21.0, height: 19.666666666666668))
    }

    func testImageFrameForCenter() {
        imageView.contentMode = .center

        let imageFrame = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrame, CGRect(x: 49.5, y: 50.166666666666664, width: 21.0, height: 19.666666666666668))

        imageView.clipsToBounds = true
        let imageFrameClipped = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrameClipped, CGRect(x: 49.5, y: 50.166666666666664, width: 21.0, height: 19.666666666666668))
    }

    func testImageFrameForLeft() {
        imageView.contentMode = .left

        let imageFrame = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrame, CGRect(x: 10.0, y: 50.166666666666664, width: 21.0, height: 19.666666666666668))

        imageView.clipsToBounds = true
        let imageFrameClipped = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrameClipped, CGRect(x: 10.0, y: 50.166666666666664, width: 21.0, height: 19.666666666666668))
    }

    func testImageFrameForRight() {
        imageView.contentMode = .right

        let imageFrame = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrame, CGRect(x: 89.0, y: 50.166666666666664, width: 21.0, height: 19.666666666666668))

        imageView.clipsToBounds = true
        let imageFrameClipped = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrameClipped, CGRect(x: 89.0, y: 50.166666666666664, width: 21.0, height: 19.666666666666668))
    }

    func testImageFrameForTop() {
        imageView.contentMode = .top

        let imageFrame = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrame, CGRect(x: 49.5, y: 10.0, width: 21.0, height: 19.666666666666668))

        imageView.clipsToBounds = true
        let imageFrameClipped = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrameClipped, CGRect(x: 49.5, y: 10.0, width: 21.0, height: 19.666666666666668))
    }

    func testImageFrameForBottom() {
        imageView.contentMode = .bottom

        let imageFrame = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrame, CGRect(x: 49.5, y: 90.33333333333333, width: 21.0, height: 19.666666666666668))

        imageView.clipsToBounds = true
        let imageFrameClipped = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrameClipped, CGRect(x: 49.5, y: 90.33333333333333, width: 21.0, height: 19.666666666666668))
    }

    func testImageFrameForBottomLeft() {
        imageView.contentMode = .bottomLeft

        let imageFrame = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrame, CGRect(x: 10.0, y: 90.33333333333333, width: 21.0, height: 19.666666666666668))

        imageView.clipsToBounds = true
        let imageFrameClipped = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrameClipped, CGRect(x: 10.0, y: 90.33333333333333, width: 21.0, height: 19.666666666666668))
    }

    func testImageFrameForBottomRight() {
        imageView.contentMode = .bottomRight

        let imageFrame = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrame, CGRect(x: 89.0, y: 90.33333333333333, width: 21.0, height: 19.666666666666668))

        imageView.clipsToBounds = true
        let imageFrameClipped = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrameClipped, CGRect(x: 89.0, y: 90.33333333333333, width: 21.0, height: 19.666666666666668))
    }

    func testImageFrameForTopLeft() {
        imageView.contentMode = .topLeft

        let imageFrame = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrame, CGRect(x: 10.0, y: 10.0, width: 21.0, height: 19.666666666666668))

        imageView.clipsToBounds = true
        let imageFrameClipped = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrameClipped, CGRect(x: 10.0, y: 10.0, width: 21.0, height: 19.666666666666668))
    }

    func testImageFrameForTopRight() {
        imageView.contentMode = .topRight

        let imageFrame = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrame, CGRect(x: 89.0, y: 10.0, width: 21.0, height: 19.666666666666668))

        imageView.clipsToBounds = true
        let imageFrameClipped = imageView.imageFrame(in: frame)
        XCTAssertEqual(imageFrameClipped, CGRect(x: 89.0, y: 10.0, width: 21.0, height: 19.666666666666668))
    }
}
