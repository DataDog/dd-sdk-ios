import XCTest

class iOS_app_example_spm_UITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testAppCanBeLaunched() {
        let app = XCUIApplication()
        app.launch()
    }
}
