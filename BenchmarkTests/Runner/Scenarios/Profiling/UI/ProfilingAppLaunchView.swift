/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogTrace
import SwiftUI

struct ProfilingAppLaunchView: View {
    init() {
        // Block TTID for 3 seconds to have more Profiling time.
        Thread.sleep(forTimeInterval: 4)
    }

    var body: some View {
        Text("Profiling App Launch")
    }
}

#Preview {
    ProfilingAppLaunchView()
}
