/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import HTTPServerMock
import XCTest

private extension ExampleApplication {
    func tapButton(titled buttonTitle: String) {
        buttons[buttonTitle].tap()
    }

    func swipeToPullModalDown() {
        let coordinate1 = coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.25))
        let coordinate2 = coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.75))
        coordinate1.press(forDuration: 0.3, thenDragTo: coordinate2)
    }

    func swipeToPullModalDownButThenCancel() {
        let coordinate1 = coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.25))
        let coordinate2 = coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.35))
        coordinate1.press(forDuration: 0.3, thenDragTo: coordinate2)
    }
}

class RUMModalViewsScenarioTests: IntegrationTests {
    func testRUMModalViewsScenario() throws {
        let app = ExampleApplication()
        app.launchWith(
            testScenario: RUMModalViewsAutoInstrumentationScenario.self,
            serverConfiguration: HTTPServerMockConfiguration()
        ) // start on "Screen1"

        app.tapButton(titled: "Present modally using segue") // go to modal "Screen2"
        app.tapButton(titled: "Dismiss by self.dismiss()") // dismiss to "Screen1"
        app.tapButton(titled: "Present modally from code") // go to modal "Screen2"
        app.tapButton(titled: "Dismiss by parent.dismiss()") // dismiss to "Screen1"
        app.tapButton(titled: "Present modally using segue") // go to modal "Screen2"
        app.swipeToPullModalDown() // interactive dismiss to "Screen1"
        app.tapButton(titled: "Present modally from code") // go to modal "Screen2"
        app.swipeToPullModalDownButThenCancel() // interactive and cancelled dismiss, stay on "Screen2"
    }
}
