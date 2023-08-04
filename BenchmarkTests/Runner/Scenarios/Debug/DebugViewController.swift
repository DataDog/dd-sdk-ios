/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

/// Does nothing else except allocating heap memory blocks in certain interval until benchmark finishes.
internal class DebugViewController: UIViewController {
    private class HeapAllocation {
        static let allocationSizeInMB: Int = 1
        private var data: Data

        init() {
            let dataSize: Int = HeapAllocation.allocationSizeInMB * 1_024 * 1_024
            data = Data(count: dataSize)
            for i in (0..<dataSize) {
                data[i] = .random(in: UInt8.min...UInt8.max) // write random bytes otherwise memory pages get compressed
            }
        }
    }

    private var schedule: Schedule!
    @IBOutlet weak var allocatedMemoryLabel: UILabel!

    private var allocations: [HeapAllocation] = [] {
        didSet {
            allocatedMemoryLabel.text = "\(allocations.count * HeapAllocation.allocationSizeInMB)MB"
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        schedule = Schedule(interval: 0.5, operation: { [weak self] in
            self?.allocateHeapMemory()
        })
    }

    private func allocateHeapMemory() {
        allocations.append(HeapAllocation())
    }
}
