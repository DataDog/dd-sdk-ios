/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

/// Common interactions to several tests
internal extension ExampleApplication {
    func tapTapBar(item tabName: String) {
        tabBars.buttons[tabName].tap()
    }

    func tapView(named name: String) {
        staticTexts[name].tap()
    }

    func tapButton(titled buttonTitle: String) {
        buttons[buttonTitle].safeTap(within: 5)
    }

    func swipeDownInteraction() {
        let coordinate1 = coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.2))
        let coordinate2 = coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.8))
        coordinate1.press(forDuration: 0.5, thenDragTo: coordinate2)
    }
}
