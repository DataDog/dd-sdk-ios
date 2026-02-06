/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */


import UIKit

#if os(watchOS)

import WatchKit

public class UIDeviceMock: WKInterfaceDevice {
    override public var model: String { _model }
    override public var systemName: String { _systemName }
    override public var systemVersion: String { _systemVersion }

    private var _model: String
    private var _systemName: String
    private var _systemVersion: String

    public init(
        model: String = .mockAny(),
        systemName: String = .mockAny(),
        systemVersion: String = .mockAny()
    ) {
        self._model = model
        self._systemName = systemName
        self._systemVersion = systemVersion
    }
}

#else

public class UIDeviceMock: UIDevice {
    override public var model: String { _model }
    override public var systemName: String { _systemName }
    override public var systemVersion: String { _systemVersion }

    private var _model: String
    private var _systemName: String
    private var _systemVersion: String

    #if os(tvOS)
    public init(
        model: String = .mockAny(),
        systemName: String = .mockAny(),
        systemVersion: String = .mockAny()
    ) {
        self._model = model
        self._systemName = systemName
        self._systemVersion = systemVersion
    }
    #else
    override public var isBatteryMonitoringEnabled: Bool {
        get { _isBatteryMonitoringEnabled }
        set { _isBatteryMonitoringEnabled = newValue }
    }

    override public var batteryState: UIDevice.BatteryState {
        get { _batteryState }
        set { _batteryState = newValue }
    }

    override public var batteryLevel: Float {
        get { _batteryLevel }
        set { _batteryLevel = newValue }
    }

    private var _isBatteryMonitoringEnabled: Bool
    private var _batteryLevel: Float
    private var _batteryState: UIDevice.BatteryState

    public init(
        model: String = .mockAny(),
        systemName: String = .mockAny(),
        systemVersion: String = .mockAny(),
        isBatteryMonitoringEnabled: Bool = .mockAny(),
        batteryLevel: Float = .mockAny(),
        batteryState: UIDevice.BatteryState = .mockAny()
    ) {
        self._model = model
        self._systemName = systemName
        self._systemVersion = systemVersion
        self._isBatteryMonitoringEnabled = isBatteryMonitoringEnabled
        self._batteryState = batteryState
        self._batteryLevel = batteryLevel
    }
    #endif
}

#if os(iOS)
public class UIScreenMock: UIScreen {
    private var _brightness: CGFloat

    public init(brightness: CGFloat = 0.5) {
        self._brightness = brightness
    }

    override public var brightness: CGFloat {
        get { _brightness }
        set { _brightness = newValue }
    }
}
#endif

#if !os(tvOS)
extension UIDevice.BatteryState: AnyMockable {
    public static func mockAny() -> UIDevice.BatteryState {
        return .full
    }
}
#endif

extension UIEvent {
    public static func mockAnyTouch() -> UIEvent {
        return .mockWith(touches: [.mockAny()])
    }

    public static func mockAnyPress() -> UIEvent {
        return .mockWith(touches: [.mockAny()])
    }

    public static func mockWith(touch: UITouch) -> UIEvent {
        return UIEventMock(allTouches: [touch])
    }

    public static func mockWith(touches: Set<UITouch>?) -> UIEvent {
        return UIEventMock(allTouches: touches)
    }

    public static func mockWith(press: UIPress) -> UIPressesEvent {
        return UIPressesEventMock(allPresses: [press])
    }

    public static func mockWith(presses: Set<UIPress>) -> UIPressesEvent {
        return UIPressesEventMock(allPresses: presses)
    }
}

private class UIEventMock: UIEvent {
    private let _allTouches: Set<UITouch>?

    fileprivate init(allTouches: Set<UITouch>?) {
        _allTouches = allTouches
    }

    override var allTouches: Set<UITouch>? { _allTouches }
}

private class UIPressesEventMock: UIPressesEvent {
    private let _allPresses: Set<UIPress>

    fileprivate init(allPresses: Set<UIPress> = []) {
        _allPresses = allPresses
    }

    override var allPresses: Set<UIPress> { _allPresses }
}

extension UITouch {
    public static func mockAny() -> UITouch {
        return mockWith(view: UIView())
    }

    public static func mockWith(
        phase: UITouch.Phase = .ended,
        view: UIView = .init()
    ) -> UITouch {
        return UITouchMock(phase: phase, view: view)
    }
}

extension UIPress {
    public static func mockAny() -> UIPress {
        return mockWith(type: .select, view: UIView())
    }

    public static func mockWith(
        phase: UIPress.Phase = .ended,
        type: UIPress.PressType = .select,
        view: UIView? = .init()
    ) -> UIPress {
        return UIPressMock(phase: phase, type: type, view: view)
    }
}

public class UITouchMock: UITouch {
    var _phase: UITouch.Phase
    var _location: CGPoint
    var _mockedView: UIView

    public init(phase: UITouch.Phase = .began, location: CGPoint = .zero, view: UIView = UIView()) {
        self._phase = phase
        self._location = location
        self._mockedView = view
    }

    override public var phase: UITouch.Phase {
        get { _phase }
        set { _phase = newValue }
    }

    override public func location(in view: UIView?) -> CGPoint {
        return _location
    }

    override public var view: UIView {
        return _mockedView
    }
}

private class UIPressMock: UIPress {
    private let _phase: UIPress.Phase
    private let _type: UIPress.PressType
    private let _view: UIView?

    fileprivate init(phase: UIPress.Phase, type: UIPress.PressType, view: UIView?) {
        _phase = phase
        _type = type
        _view = view
    }

    override var phase: UIPress.Phase { _phase }
    override var type: UIPress.PressType { _type }
    override var responder: UIResponder? { _view }
}

extension UIApplication.State: AnyMockable, RandomMockable {
    public static func mockAny() -> UIApplication.State {
        return .active
    }

    public static func mockRandom() -> UIApplication.State {
        return [.active, .inactive, .background].randomElement()!
    }
}

extension UIColor: AnyMockable, RandomMockable {
    public static func mockAny() -> Self {
        return UIColor.green as! Self
    }

    public static func mockRandom() -> Self {
        return mockRandomWith(alpha: .mockRandom(min: 0, max: 1))
    }

    public static func mockRandomWith(alpha: CGFloat) -> Self {
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
        return .init(frame: .init(x: 0, y: 0, width: 200, height: 400))
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

public class UITouchEventMock: UIEvent {
    public var _touches: Set<UITouchMock>

    public init(touches: [UITouchMock] = []) {
        self._touches = Set(touches)
    }

    override public var type: UIEvent.EventType { .touches }

    override public func touches(for window: UIWindow) -> Set<UITouch>? {
        return _touches
    }
}

extension UIView.ContentMode {
    public static func mockRandom() -> UIView.ContentMode {
        UIView.ContentMode(rawValue: Int.random(in: 0...12)) ?? .scaleToFill
    }
}

extension UITextContentType: RandomMockable {
    public static var allCases: Set<UITextContentType> {
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

        var bitmapBytes = [UInt8].mockRandom(count: totalBytes)

        let bitmapContext = CGContext(
            data: &bitmapBytes,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        let cgImage = bitmapContext!.makeImage()!
        return UIImage(cgImage: cgImage) as! Self
    }
}

#endif
