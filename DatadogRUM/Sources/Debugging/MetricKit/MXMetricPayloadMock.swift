///*
// * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
// * This product includes software developed at Datadog (https://www.datadoghq.com/).
// * Copyright 2019-Present Datadog, Inc.
// */
//
//import Foundation
//
//#if canImport(MetricKit)
//import MetricKit
//
//public class MXMetricPayloadMock: MXMetricPayload {
//    var _latestApplicationVersion: String
//    var _includesMultipleApplicationVersions: Bool
//    var _timeStampBegin: Date
//    var _timeStampEnd: Date
//
//    public override var latestApplicationVersion: String { _latestApplicationVersion }
//    public override var includesMultipleApplicationVersions: Bool { _includesMultipleApplicationVersions }
//    public override var timeStampBegin: Date { _timeStampBegin }
//    public override var timeStampEnd: Date { _timeStampEnd }
//
//    public override var cpuMetrics: MXCPUMetric? { MXCPUMetricMock() }
//    public override var gpuMetrics: MXGPUMetric? { MXGPUMetricMock() }
//    public override var applicationTimeMetrics: MXAppRunTimeMetric? { MXAppRunTimeMetricMock() }
//    public override var locationActivityMetrics: MXLocationActivityMetric? { MXLocationActivityMetricMock() }
//    public override var networkTransferMetrics: MXNetworkTransferMetric? { MXNetworkTransferMetricMock() }
//    public override var diskIOMetrics: MXDiskIOMetric? { MXDiskIOMetricMock() }
//    public override var memoryMetrics: MXMemoryMetric? { MXMemoryMetricMock() }
//
//    public init(
//        latestApplicationVersion: String,
//        includesMultipleApplicationVersions: Bool,
//        timeStampBegin: Date,
//        timeStampEnd: Date
//    ) {
//        self._latestApplicationVersion = latestApplicationVersion
//        self._includesMultipleApplicationVersions = includesMultipleApplicationVersions
//        self._timeStampBegin = timeStampBegin
//        self._timeStampEnd = timeStampEnd
//        super.init()
//    }
//    
//    required init?(coder: NSCoder) {
//        fatalError("init(coder:) has not been implemented")
//    }
//}
//
//extension Measurement {
//    public static func random(in range: ClosedRange<Double>, unit: UnitType) -> Self {
//        Self(value: .random(in: range), unit: unit)
//    }
//}
//
//internal class MXCPUMetricMock: MXCPUMetric {
//    var _cumulativeCPUTime: Measurement<UnitDuration>
//    var _cumulativeCPUInstructions: Measurement<Unit>
//
//    override var cumulativeCPUTime: Measurement<UnitDuration> { _cumulativeCPUTime }
//    override var cumulativeCPUInstructions: Measurement<Unit> { _cumulativeCPUInstructions }
//
//    override init() {
//        _cumulativeCPUTime = .random(in: 100...130, unit: .seconds)
//        _cumulativeCPUInstructions = .random(in: 900...1_000, unit: .init(symbol: "kiloinstructions"))
//        super.init()
//    }
//    
//    required init?(coder: NSCoder) {
//        fatalError("init(coder:) has not been implemented")
//    }
//}
//
//internal class MXGPUMetricMock: MXGPUMetric {
//    var _cumulativeGPUTime: Measurement<UnitDuration>
//
//    override var cumulativeGPUTime: Measurement<UnitDuration> { _cumulativeGPUTime }
//
//    override init() {
//        _cumulativeGPUTime = .random(in: 40...60, unit: .seconds)
//        super.init()
//    }
//
//    required init?(coder: NSCoder) {
//        fatalError("init(coder:) has not been implemented")
//    }
//}
//
//internal class MXAppRunTimeMetricMock: MXAppRunTimeMetric {
//    var _cumulativeForegroundTime: Measurement<UnitDuration>
//    var _cumulativeBackgroundTime: Measurement<UnitDuration>
//    var _cumulativeBackgroundAudioTime: Measurement<UnitDuration>
//    var _cumulativeBackgroundLocationTime: Measurement<UnitDuration>
//
//    override var cumulativeForegroundTime: Measurement<UnitDuration> { _cumulativeForegroundTime }
//    override var cumulativeBackgroundTime: Measurement<UnitDuration> { _cumulativeBackgroundTime }
//    override var cumulativeBackgroundAudioTime: Measurement<UnitDuration> { _cumulativeBackgroundAudioTime }
//    override var cumulativeBackgroundLocationTime: Measurement<UnitDuration> { _cumulativeBackgroundLocationTime }
//
//    override init() {
//        _cumulativeForegroundTime = .random(in: 100...130, unit: .seconds)
//        _cumulativeBackgroundTime = .random(in: 55...60, unit: .seconds)
//        _cumulativeBackgroundAudioTime = .random(in: 0...30, unit: .seconds)
//        _cumulativeBackgroundLocationTime = .random(in: 0...30, unit: .seconds)
//        super.init()
//    }
//
//    required init?(coder: NSCoder) {
//        fatalError("init(coder:) has not been implemented")
//    }
//}
//
//internal class MXLocationActivityMetricMock: MXLocationActivityMetric {
//    var _cumulativeBestAccuracyTime: Measurement<UnitDuration>
//    var _cumulativeBestAccuracyForNavigationTime: Measurement<UnitDuration>
//    var _cumulativeNearestTenMetersAccuracyTime: Measurement<UnitDuration>
//    var _cumulativeHundredMetersAccuracyTime: Measurement<UnitDuration>
//    var _cumulativeKilometerAccuracyTime: Measurement<UnitDuration>
//    var _cumulativeThreeKilometersAccuracyTime: Measurement<UnitDuration>
//
//    override var cumulativeBestAccuracyTime: Measurement<UnitDuration> { _cumulativeBestAccuracyTime }
//    override var cumulativeBestAccuracyForNavigationTime: Measurement<UnitDuration> { _cumulativeBestAccuracyForNavigationTime }
//    override var cumulativeNearestTenMetersAccuracyTime: Measurement<UnitDuration> { _cumulativeNearestTenMetersAccuracyTime }
//    override var cumulativeHundredMetersAccuracyTime: Measurement<UnitDuration> { _cumulativeHundredMetersAccuracyTime }
//    override var cumulativeKilometerAccuracyTime: Measurement<UnitDuration> { _cumulativeKilometerAccuracyTime }
//    override var cumulativeThreeKilometersAccuracyTime: Measurement<UnitDuration> { _cumulativeThreeKilometersAccuracyTime }
//
//    override init() {
//        _cumulativeBestAccuracyTime = .random(in: 0...20, unit: .seconds)
//        _cumulativeBestAccuracyForNavigationTime = .random(in: 0...30, unit: .seconds)
//        _cumulativeNearestTenMetersAccuracyTime = .random(in: 0...30, unit: .seconds)
//        _cumulativeHundredMetersAccuracyTime = .random(in: 0...30, unit: .seconds)
//        _cumulativeKilometerAccuracyTime = .random(in: 0...20, unit: .seconds)
//        _cumulativeThreeKilometersAccuracyTime = .random(in: 0...30, unit: .seconds)
//        super.init()
//    }
//
//    required init?(coder: NSCoder) {
//        fatalError("init(coder:) has not been implemented")
//    }
//}
//
//internal class MXNetworkTransferMetricMock: MXNetworkTransferMetric {
//    var _cumulativeWifiUpload: Measurement<UnitInformationStorage>
//    var _cumulativeWifiDownload: Measurement<UnitInformationStorage>
//    var _cumulativeCellularUpload: Measurement<UnitInformationStorage>
//    var _cumulativeCellularDownload: Measurement<UnitInformationStorage>
//
//    override var cumulativeWifiUpload: Measurement<UnitInformationStorage> { _cumulativeWifiUpload }
//    override var cumulativeWifiDownload: Measurement<UnitInformationStorage> { _cumulativeWifiDownload }
//    override var cumulativeCellularUpload: Measurement<UnitInformationStorage> { _cumulativeCellularUpload }
//    override var cumulativeCellularDownload: Measurement<UnitInformationStorage> { _cumulativeCellularDownload }
//
//    override init() {
//        _cumulativeWifiUpload = .random(in: 50_000...60_000, unit: .kilobytes)
//        _cumulativeWifiDownload = .random(in: 75_000...80_000, unit: .kilobytes)
//        _cumulativeCellularUpload = .random(in: 20_000...30_000, unit: .kilobytes)
//        _cumulativeCellularDownload = .random(in: 40_000...50_000, unit: .kilobytes)
//        super.init()
//    }
//
//    required init?(coder: NSCoder) {
//        fatalError("init(coder:) has not been implemented")
//    }
//}
//
//internal class MXDiskIOMetricMock: MXDiskIOMetric {
//    var _cumulativeLogicalWrites: Measurement<UnitInformationStorage>
//
//    override var cumulativeLogicalWrites: Measurement<UnitInformationStorage> { _cumulativeLogicalWrites }
//
//    override init() {
//        _cumulativeLogicalWrites = .random(in: 600...1_300, unit: .kilobytes)
//        super.init()
//    }
//
//    required init?(coder: NSCoder) {
//        fatalError("init(coder:) has not been implemented")
//    }
//}
//
//internal class MXMemoryMetricMock: MXMemoryMetric {
//    var _peakMemoryUsage: Measurement<UnitInformationStorage>
//    var _averageSuspendedMemory: MXMemoryMetricAverageUnitInformationStorageMock
//
//    override var peakMemoryUsage: Measurement<UnitInformationStorage> { _peakMemoryUsage }
//    override var averageSuspendedMemory: MXAverage<UnitInformationStorage> { _averageSuspendedMemory }
//
//    override init() {
//        _peakMemoryUsage = .random(in: 150_000...240_000, unit: .kilobytes)
//        _averageSuspendedMemory = MXMemoryMetricAverageUnitInformationStorageMock()
//        super.init()
//    }
//
//    required init?(coder: NSCoder) {
//        fatalError("init(coder:) has not been implemented")
//    }
//}
//
//internal class MXMemoryMetricAverageUnitInformationStorageMock: MXAverage<UnitInformationStorage> {
//    var _averageMeasurement: Measurement<UnitInformationStorage>
//    var _sampleCount: Int
//    var _standardDeviation: Double
//
//    override var averageMeasurement: Measurement<UnitInformationStorage> { _averageMeasurement }
//    override var sampleCount: Int { _sampleCount }
//    override var standardDeviation: Double { _standardDeviation }
//
//    override init() {
//        _averageMeasurement = .random(in: 30_000...100_000, unit: .kilobytes)
//        _sampleCount = .random(in: 15...500)
//        _standardDeviation = 0
//        super.init()
//    }
//
//    required init?(coder: NSCoder) {
//        fatalError("init(coder:) has not been implemented")
//    }
//}
//
//
//#endif
