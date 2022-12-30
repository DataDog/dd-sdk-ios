/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import UIKit
@testable import DatadogSessionReplay

class CGRectContentFrameTests: XCTestCase {
    let accuracy = CGFloat(0.001)

    func testZeroContentFrame() {
        XCTAssertRectsEqual(
            CGRect.zero.contentFrame(for: CGSize.mockAny(), using: .scaleAspectFit),
            .zero,
            accuracy: accuracy
        )

        XCTAssertRectsEqual(
            CGRect.zero.contentFrame(for: CGSize.mockAny(), using: .scaleAspectFit),
            .zero,
            accuracy: accuracy
        )

        XCTAssertRectsEqual(
            CGRect(origin: .zero, size: CGSize(width: 0, height: 100))
                .contentFrame(for: CGSize.mockAny(), using: .scaleAspectFit),
            .zero,
            accuracy: accuracy
        )

        XCTAssertRectsEqual(
            CGRect(origin: .zero, size: CGSize(width: 100, height: 0))
                .contentFrame(for: CGSize.zero, using: .scaleAspectFit),
            .zero,
            accuracy: accuracy
        )

        XCTAssertRectsEqual(
            CGRect.mockAny().contentFrame(for: CGSize.zero, using: .scaleAspectFit),
            .zero,
            accuracy: accuracy
        )

        XCTAssertRectsEqual(
            CGRect.mockAny().contentFrame(for: CGSize(width: 0, height: 100), using: .scaleAspectFit),
            .zero,
            accuracy: accuracy
        )

        XCTAssertRectsEqual(
            CGRect.mockAny().contentFrame(for:  CGSize(width: 100, height: 0), using: .scaleAspectFit),
            .zero,
            accuracy: accuracy
        )
    }

    func testSmallContentFrameForAllContentModes() {
        let frame = CGRect(x: 10, y: 10, width: 100, height: 100)
        let contentSize = CGSize(width: 21, height: 19.5)
        XCTAssertRectsEqual(
            frame.contentFrame(for: contentSize, using: .scaleAspectFit),
            CGRect(x: 10.0, y: 13.57142857142857, width: 100.0, height: 92.85714285714286),
            accuracy: accuracy
        )
        XCTAssertRectsEqual(
            frame.contentFrame(for: contentSize, using: .scaleAspectFill),
            CGRect(x: 6.153846153846146, y: 9.999999999999993, width: 107.69230769230771, height: 100.00000000000001), accuracy: accuracy
        )
        XCTAssertRectsEqual(
            frame.contentFrame(for: contentSize, using: .scaleToFill),
            CGRect(x: 10, y: 10, width: 100, height: 100), accuracy: accuracy
        )
        XCTAssertRectsEqual(
            frame.contentFrame(for: contentSize, using: .redraw),
            CGRect(x: 49.5, y: 50.25, width: 21.0, height: 19.5), accuracy: accuracy
        )
        XCTAssertRectsEqual(
            frame.contentFrame(for: contentSize, using: .center),
            CGRect(x: 49.5, y: 50.25, width: 21.0, height: 19.5), accuracy: accuracy
        )
        XCTAssertRectsEqual(
            frame.contentFrame(for: contentSize, using: .left),
            CGRect(x: 10.0, y: 50.25, width: 21.0, height: 19.5), accuracy: accuracy
        )
        XCTAssertRectsEqual(
            frame.contentFrame(for: contentSize, using: .right),
            CGRect(x: 89.0, y: 50.25, width: 21.0, height: 19.5), accuracy: accuracy
        )
        XCTAssertRectsEqual(
            frame.contentFrame(for: contentSize, using: .top),
            CGRect(x: 49.5, y: 10.0, width: 21.0, height: 19.5), accuracy: accuracy
        )
        XCTAssertRectsEqual(
            frame.contentFrame(for: contentSize, using: .bottom),
            CGRect(x: 49.5, y: 90.5, width: 21.0, height: 19.5), accuracy: accuracy
        )
        XCTAssertRectsEqual(
            frame.contentFrame(for: contentSize, using: .bottomLeft),
            CGRect(x: 10.0, y: 90.5, width: 21.0, height: 19.5), accuracy: accuracy
        )
        XCTAssertRectsEqual(
            frame.contentFrame(for: contentSize, using: .bottomRight),
            CGRect(x: 89.0, y: 90.5, width: 21.0, height: 19.5), accuracy: accuracy
        )
        XCTAssertRectsEqual(
            frame.contentFrame(for: contentSize, using: .topLeft),
            CGRect(x: 10.0, y: 10.0, width: 21.0, height: 19.5), accuracy: accuracy
        )
        XCTAssertRectsEqual(
            frame.contentFrame(for: contentSize, using: .topRight),
            CGRect(x: 89.0, y: 10.0, width: 21.0, height: 19.5), accuracy: accuracy
        )
    }

