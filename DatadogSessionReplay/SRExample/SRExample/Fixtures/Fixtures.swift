/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

internal enum Fixture: CaseIterable {
    case basicShapes
    case basicTexts

    var menuItemTitle: String {
        switch self {
        case .basicShapes:
            return "Basic Shapes"
        case .basicTexts:
            return "Basic Texts"
        }
    }

    func instantiateViewController() -> UIViewController {
        switch self {
        case .basicShapes:
            return UIStoryboard.basic.instantiateViewController(withIdentifier: "Shapes")
        case .basicTexts:
            return UIStoryboard.basic.instantiateViewController(withIdentifier: "Texts")
        }
    }
}

internal extension UIStoryboard {
    static var basic: UIStoryboard { UIStoryboard(name: "Basic", bundle: nil) }
}
