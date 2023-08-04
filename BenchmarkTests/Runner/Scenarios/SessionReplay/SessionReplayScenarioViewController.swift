/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

internal class SessionReplayScenarioViewController: UINavigationController {
    private let fixtures: [UIViewController]
    private let changeInterval: TimeInterval
    private var current = 0

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
        keepChangingFixture()
    }

    private func keepChangingFixture() {
        DispatchQueue.main.asyncAfter(deadline: .now() + changeInterval) { [weak self] in
            guard let self = self, BenchmarkController.current?.isRunning == true else {
                return
            }
            self.current = (self.current + 1) % self.fixtures.count
            self.viewControllers = [fixtures[self.current]]
            self.keepChangingFixture()
        }
    }
}
