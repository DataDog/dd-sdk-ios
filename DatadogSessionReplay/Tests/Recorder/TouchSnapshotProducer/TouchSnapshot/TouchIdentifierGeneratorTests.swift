/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
@testable import DatadogSessionReplay
@testable import TestUtilities

class TouchIdentifierGeneratorTests: XCTestCase {
    func testItPersistsUniqueIDThroughoutAllTouchPhasesForEachInstanceOfUITouch() {
        // Given
        let generator = TouchIdentifierGenerator()
        let touchA = UITouchMock()
        let touchB = UITouchMock()

        var idsA: Set<TouchIdentifier> = []
        var idsB: Set<TouchIdentifier> = []

        // When
        touchA.phase = [.began, .moved, .stationary].randomElement()!
        touchB.phase = [.began, .moved, .stationary].randomElement()!
        idsA.insert(generator.touchIdentifier(for: touchA))
        idsB.insert(generator.touchIdentifier(for: touchB))

        (0..<20).forEach { _ in
            touchA.phase = [.moved, .stationary].randomElement()!
            touchB.phase = [.moved, .stationary].randomElement()!
            idsA.insert(generator.touchIdentifier(for: touchA))
            idsB.insert(generator.touchIdentifier(for: touchB))
        }

        touchA.phase = [.ended, .cancelled].randomElement()!
        touchB.phase = [.ended, .cancelled].randomElement()!
        idsA.insert(generator.touchIdentifier(for: touchA))
        idsB.insert(generator.touchIdentifier(for: touchB))

        // Then
        XCTAssertEqual(idsA.count, 1, "It must persist `TouchIdentifier` through all touch phases")
        XCTAssertEqual(idsB.count, 1, "It must persist `TouchIdentifier` through all touch phases")
        XCTAssertNotEqual(idsA, idsB, "Each `UITouch` must be given an unique identifier")
    }

    func testWhenUITouchInstanceGetsRecycled_itReceivesDifferentID() throws {
        // Given
        let generator = TouchIdentifierGenerator()
        let touch = UITouchMock()

        touch.phase = [.began, .moved, .stationary].randomElement()!
        let id1 = generator.touchIdentifier(for: touch)
        touch.phase = [.moved, .stationary].randomElement()!
        let id2 = generator.touchIdentifier(for: touch)
        touch.phase = [.ended, .cancelled].randomElement()!
        let id3 = generator.touchIdentifier(for: touch)

        // When
        touch.phase = [.began, .moved, .stationary].randomElement()!
        let id4 = generator.touchIdentifier(for: touch)
        touch.phase = [.moved, .stationary].randomElement()!
        let id5 = generator.touchIdentifier(for: touch)
        touch.phase = [.ended, .cancelled].randomElement()!
        let id6 = generator.touchIdentifier(for: touch)

        // Then
        XCTAssertTrue(id1 == id2 && id2 == id3)
        XCTAssertTrue(id4 == id5 && id5 == id6)
        XCTAssertNotEqual(id1, id4, "After `UITouch` gets recycled, it must receive different `TouchIdentifier`")
        XCTAssertNotEqual(id2, id5, "After `UITouch` gets recycled, it must receive different `TouchIdentifier`")
        XCTAssertNotEqual(id3, id6, "After `UITouch` gets recycled, it must receive different `TouchIdentifier`")
    }

    /// Following test covers an edge case, where SR is started right before the touch ends. In such situation
    /// we can still capture the touch, so it should be assigned an id.
    func testWhenTouchStartsInTerminalPhase_itReceivesOneTimeID() throws {
        // Given
        let generator = TouchIdentifierGenerator()
        let touch = UITouchMock(phase: [.ended, .cancelled].randomElement()!)

        // When
        let id1 = generator.touchIdentifier(for: touch)
        let id2 = generator.touchIdentifier(for: touch)

        // Then
        XCTAssertNotEqual(id1, id2)
    }

    func testAfterReachingMaxID_itStartsAgainFromZero() throws {
        // Given
        let maxID: TouchIdentifier = .mockRandom(min: 1)
        let currentID: TouchIdentifier = maxID - 1

        // When
        let generator = TouchIdentifierGenerator(currentID: currentID, maxID: maxID)

        // Then
        XCTAssertEqual(generator.touchIdentifier(for: UITouchMock(phase: .began)), currentID)
        XCTAssertEqual(generator.touchIdentifier(for: UITouchMock(phase: .began)), maxID)
        XCTAssertEqual(generator.touchIdentifier(for: UITouchMock(phase: .began)), 0)
    }
}
#endif
