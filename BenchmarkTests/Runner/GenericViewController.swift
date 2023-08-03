/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

internal class HeapAllocation {
    var data: Data

    init(dataSize: Int) {
        data = Data(count: dataSize)
        for i in (0..<dataSize) {
            self.data[i] = UInt8(i % 10)
        }
    }
}

var heaps: [HeapAllocation] = []

internal class GenericViewController: UIViewController {
    let droppedFramesInstrument: DroppedFramesInstrument? = nil
//    let droppedFramesInstrument: DroppedFramesInstrument? = DroppedFramesInstrument()
//    let frameDurationInstrument: FrameDurationInstrument? = FrameDurationInstrument()
    let frameDurationInstrument: FrameDurationInstrument? = nil
    let memoryUsageInstrument: MemoryUsageInstrument? = MemoryUsageInstrument()
//    let memoryUsageInstrument: MemoryUsageInstrument? = nil

    override func viewDidLoad() {
        forceSleep()
    }

    func forceSleep() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            print("⏱️😴 will sleep")
            Thread.sleep(forTimeInterval: 0.1)

            heaps.append(HeapAllocation(dataSize: 1_024 * 1_024 * 10))

            self.forceSleep()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        droppedFramesInstrument?.start()
        frameDurationInstrument?.start()
        memoryUsageInstrument?.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        droppedFramesInstrument?.stop()
        frameDurationInstrument?.stop()
        memoryUsageInstrument?.stop()
    }
}
