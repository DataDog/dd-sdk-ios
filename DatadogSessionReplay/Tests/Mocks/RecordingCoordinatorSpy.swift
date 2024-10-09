//
//  RecordingCoordinatorSpy.swift
//  Datadog
//
//  Created by Maciej Burda on 08/10/2024.
//  Copyright © 2024 Datadog. All rights reserved.
//

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
