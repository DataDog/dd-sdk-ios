/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Randomly picks and executes one of provided effects.
@discardableResult
public func oneOf<T>(_ effects: [() -> T]) -> T {
    guard let randomEffect = effects.randomElement() else {
        preconditionFailure("At least one effect must be specified")
    }
    return randomEffect()
}

/// Randomly picks and executes one or more of provided effects.
public func oneOrMoreOf(_ effects: [() -> Void]) {
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
