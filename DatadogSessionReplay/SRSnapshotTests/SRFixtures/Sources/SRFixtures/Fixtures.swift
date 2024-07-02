/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import SwiftUI

public enum Fixture: CaseIterable {
    case basicShapes
    case basicTexts
    case sliders
    case progressViews
    case activityIndicators
    case segments
    case pickers
    case switches
    case textFields
    case steppers
    /// Instantiated view controller is ``DatePickersInlineViewController``
    case datePickersInline
    /// Instantiated view controller is ``DatePickersCompactViewController``
    case datePickersCompact
    /// Instantiated view controller is ``DatePickersWheelsViewController``
    case datePickersWheels
    /// Instantiated view controller is ``TimePickersCountDownViewController``
    case timePickersCountDown
    /// Instantiated view controller is ``TimePickersWheelViewController``
    case timePickersWheels
    /// Instantiated view controller is ``TimePickersCompactViewController``
    case timePickersCompact
    case images
    case unsupportedViews
    /// Instantiated view controller is ``PopupsViewController``
    case popups
    case swiftUI
    case navigationBars
    case navigationBarDefaultTranslucent
    case navigationBarDefaultNonTranslucent
    case navigationBarBlackTranslucent
    case navigationBarBlackNonTranslucent
    case navigationBarDefaultTranslucentBarTint
    case navigationBarDefaultNonTranslucentBarTint
    case navigationBarDefaultTranslucentBackground
    case navigationBarDefaultNonTranslucentBackground
    case tabbar
    case embeddedTabbar
    case embeddedTabbarUnselectedTintColor

    public func instantiateViewController() -> UIViewController {
        switch self {
        case .basicShapes:
            return UIStoryboard.basic.instantiateViewController(withIdentifier: "Shapes")
        case .basicTexts:
            return UIStoryboard.basic.instantiateViewController(withIdentifier: "Texts")
        case .sliders:
            return UIStoryboard.inputElements.instantiateViewController(withIdentifier: "Sliders")
        case .progressViews:
            return UIStoryboard.inputElements.instantiateViewController(withIdentifier: "ProgressViews")
        case .activityIndicators:
            return UIStoryboard.inputElements.instantiateViewController(withIdentifier: "ActivityIndicators")
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
            if #available(iOS 13.0, *) {
                return UIHostingController(rootView: Text("Hello SwiftUI"))
            } else {
                return ErrorViewController(message: "`.swiftUI` fixture is only available on iOS 13+")
            }
        //- Navigation Bars
        case .navigationBars:
            return UIStoryboard.navigationBars.instantiateViewController(withIdentifier: "NavigationBars")
        case .navigationBarDefaultTranslucent:
            let vc = UIStoryboard.navigationBars.instantiateViewController(withIdentifier: "Default_Translucent_Navbar")
            return vc
        case .navigationBarDefaultNonTranslucent:
            return UIStoryboard.navigationBars.instantiateViewController(withIdentifier: "Default_Non_Translucent_Navbar")
        case .navigationBarBlackTranslucent:
            let vc = UIStoryboard.navigationBars.instantiateViewController(withIdentifier: "Black_Translucent_Navbar")
            return vc
        case .navigationBarBlackNonTranslucent:
            return UIStoryboard.navigationBars.instantiateViewController(withIdentifier: "Black_Non_Translucent_Navbar")
        case .navigationBarDefaultTranslucentBarTint:
            let vc = UIStoryboard.navigationBars.instantiateViewController(withIdentifier: "Default_Translucent_Bar_Tint_Navbar")
            return vc
        case .navigationBarDefaultNonTranslucentBarTint:
            return UIStoryboard.navigationBars.instantiateViewController(withIdentifier: "Default_Non_Translucent_Bar_Tint_Navbar")
        case .navigationBarDefaultTranslucentBackground:
            let vc = UIStoryboard.navigationBars.instantiateViewController(withIdentifier: "Default_Translucent_Background_Navbar")
            return vc
        case .navigationBarDefaultNonTranslucentBackground:
            return UIStoryboard.navigationBars.instantiateViewController(withIdentifier: "Default_Non_Translucent_Background_Navbar")
        case .tabbar:
            return UIStoryboard.tabbars.instantiateViewController(withIdentifier: "Tabbars")
        case .embeddedTabbar:
            return UIStoryboard.tabbars.instantiateViewController(withIdentifier: "EmbeddedTabbar")
        case .embeddedTabbarUnselectedTintColor:
            return UIStoryboard.tabbars.instantiateViewController(withIdentifier: "EmbeddedTabbarUnselectedTintColor")
        }
    }
}

internal extension UIStoryboard {
    static var basic: UIStoryboard { UIStoryboard(name: "Basic", bundle: .module) }
    static var inputElements: UIStoryboard { UIStoryboard(name: "InputElements", bundle: .module) }
    static var datePickers: UIStoryboard { UIStoryboard(name: "InputElements-DatePickers", bundle: .module) }
    static var images: UIStoryboard { UIStoryboard(name: "Images", bundle: .module) }
    static var unsupportedViews: UIStoryboard { UIStoryboard(name: "UnsupportedViews", bundle: .module) }
    static var navigationBars: UIStoryboard { UIStoryboard(name: "NavigationBars", bundle: .module) }
    static var tabbars: UIStoryboard { UIStoryboard(name: "Tabbars", bundle: .module) }
}
