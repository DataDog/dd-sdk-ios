/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI
import TipKit

@available(iOS 17.0, *)
struct RUMCpuSuggestionTip: Tip {
    var title: Text {
        Text("CPU Usage Alert")
    }

    var message: Text? {
        Text("High CPU usage detected. Look for performance bottlenecks and optimize heavy computations.")
    }
}
