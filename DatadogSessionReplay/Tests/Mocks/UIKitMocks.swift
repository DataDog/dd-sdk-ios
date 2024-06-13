/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
@testable import TestUtilities

extension UIColor: AnyMockable, RandomMockable {
    public static func mockAny() -> Self {
        return UIColor.green as! Self
    }

    public static func mockRandom() -> Self {
        return mockRandomWith(alpha: .mockRandom(min: 0, max: 1))
    }

    static func mockRandomWith(alpha: CGFloat) -> Self {
        return UIColor(
            red: .mockRandom(min: 0, max: 1),
            green: .mockRandom(min: 0, max: 1),
            blue: .mockRandom(min: 0, max: 1),
            alpha: alpha
        ) as! Self
    }
}

extension UIView: AnyMockable, RandomMockable {
    public static func mockAny() -> Self {
        return UIView(frame: .init(x: 0, y: 0, width: 200, height: 400)) as! Self
    }

    public static func mockRandom() -> Self {
        let view = UIView(frame: .mockRandom())
        view.backgroundColor = .mockRandom()
        view.layer.borderColor = .mockRandom()
        view.layer.backgroundColor = .mockRandom()
        view.layer.cornerRadius = .mockRandom(min: 0, max: 5)
        view.alpha = .mockRandom(min: 0, max: 1)
        view.isHidden = .random()
        return view as! Self
    }
}

class UITouchMock: UITouch {
    var _phase: UITouch.Phase
    var _location: CGPoint

    init(phase: UITouch.Phase = .began, location: CGPoint = .zero) {
        self._phase = phase
        self._location = location
    }

    override var phase: UITouch.Phase {
        get { _phase }
        set { _phase = newValue }
    }

    override func location(in view: UIView?) -> CGPoint {
        return _location
    }
}

class UITouchEventMock: UIEvent {
    var _touches: Set<UITouchMock>

    init(touches: [UITouchMock] = []) {
        self._touches = Set(touches)
    }

    override var type: UIEvent.EventType { .touches }

    override func touches(for window: UIWindow) -> Set<UITouch>? {
        return _touches
    }
}

extension UIView.ContentMode {
    static func mockRandom() -> UIView.ContentMode {
        UIView.ContentMode(rawValue: Int.random(in: 0...12)) ?? .scaleToFill
    }
}

extension UITextContentType: RandomMockable {
    static var allCases: Set<UITextContentType> {
        var all: Set<UITextContentType> = [
            .name, .namePrefix, .givenName, .middleName, .familyName, .nameSuffix, .nickname,
            .jobTitle, .organizationName, .location, .fullStreetAddress, .streetAddressLine1,
            .streetAddressLine2, .addressCity, .addressState, .addressCityAndState, .sublocality,
            .countryName, .postalCode, .telephoneNumber, .emailAddress, .URL, .creditCardNumber,
            .username, .password,
            .newPassword,
            .oneTimeCode,
        ]

        if #available(iOS 15.0, tvOS 15.0, *) {
            all.formUnion([.shipmentTrackingNumber, .flightNumber, .dateTime])
        }

        return all
    }

    public static func mockRandom() -> UITextContentType { allCases.randomElement()! }
}

extension UIImage: RandomMockable {
    /// Creates bitmap by randomising the value of each pixel.
    public static func mockRandom() -> Self {
        return mockRandom(width: .mockRandom(min: 10, max: 100), height: .mockRandom(min: 10, max: 100))
    }

    /// Creates bitmap of certain size by randomising the value of each pixel.
    public static func mockRandom(width: Int, height: Int) -> Self {
        let bytesPerPixel: Int = 4
        let bitsPerComponent: Int = 8
        let bytesPerRow = bytesPerPixel * width
        let totalBytes = bytesPerRow * height
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        var bitmapBytes = [UInt8].mockRandom(count: totalBytes)
        let bitmapData = Data(bytes: &bitmapBytes, count: totalBytes)

        let bitmapContext = CGContext(
            data: UnsafeMutableRawPointer(mutating: (bitmapData as NSData).bytes),
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
        let cgImage = bitmapContext!.makeImage()!
        return UIImage(cgImage: cgImage) as! Self
    }
}
