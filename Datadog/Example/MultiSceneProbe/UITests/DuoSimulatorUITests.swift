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
    private var checkpoints: [[String: String]] = []

    private var artifactDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DuoInput")
    }

    private func checkpoint(_ stage: String, runID: String) throws {
        try FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)
        checkpoints.append([
            "runID": runID,
            "stage": stage,
            "timestamp": String(Date().timeIntervalSince1970)
        ])
        let data = try JSONSerialization.data(withJSONObject: checkpoints, options: [.sortedKeys])
        try data.write(to: artifactDirectory.appendingPathComponent("checkpoints.json"), options: .atomic)
    }
    func testInnerDisplaySplitViewInput() throws {
        continueAfterFailure = false
        // Device Hub establishes the pose; forcing orientation can transform
        // injected coordinates independently from the active Duo display.
        let app = XCUIApplication()
        let runID = UUID().uuidString.lowercased()
        app.launchArguments = [
            "--probe-scenario", "interactive.manual",
            "--probe-run-id", runID, "--probe-run-mode", "clean"
        ]
        app.launchEnvironment["DD_PROBE_CAPTURE_JSONL"] = "1"
        try checkpoint("launch", runID: runID)
        app.launch()
        defer {
            try? checkpoint("terminate", runID: runID)
            app.terminate()
            try? checkpoint("terminated", runID: runID)
        }

        let sourceA = app.staticTexts.matching(
            NSPredicate(format: "label == %@", "source: scene-A")
        ).firstMatch
        XCTAssertTrue(sourceA.waitForExistence(timeout: 15))
        try attachState(app, name: "before-open-b-\(runID)")
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
        try attachState(app, name: "before-system-split-\(runID)")

        // Coordinates come from the current application window. A slow move
        // with a held endpoint distinguishes split placement from a Home swipe.
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.985))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.55))
        try checkpoint("drag-start window=\(window.frame) start=\(start.screenPoint) end=\(end.screenPoint)", runID: runID)
        start.press(
            forDuration: 0.15,
            thenDragTo: end,
            withVelocity: .slow,
            thenHoldForDuration: 1
        )
        try checkpoint("drag-returned", runID: runID)
        try attachState(app, name: "after-system-split-\(runID)")
        let bothVisible = NSPredicate { _, _ in
            sourceA.exists && sourceA.isHittable && sourceB.exists && sourceB.isHittable
        }
        let result = XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: bothVisible, object: app)],
            timeout: 8
        )
        try attachState(app, name: "split-result-\(runID)")
        XCTAssertEqual(
            result, .completed,
            "The required two visible native scenes were not established; this is input qualification only."
        )
        XCTAssertFalse(sourceA.frame.intersects(sourceB.frame))
    }

    /// The host collector owns phase admission; the runner only delivers native controls.
    func testAdaptiveResizePrefix() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let runID = UUID().uuidString.lowercased()
        let controlDirectory = artifactDirectory.appendingPathComponent(runID)
        try FileManager.default.createDirectory(at: controlDirectory, withIntermediateDirectories: true)
        let identity = try JSONSerialization.data(withJSONObject: [
            "runID": runID,
            "scenario": "swiftui.split.adaptive-resize",
            "createdAt": String(Date().timeIntervalSince1970)
        ], options: [.sortedKeys])
        try identity.write(to: artifactDirectory.appendingPathComponent("active-run.json"), options: .atomic)
        app.launchArguments = [
            "--probe-scenario", "swiftui.split.adaptive-resize",
            "--probe-run-id", runID, "--probe-run-mode", "clean"
        ]
        app.launchEnvironment["DD_PROBE_CAPTURE_JSONL"] = "1"
        try checkpoint("adaptive-launch", runID: runID)
        app.launch()
        defer {
            try? checkpoint("adaptive-terminate", runID: runID)
            app.terminate()
            try? checkpoint("adaptive-terminated", runID: runID)
        }
        XCTAssertTrue(app.staticTexts["accepted generation: 0"].waitForExistence(timeout: 15))
        try checkpoint("adaptive-ready", runID: runID)
        try waitForControl("marker-1", runID: runID, directory: controlDirectory)
        try tapAdaptiveMarker(app)
        try checkpoint("adaptive-marker-1-delivered", runID: runID)

        try waitForControl("select-detail", runID: runID, directory: controlDirectory)
        let sidebar = app.buttons["Show Sidebar"]
        if sidebar.exists && sidebar.isHittable { sidebar.tap() }
        let detail = app.buttons["Detail 1"]
        XCTAssertTrue(detail.waitForExistence(timeout: 10))
        XCTAssertTrue(detail.isHittable)
        detail.tap()
        XCTAssertTrue(app.staticTexts["accepted generation: 1"].waitForExistence(timeout: 10))
        try checkpoint("adaptive-detail-1-selected", runID: runID)
        try waitForControl("marker-2", runID: runID, directory: controlDirectory)
        try tapAdaptiveMarker(app)
        try checkpoint("adaptive-marker-2-delivered", runID: runID)

        // Keep the process alive through the externally measured resize and backend checks.
        try waitForControl("finish", runID: runID, directory: controlDirectory)
        try checkpoint("adaptive-acceptance-exported", runID: runID)
    }

    private func tapAdaptiveMarker(_ app: XCUIApplication) throws {
        let candidates = app.buttons.matching(NSPredicate(format: "label == %@", "Emit adaptive marker"))
        let marker = try XCTUnwrap(candidates.allElementsBoundByIndex.first { $0.isHittable })
        marker.tap()
    }

    private func waitForControl(_ command: String, runID: String, directory: URL) throws {
        let path = directory.appendingPathComponent(command + ".json")
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in FileManager.default.fileExists(atPath: path.path) },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 600), .completed)
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: String]
        )
        XCTAssertEqual(payload["runID"], runID)
        XCTAssertEqual(payload["command"], command)
        try checkpoint("adaptive-control-" + command, runID: runID)
    }

    private func attachState(_ app: XCUIApplication, name: String) throws {
        let capture = XCUIScreen.main.screenshot()
        let screenshot = XCTAttachment(screenshot: capture)
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let screenshotURL = artifactDirectory.appendingPathComponent(name + ".png")
        try capture.pngRepresentation.write(to: screenshotURL)
        let description = app.debugDescription
        try description.write(to: artifactDirectory.appendingPathComponent(name + ".txt"), atomically: true, encoding: .utf8)
        let hierarchy = XCTAttachment(string: description)
        hierarchy.name = name + "-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }
}
