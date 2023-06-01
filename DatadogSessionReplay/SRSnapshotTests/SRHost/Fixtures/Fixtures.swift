/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import SwiftUI

internal enum Fixture: CaseIterable {
    case basicShapes
    case basicTexts
    case sliders
    case segments
    case pickers
    case switches
    case textFields
    case steppers
    case datePickersInline
    case datePickersCompact
    case datePickersWheels
    case timePickersCountDown
    case timePickersWheels
    case timePickersCompact
    case images
    case unsupportedViews
    case popups
    case swiftUI

    var menuItemTitle: String {
        switch self {
        case .basicShapes:
            return "Basic Shapes"
        case .basicTexts:
            return "Basic Texts"
        case .sliders:
            return "Sliders"
        case .segments:
            return "Segments"
        case .pickers:
            return "Pickers"
        case .switches:
            return "Switches"
        case .textFields:
            return "Text Fields"
        case .steppers:
            return "Steppers"
        case .datePickersInline:
            return "Date Picker (inline)"
        case .datePickersCompact:
            return "Date Picker (compact)"
        case .datePickersWheels:
            return "Date Picker (wheels)"
        case .timePickersCountDown:
            return "Time Picker (count down)"
        case .timePickersWheels:
            return "Time Picker (wheels)"
        case .timePickersCompact:
            return "Time Picker (compact)"
        case .images:
            return "Images"
        case .unsupportedViews:
            return "Unsupported Views"
        case .popups:
            return "Popups"
        case .swiftUI:
            return "SwiftUI"
        }
    }

    func instantiateViewController() -> UIViewController {
        switch self {
        case .basicShapes:
            return UIStoryboard.basic.instantiateViewController(withIdentifier: "Shapes")
        case .basicTexts:
            return UIStoryboard.basic.instantiateViewController(withIdentifier: "Texts")
        case .sliders:
            return UIStoryboard.inputElements.instantiateViewController(withIdentifier: "Sliders")
        case .segments:
            return UIStoryboard.inputElements.instantiateViewController(withIdentifier: "Segments")
        case .pickers:
            return UIStoryboard.inputElements.instantiateViewController(withIdentifier: "Pickers")
        case .switches:
            return UIStoryboard.inputElements.instantiateViewController(withIdentifier: "Switches")
        case .textFields:
            return UIStoryboard.inputElements.instantiateViewController(withIdentifier: "TextFields")
        case .steppers:
            return UIStoryboard.inputElements.instantiateViewController(withIdentifier: "Steppers")
        case .datePickersInline:
            return UIStoryboard.datePickers.instantiateViewController(withIdentifier: "DatePickersInline")
        case .datePickersCompact:
            return UIStoryboard.datePickers.instantiateViewController(withIdentifier: "DatePickersCompact")
        case .datePickersWheels:
            return UIStoryboard.datePickers.instantiateViewController(withIdentifier: "DatePickersWheels")
        case .timePickersCountDown:
            return UIStoryboard.datePickers.instantiateViewController(withIdentifier: "TimePickersCountDown")
        case .timePickersWheels:
            return UIStoryboard.datePickers.instantiateViewController(withIdentifier: "TimePickersWheels")
        case .timePickersCompact:
            return UIStoryboard.datePickers.instantiateViewController(withIdentifier: "DatePickersCompact") // sharing the same VC with `datePickersCompact`
        case .images:
            return UIStoryboard.images.instantiateViewController(withIdentifier: "Images")
        case .unsupportedViews:
            return UIStoryboard.unsupportedViews.instantiateViewController(withIdentifier: "UnsupportedViews")
        case .popups:
            return UIStoryboard.basic.instantiateViewController(withIdentifier: "Popups")
        case .swiftUI:
            return UIHostingController(rootView: Text("Hello SwiftUI"))
        }
    }
}

internal extension UIStoryboard {
    static var basic: UIStoryboard { UIStoryboard(name: "Basic", bundle: nil) }
    static var inputElements: UIStoryboard { UIStoryboard(name: "InputElements", bundle: nil) }
    static var datePickers: UIStoryboard { UIStoryboard(name: "InputElements-DatePickers", bundle: nil) }
    static var images: UIStoryboard { UIStoryboard(name: "Images", bundle: nil) }
    static var unsupportedViews: UIStoryboard { UIStoryboard(name: "UnsupportedViews", bundle: nil) }
}