    func testBigContentFrameForAllContentModes() {
        let frame = CGRect(x: 100, y: 100, width: 100, height: 100)
        let contentSize = CGSize(width: 200, height: 200)
        XCTAssertRectsEqual(
            frame.contentFrame(for: contentSize, using: .scaleAspectFit),
            CGRect(x: 100.0, y: 100.0, width: 100.0, height: 100.0), accuracy: accuracy
        )
        XCTAssertRectsEqual(
            frame.contentFrame(for: contentSize, using: .scaleAspectFill),
            CGRect(x: 100.0, y: 100.0, width: 100.0, height: 100.0), accuracy: accuracy
        )
        XCTAssertRectsEqual(
            frame.contentFrame(for: contentSize, using: .scaleToFill),
            CGRect(x: 100.0, y: 100.0, width: 100.0, height: 100.0), accuracy: accuracy
        )
        XCTAssertRectsEqual(
            frame.contentFrame(for: contentSize, using: .redraw),
            CGRect(x: 50.0, y: 50.0, width: 200.0, height: 200.0), accuracy: accuracy
        )
        XCTAssertRectsEqual(
            frame.contentFrame(for: contentSize, using: .center),
            CGRect(x: 50.0, y: 50.0, width: 200.0, height: 200.0), accuracy: accuracy
        )
        XCTAssertRectsEqual(
            frame.contentFrame(for: contentSize, using: .left),
            CGRect(x: 100.0, y: 50.0, width: 200.0, height: 200.0), accuracy: accuracy
        )
        XCTAssertRectsEqual(
            frame.contentFrame(for: contentSize, using: .right),
            CGRect(x: 0.0, y: 50.0, width: 200.0, height: 200.0), accuracy: accuracy
        )
        XCTAssertRectsEqual(
            frame.contentFrame(for: contentSize, using: .top),
            CGRect(x: 50.0, y: 100.0, width: 200.0, height: 200.0), accuracy: accuracy
        )
        XCTAssertRectsEqual(
            frame.contentFrame(for: contentSize, using: .bottom),
            CGRect(x: 50.0, y: 0.0, width: 200.0, height: 200.0), accuracy: accuracy
        )
        XCTAssertRectsEqual(
            frame.contentFrame(for: contentSize, using: .bottomLeft),
            CGRect(x: 100.0, y: 0.0, width: 200.0, height: 200.0), accuracy: accuracy
        )
        XCTAssertRectsEqual(
            frame.contentFrame(for: contentSize, using: .bottomRight),
            CGRect(x: 0.0, y: 0.0, width: 200.0, height: 200.0), accuracy: accuracy
        )
        XCTAssertRectsEqual(
            frame.contentFrame(for: contentSize, using: .topLeft),
            CGRect(x: 100.0, y: 100.0, width: 200.0, height: 200.0), accuracy: accuracy
        )
        XCTAssertRectsEqual(
            frame.contentFrame(for: contentSize, using: .topRight),
            CGRect(x: 0.0, y: 100.0, width: 200.0, height: 200.0), accuracy: accuracy
        )
    }
}

func XCTAssertRectsEqual(
    _ rect1: CGRect,
    _ rect2: CGRect,
    accuracy: CGFloat,
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(rect1.origin.x, rect2.origin.x, accuracy: accuracy, message, file: file, line: line)
    XCTAssertEqual(rect1.origin.y, rect2.origin.y, accuracy: accuracy, message, file: file, line: line)
    XCTAssertEqual(rect1.width, rect2.width, accuracy: accuracy, message, file: file, line: line)
    XCTAssertEqual(rect1.height, rect2.height, accuracy: accuracy, message, file: file, line: line)
}
