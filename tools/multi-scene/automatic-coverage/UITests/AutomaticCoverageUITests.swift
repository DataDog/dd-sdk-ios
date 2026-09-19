import XCTest

@MainActor final class AutomaticCoverageUITests: XCTestCase {
    private var receipts: [[String: Any]] = []
    private var runID: String { ProcessInfo.processInfo.environment["EXP195_RUN_ID"] ?? "missing" }
    private var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(runID)
    }
    private func record(_ phase: String, _ payload: [String: Any] = [:]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        receipts.append(["run_id": runID, "phase": phase, "timestamp": Date().timeIntervalSince1970, "payload": payload])
        try JSONSerialization.data(withJSONObject: receipts, options: [.sortedKeys])
            .write(to: directory.appendingPathComponent("receipts.json"), options: .atomic)
    }
    private func wait(_ message: String, timeout: TimeInterval = 15, _ condition: @escaping () -> Bool) {
        let e = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [e], timeout: timeout), .completed, message)
    }
    private func captureWindow() {
        // A fixed measurement window deliberately allows automatic-action timeout
        // and view updates to settle. Input readiness is asserted separately.
        let end = Date().addingTimeInterval(1.2)
        wait("observation window", timeout: 4) { Date() >= end }
    }
    private func visible(_ app: XCUIApplication, _ screen: String) {
        wait("visible native " + screen) {
            let e = app.staticTexts["screen." + screen]
            return e.exists && e.isHittable
        }
    }
    private func tap(_ app: XCUIApplication, _ id: String, phase: String) throws {
        let button = app.buttons[id]
        wait("hittable " + id) { button.exists && button.isHittable }
        try record(phase + ".before", ["target": id, "frame": String(describing: button.frame)])
        button.tap()
        try record(phase + ".delivered", ["target": id])
        captureWindow()
    }
    private func interact(_ app: XCUIApplication, _ screen: String, phase: String) throws {
        visible(app, screen)
        let receipt = app.staticTexts[screen + ".receipt"]
        let old = receipt.label
        try tap(app, screen + ".tap", phase: phase + ".tap")
        wait("tap had native effect") { receipt.label != old }
        try record(phase + ".tap.effect", ["receipt": receipt.label])
        let toggle = app.switches[screen + ".toggle"]
        wait("toggle hittable") { toggle.exists && toggle.isHittable }
        let oldToggle = toggle.value as? String
        try record(phase + ".toggle.before", ["target": screen + ".toggle"])
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        wait("toggle changed") { toggle.value as? String != oldToggle }
        try record(phase + ".toggle.effect", ["value": toggle.value as? String ?? "missing"])
        captureWindow()
        let scroll = app.scrollViews[screen + ".scroll"]
        wait("scroll hittable") { scroll.exists && scroll.isHittable }
        let before = scroll.staticTexts["Row 0"].frame
        try record(phase + ".scroll.before", ["frame": String(describing: before)])
        scroll.swipeUp(velocity: .slow)
        wait("scroll content moved") { scroll.staticTexts["Row 0"].frame != before }
        try record(phase + ".scroll.effect", ["frame": String(describing: scroll.staticTexts["Row 0"].frame)])
        captureWindow()
    }
    private func flow(_ app: XCUIApplication, layout: String, phase: String) throws {
        let root = layout == "split" ? "sidebar" : "home"
        try interact(app, root, phase: phase + ".root")
        try tap(app, root + ".next", phase: phase + ".navigate")
        visible(app, "detail"); try record(phase + ".navigate.effect")
        try interact(app, "detail", phase: phase + ".detail")
        try tap(app, "detail.sheet", phase: phase + ".present")
        visible(app, "sheet"); try record(phase + ".present.effect")
        try tap(app, "sheet.tap", phase: phase + ".sheet.tap")
        XCTAssertEqual(app.staticTexts["sheet.receipt"].label, "receipt:1")
        try tap(app, "sheet.close", phase: phase + ".dismiss")
        visible(app, "detail"); try record(phase + ".dismiss.effect")
        try tap(app, "detail.tap", phase: phase + ".detail.return.tap")
        try tap(app, "detail.back", phase: phase + ".back")
        visible(app, root); try record(phase + ".back.effect")
        try tap(app, root + ".tap", phase: phase + ".root.return.tap")
    }
    private func poseBoundary(_ app: XCUIApplication, name: String) throws {
        try record("await-" + name, ["frame": String(describing: app.windows.firstMatch.frame)])
        let path = directory.appendingPathComponent(name + ".json")
        wait("external qualified " + name, timeout: 180) { FileManager.default.fileExists(atPath: path.path) }
        let payload = try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as! [String: Any]
        XCTAssertEqual(payload["run_id"] as? String, runID)
        try record("received-" + name, payload)
    }
    private func run(_ framework: String, layout: String) throws {
        continueAfterFailure = false
        XCTAssertNotEqual(runID, "missing")
        let prefix = ProcessInfo.processInfo.environment["EXP195_BUNDLE_PREFIX"]!
        let app = XCUIApplication(bundleIdentifier: prefix + "." + framework.lowercased())
        app.launchArguments = ["--run-id", runID, "--layout", layout]
        try record("launch", ["framework": framework, "layout": layout])
        app.launch()
        defer { app.terminate(); try? record("terminated") }
        try flow(app, layout: layout, phase: "initial")
        if ProcessInfo.processInfo.environment["EXP195_DUO_PHASES"] == "1" {
            try poseBoundary(app, name: "open")
            try flow(app, layout: layout, phase: "inner")
            let root = layout == "split" ? "sidebar" : "home"
            try tap(app, root + ".next", phase: "stable.navigate")
            visible(app, "detail")
            try poseBoundary(app, name: "close")
            visible(app, "detail"); try tap(app, "detail.tap", phase: "closed.detail.tap")
            try poseBoundary(app, name: "reopen")
            visible(app, "detail"); try tap(app, "detail.tap", phase: "reopened.detail.tap")
        }
        try record("background.before")
        XCUIDevice.shared.press(.home)
        wait("actual app background") { app.state == .runningBackground || app.state == .runningBackgroundSuspended }
        try record("background.effect")
        captureWindow()
        try record("complete")
    }
    func testUIKitStack() throws { try run("UIKit", layout: "stack") }
    func testUIKitSplit() throws { try run("UIKit", layout: "split") }
    func testSwiftUIStack() throws { try run("SwiftUI", layout: "stack") }
    func testSwiftUISplit() throws { try run("SwiftUI", layout: "split") }
}
