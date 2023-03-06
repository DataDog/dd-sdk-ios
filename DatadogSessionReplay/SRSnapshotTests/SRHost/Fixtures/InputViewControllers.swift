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
