/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import SRFixtures

internal extension Fixture {
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
        case .navigationBars:
            return "Navigation Bars"
        case .navigationBarDefaultTranslucent:
            return "Embedded Navigation Bar Default + Translucent"
        case .navigationBarDefaultNonTranslucent:
            return "Embedded Navigation Bar Default + Non Translucent"
        case .navigationBarBlackTranslucent:
            return "Embedded Navigation Bar Black + Translucent"
        case .navigationBarBlackNonTranslucent:
            return "Embedded Navigation Bar Black + Non Translucent"
        case .navigationBarDefaultTranslucentBarTint:
            return "Embedded Navigation Bar Default + Translucent + Bar Tint"
        case .navigationBarDefaultNonTranslucentBarTint:
            return "Embedded Navigation Bar Default + Non Translucent + Bar Tint"
        case .navigationBarDefaultTranslucentBackground:
            return "Embedded Navigation Bar Default + Translucent + Background color"
        case .navigationBarDefaultNonTranslucentBackground:
            return "Embedded Navigation Bar Default + Non Translucent + Background color"
        }
    }
}

internal class MenuViewController: UITableViewController {
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return Fixture.allCases.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell()

        if #available(iOS 14.0, *) {
            var content = cell.defaultContentConfiguration()
            content.text = Fixture.allCases[indexPath.item].menuItemTitle
            cell.contentConfiguration = content
        } else {
            let label = UILabel(frame: .init(x: 10, y: 0, width: tableView.bounds.width, height: 44))
            label.text = Fixture.allCases[indexPath.item].menuItemTitle
            cell.addSubview(label)
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        show(Fixture.allCases[indexPath.item].instantiateViewController(), sender: self)
    }
}
