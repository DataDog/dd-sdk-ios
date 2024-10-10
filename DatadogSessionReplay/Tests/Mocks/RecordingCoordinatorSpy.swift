/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
@testable import DatadogSessionReplay

class RecordingCoordinatorSpy: RecordingCoordinating {
    var startRecordingStub = true

    var startRecordingCalledCount = 0
    var stopRecordingCalledCount = 0
    var captureNextRecordCalledCount = 0

    func startRecording() -> Bool {
        startRecordingCalledCount += 1
        return startRecordingStub
    }

    func stopRecording() {
        stopRecordingCalledCount += 1
    }

    func captureNextRecord() {
        captureNextRecordCalledCount += 1
    }
}
#endif
