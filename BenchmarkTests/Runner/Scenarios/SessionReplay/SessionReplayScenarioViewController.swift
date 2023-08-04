/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

internal class SessionReplayScenarioViewController: UINavigationController {
    private let fixtures: [UIViewController]
    private let changeInterval: TimeInterval
    private var schedule: Schedule!
    private var current = 0

    /// Called once, after all fixtures were loaded and displayed.
    var onceAfterAllFixturesLoaded: (() -> Void)? = nil

    init(fixtureViewControllers: [UIViewController], fixtureChangeInterval: TimeInterval) {
        self.fixtures = fixtureViewControllers
        self.changeInterval = fixtureChangeInterval
        super.init(rootViewController: fixtureViewControllers[0])
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        schedule = Schedule(interval: changeInterval, operation: { [weak self] in
            self?.changeFixture()
        })
    }

    private func changeFixture() {
        if (current + 1) >= fixtures.count && onceAfterAllFixturesLoaded != nil {
            onceAfterAllFixturesLoaded?()
            onceAfterAllFixturesLoaded = nil
        }

        current = (current + 1) % fixtures.count
        self.viewControllers = [fixtures[current]]
    }
}
