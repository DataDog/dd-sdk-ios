/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import TestUtilities

/*
A collection of mocks for different `UIKit` types.
It follows the mocking conventions described in `FoundationMocks.swift`.
 */

#if !os(tvOS)
extension UIDevice.BatteryState {
    static func mockAny() -> UIDevice.BatteryState {
        return .full
    }
}
#endif

class UIDeviceMock: UIDevice {
    override var model: String { _model }
    override var systemName: String { _systemName }
    override var systemVersion: String { _systemVersion }

    private var _model: String
    private var _systemName: String
    private var _systemVersion: String

    #if os(tvOS)
    init(
        model: String = .mockAny(),
        systemName: String = .mockAny(),
        systemVersion: String = .mockAny()
    ) {
        self._model = model
        self._systemName = systemName
        self._systemVersion = systemVersion
    }
    #else
    override var isBatteryMonitoringEnabled: Bool {
        get { _isBatteryMonitoringEnabled }
        set { _isBatteryMonitoringEnabled = newValue }
    }

    override var batteryState: UIDevice.BatteryState {
        get { _batteryState }
        set { _batteryState = newValue }
    }

    override var batteryLevel: Float {
        get { _batteryLevel }
        set { _batteryLevel = newValue }
    }

    private var _isBatteryMonitoringEnabled: Bool
    private var _batteryLevel: Float
    private var _batteryState: UIDevice.BatteryState

    init(
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

extension UIEvent {
    static func mockAnyTouch() -> UIEvent {
        return .mockWith(touches: [.mockAny()])
    }

    static func mockAnyPress() -> UIEvent {
        return .mockWith(touches: [.mockAny()])
    }

    static func mockWith(touch: UITouch) -> UIEvent {
        return UIEventMock(allTouches: [touch])
    }

    static func mockWith(touches: Set<UITouch>?) -> UIEvent {
        return UIEventMock(allTouches: touches)
    }

    static func mockWith(press: UIPress) -> UIPressesEvent {
        return UIPressesEventMock(allPresses: [press])
    }

    static func mockWith(presses: Set<UIPress>) -> UIPressesEvent {
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
    static func mockAny() -> UITouch {
        return mockWith(view: UIView())
    }

    static func mockWith(
        phase: UITouch.Phase = .ended,
        view: UIView? = .init()
    ) -> UITouch {
        return UITouchMock(phase: phase, view: view)
    }
}

extension UIPress {
    static func mockAny() -> UIPress {
        return mockWith(type: .select, view: UIView())
    }

    static func mockWith(
        phase: UIPress.Phase = .ended,
        type: UIPress.PressType = .select,
        view: UIView? = .init()
    ) -> UIPress {
        return UIPressMock(phase: phase, type: type, view: view)
    }
}

private class UITouchMock: UITouch {
    private let _phase: UITouch.Phase
    private let _view: UIView?

    fileprivate init(phase: UITouch.Phase, view: UIView?) {
        _phase = phase
        _view = view
    }

    override var phase: UITouch.Phase { _phase }
    override var view: UIView? { _view }
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
