//
//  SamplingPriority.swift
//  Datadog
//
//  Created by Miguel Arroz on 24/12/2025.
//  Copyright © 2025 Datadog. All rights reserved.
//

import Foundation

public enum SamplingPriority: Int {
    case manualDrop = -1
    case autoDrop = 0
    case autoKeep = 1
    case manualKeep = 2

    public var isKept: Bool {
        switch self {
        case .manualDrop, .autoDrop: false
        case .manualKeep, .autoKeep: true
        }
    }
}
