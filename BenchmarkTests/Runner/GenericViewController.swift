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

internal class GenericViewController: UIViewController {
    var heaps: [HeapAllocation] = []

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        allocateMemory()
    }

    func allocateMemory() {
        guard BenchmarkController.current?.isRunning == true else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            print("⏱️ +2MB")
            self?.heaps.append(HeapAllocation(dataSize: 1_024 * 1_024 * 2))
            self?.allocateMemory()
        }
    }
}
