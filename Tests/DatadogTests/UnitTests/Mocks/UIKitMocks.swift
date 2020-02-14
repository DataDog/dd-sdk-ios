#if canImport(UIKit)
import UIKit

/*
A collection of mocks for different `UIKit` types.
It follows the mocking conventions described in `FoundationMocks.swift`.
 */

extension UIDevice.BatteryState {
    static func mockAny() -> UIDevice.BatteryState {
        return .full
    }
}

class UIDeviceMock: UIDevice {
    private var _model: String
    private var _systemName: String
    private var _systemVersion: String
    private var _isBatteryMonitoringEnabled: Bool
    private var _batteryState: UIDevice.BatteryState
    private var _batteryLevel: Float

    init(
        model: String = .mockAny(),
        systemName: String = .mockAny(),
        systemVersion: String = .mockAny(),
        isBatteryMonitoringEnabled: Bool = .mockAny(),
        batteryState: UIDevice.BatteryState = .mockAny(),
        batteryLevel: Float = .mockAny()
    ) {
        self._model = model
        self._systemName = systemName
        self._systemVersion = systemVersion
        self._isBatteryMonitoringEnabled = isBatteryMonitoringEnabled
        self._batteryState = batteryState
        self._batteryLevel = batteryLevel
    }

    override var model: String { _model }
    override var systemName: String { _systemName }
    override var systemVersion: String { "mock system version" }
    override var isBatteryMonitoringEnabled: Bool {
        get { _isBatteryMonitoringEnabled }
        set { _isBatteryMonitoringEnabled = newValue }
    }
    override var batteryState: UIDevice.BatteryState { _batteryState }
    override var batteryLevel: Float { _batteryLevel }
}

#endif
