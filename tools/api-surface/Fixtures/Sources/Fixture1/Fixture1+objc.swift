/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

/// ObjC APIs for Fixture1 used in `api-surface` tests.

import Foundation

@objc(DDObjcCar)
@objcMembers
@_spi(objc)
public class objc_Car: NSObject {
    @objc
    public enum Manufacturer: Int {
        case manufacturer1
        case manufacturer2
        case manufacturer3
    }

    internal let swiftCar: Car

    public init(manufacturer: Manufacturer) {
        let swiftManufacturer: Car.Manufacturer
        switch manufacturer {
        case .manufacturer1: swiftManufacturer = .manufacturer1
        case .manufacturer2: swiftManufacturer = .manufacturer2
        case .manufacturer3: swiftManufacturer = .manufacturer3
        @unknown default: swiftManufacturer = .manufacturer1
        }
        self.swiftCar = Car(manufacturer: swiftManufacturer)
    }

    public func startEngine() -> Bool {
        swiftCar.startEngine()
    }

    public func stopEngine() -> Bool {
        swiftCar.stopEngine()
    }

    public var price: Int {
        swiftCar.price
    }
}

@objc(DDCarDelegate)
@_spi(objc)
public protocol objc_CarDelegate: AnyObject {
    func carDidStart(_ car: objc_Car)
    func carDidStop(_ car: objc_Car)
}

@objc(DDCarConfiguration)
@objcMembers
@_spi(objc)
public class objc_CarConfiguration: NSObject {
    public var maxPrice: Int

    public init(maxPrice: Int) {
        self.maxPrice = maxPrice
    }

    public func setDelegate(_ delegate: objc_CarDelegate?) {
        // Configure delegate
    }
}
