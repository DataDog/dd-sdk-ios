/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import SwiftUI

/// Used to display a SwiftUI view (``RUMAlertSwiftUI``) in `RUMAlertScenario` storyboard..
class RUMAlertSwiftUIViewController: UIHostingController<RUMAlertSwiftUI> {

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder, rootView: RUMAlertSwiftUI())
    }

}

