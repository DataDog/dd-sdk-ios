/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import SRFixtures

/// A navigation view controller for presenting SR fixtures.
/// This view controller displays SR fixtures, starting with the initial one, and includes a "NEXT" button
/// in the navigation bar that allows to navigate to successive fixtures.
class SRMultipleViewsRecordingViewController: UINavigationController, UINavigationControllerDelegate {
    private let fixtures: [Fixture] = [
        .basicShapes,
        .basicTexts,
        .segments,
        .unsupportedViews,
        .swiftUI,
        .images,
    ]
    private var currentFixture = 0

    override func viewDidLoad() {
        delegate = self
        pushNextFixture()
    }

    @objc private func pushNextFixture() {
        defer { currentFixture = (currentFixture + 1) % fixtures.count }
        let next = fixtures[currentFixture]
        pushViewController(next.instantiateViewController(), animated: true)
    }

    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        let nextButton = UIBarButtonItem(title: "NEXT", style: .plain, target: self, action: #selector(pushNextFixture))
        topViewController?.navigationItem.rightBarButtonItem = nextButton
        topViewController?.navigationItem.title = "\(fixtures[currentFixture])"
    }
}
