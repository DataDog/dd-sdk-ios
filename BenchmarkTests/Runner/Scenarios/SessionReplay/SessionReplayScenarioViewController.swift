/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

private var currentFixtureIndex = 0

private func nextFixture() -> Fixture {
    currentFixtureIndex = (currentFixtureIndex + 1) % Fixture.allCases.count
    return Fixture.allCases[currentFixtureIndex]
}

private func currentFixture() -> Fixture {
    Fixture.allCases[currentFixtureIndex]
}

internal class SessionReplayScenarioViewController: UINavigationController {
    private let fixtureChangeInterval: TimeInterval

    init(fixtureChangeInterval: TimeInterval) {
        currentFixtureIndex = 0
        self.fixtureChangeInterval = fixtureChangeInterval
        super.init(rootViewController: currentFixture().instantiateViewController())
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        keepChangingFixture()
    }

    private func keepChangingFixture() {
        DispatchQueue.main.asyncAfter(deadline: .now() + fixtureChangeInterval) { [weak self] in
            if BenchmarkController.current?.isRunning == true {
                let fixture = nextFixture()
                self?.viewControllers = [fixture.instantiateViewController()]
                self?.keepChangingFixture()
            }
        }
    }
}
