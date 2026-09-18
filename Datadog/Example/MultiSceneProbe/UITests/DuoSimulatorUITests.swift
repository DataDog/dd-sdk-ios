/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

/// Qualifies actual system input before native multi-scene acceptance uses it.
/// Passing this input check alone does not prove RUM ownership or hardware parity.
@MainActor
final class DuoSimulatorUITests: XCTestCase {
    func testInnerDisplaySplitViewInput() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeRight
        let app = XCUIApplication()
        let runID = UUID().uuidString.lowercased()
        app.launchArguments = [
            "--probe-scenario", "interactive.manual",
            "--probe-run-id", runID, "--probe-run-mode", "clean"
        ]
        app.launchEnvironment["DD_PROBE_CAPTURE_JSONL"] = "1"
        app.launch()
        defer { app.terminate() }

        let sourceA = app.staticTexts.matching(
            NSPredicate(format: "label == %@", "source: scene-A")
        ).firstMatch
        XCTAssertTrue(sourceA.waitForExistence(timeout: 15))
        attachState(app, name: "before-open-b-\(runID)")
        let openB = app.buttons.matching(
            NSPredicate(
                format: "identifier == %@ AND label == %@",
                "probe.native.scene-A.home", "Open scene B"
            )
        ).firstMatch
        XCTAssertTrue(openB.isHittable)
        openB.tap()
        let sourceB = app.staticTexts.matching(
            NSPredicate(format: "label == %@", "source: scene-B")
        ).firstMatch
        XCTAssertTrue(sourceB.waitForExistence(timeout: 15))
        XCTAssertTrue(sourceB.isHittable)
        attachState(app, name: "before-system-split-\(runID)")

        // Coordinates come from the current application window. A slow move
        // with a held endpoint distinguishes split placement from a Home swipe.
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.985))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.55))
        start.press(
            forDuration: 0.15,
            thenDragTo: end,
            withVelocity: .slow,
            thenHoldForDuration: 1
        )
        attachState(app, name: "after-system-split-\(runID)")
        let bothVisible = NSPredicate { _, _ in
            sourceA.exists && sourceA.isHittable && sourceB.exists && sourceB.isHittable
        }
        let result = XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: bothVisible, object: app)],
            timeout: 8
        )
        attachState(app, name: "split-result-\(runID)")
        XCTAssertEqual(
            result, .completed,
            "The required two visible native scenes were not established; this is input qualification only."
        )
        XCTAssertFalse(sourceA.frame.intersects(sourceB.frame))
    }

    private func attachState(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let hierarchy = XCTAttachment(string: app.debugDescription + "\n" + XCUIApplication(bundleIdentifier: "com.apple.springboard").debugDescription)
        hierarchy.name = name + "-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }
}
