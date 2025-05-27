
/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import SwiftUI

// MARK: - SwiftUIAutoInstrumentationSingleRootViewScenario

@available(iOS 16.0, *)
class SwiftUIAutoInstrumentationSingleRootViewScenario: UIHostingController<NavigationStackExample> {
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder, rootView: NavigationStackExample())
    }
}
