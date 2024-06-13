/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

internal class PickersViewController: UIViewController {
    private class PickerData: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
        var labels: [[String]] = []

        init(labels: [[String]]) {
            self.labels = labels
        }

        func numberOfComponents(in pickerView: UIPickerView) -> Int {
            labels.count
        }

        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            labels[component].count
        }

        func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
            labels[component][row]
        }

    }

    private let firstPickerData = PickerData(
        labels: [
            ["One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight"]
        ]
    )
    private let secondPickerData = PickerData(
        labels: [
            ["A", "B", "C", "D", "E", "F", "G"],
            ["One", "Two", "Three", "Four", "Five"],
            ["First", "Second", "Third", "Fourth", "Fifth"],
        ]
    )
    @IBOutlet weak var firstPicker: UIPickerView!
    @IBOutlet weak var secondPicker: UIPickerView!

    override func viewDidLoad() {
        super.viewDidLoad()

        firstPicker.dataSource = firstPickerData
        firstPicker.delegate = firstPickerData
        firstPicker.selectRow(3, inComponent: 0, animated: false)

        secondPicker.dataSource = secondPickerData
        secondPicker.delegate = secondPickerData
        secondPicker.selectRow(3, inComponent: 0, animated: false)
        secondPicker.selectRow(0, inComponent: 1, animated: false)
        secondPicker.selectRow(4, inComponent: 2, animated: false)
    }
}

public class DatePickersInlineViewController: UIViewController {
    @IBOutlet weak var datePicker: UIDatePicker!

    public func set(date: Date, timeZone: TimeZone) {
        datePicker.timeZone = timeZone
        datePicker.setDate(date, animated: false)
    }
}

public class DatePickersCompactViewController: UIViewController {
    @IBOutlet weak var datePicker: UIDatePicker!

    public func set(date: Date, timeZone: TimeZone) {
        datePicker.timeZone = timeZone
        datePicker.setDate(date, animated: false)
    }

    /// Forces the "compact" date picker to open full calendar view in a popover.
    public func openCalendarPopover() {
        // Here we use private Objc APIs. It works fine on iOS 17.5 which matches the OS version used
        // for snapshot tests, but might need updates in the future.
        //
        // If this breaks on newer iOS version, leverage this gist:
        // https://gist.github.com/ncreated/dedd8f8b628fbb820b0771e8355e32b9
        // to inspect private methods on `datePicker` and its subviews (`po datePicker.__methods`). Find the
        // one that can trigger popover open and use it as `tapAction`.
        let target = datePicker.subviews[0].subviews[0]
        let tapAction = NSSelectorFromString("activateLabel")
        target.perform(tapAction, with: nil)
    }

    /// Forces the "wheel" time picker to open in a popover.
    public func openTimePickerPopover() {
        // Here we use private Objc APIs - it works fine on iOS 17.5 which matches the OS version used
        // for snapshot tests, but might need updates in the future.
        //
        // If this breaks on newer iOS version, leverage this gist:
        // https://gist.github.com/ncreated/dedd8f8b628fbb820b0771e8355e32b9
        // to inspect private methods on `datePicker` and its subviews (`po datePicker.__methods`). Find the
        // one that can trigger popover open and use it as `tapAction`.
        let target = datePicker.subviews[0].subviews[1]
        let tapAction = NSSelectorFromString("activateLabel")
        target.perform(tapAction, with: nil)
    }
}

public class DatePickersWheelsViewController: UIViewController {
    @IBOutlet weak var datePicker: UIDatePicker!

    public func set(date: Date, timeZone: TimeZone) {
        datePicker.timeZone = timeZone
        datePicker.setDate(date, animated: false)
    }
}

public class TimePickersCountDownViewController: UIViewController {}

public class TimePickersWheelViewController: UIViewController {
    @IBOutlet weak var datePicker: UIDatePicker!

    public func set(date: Date, timeZone: TimeZone) {
        datePicker.timeZone = timeZone
        datePicker.setDate(date, animated: false)
    }
}

/// Sharing the same VC for compact time and date picker.
public typealias TimePickersCompactViewController = DatePickersCompactViewController
