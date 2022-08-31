/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest

extension XCTestCase {
    /// Randomly picks and executes one of provided effects.
    func oneOf(_ effects: [() -> Void]) {
        guard let randomEffect = effects.randomElement() else {
            return
        }
        randomEffect()
    }

    /// Randomly picks and executes one or more of provided effects.
    func oneOrMoreOf(_ effects: [() -> Void]) {
        guard effects.count > 1 else {
            effects.first?()
            return
        }

        let randomNumberOfEffects: Int = .random(in: (1..<effects.count))
        let randomEffects = effects.shuffled()[0..<randomNumberOfEffects]
        randomEffects.forEach { randomEffect in
            randomEffect()
        }
    }
}
