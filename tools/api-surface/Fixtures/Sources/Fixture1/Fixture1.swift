/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

/// A fixture file used in `api-surface` tests.

import Foundation

public class Car {
    public enum Manufacturer: String {
        case manufacturer1
        case manufacturer2
        case manufacturer3
    }

    private let engine = Engine()

    public init(
        manufacturer: Manufacturer
    ) {}

    public func startEngine() -> Bool { engine.start() }
    public func stopEngine() -> Bool { engine.stop() }
}

internal struct Engine {
    func start() -> Bool { true }
    func stop() -> Bool { true }
}

public extension Car {
    var price: Int { 100 }
}
