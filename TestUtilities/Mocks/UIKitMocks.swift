/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(UIKit)
import UIKit

public class UIDeviceMock: UIDevice {
    public override var model: String { _model }
    public override var systemName: String { _systemName }
    public override var systemVersion: String { _systemVersion }

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
    public override var isBatteryMonitoringEnabled: Bool {
        get { _isBatteryMonitoringEnabled }
        set { _isBatteryMonitoringEnabled = newValue }
    }

    public override var batteryState: UIDevice.BatteryState {
        get { _batteryState }
        set { _batteryState = newValue }
    }

    public override var batteryLevel: Float {
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


#if !os(tvOS)
extension UIDevice.BatteryState: AnyMockable {
    public static func mockAny() -> UIDevice.BatteryState {
        return .full
    }
}
#endif

#endif
