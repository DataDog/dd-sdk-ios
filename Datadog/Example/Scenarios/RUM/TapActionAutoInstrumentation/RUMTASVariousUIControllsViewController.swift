/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

internal class RUMTASVariousUIControllsViewController: UITableViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        hideKeyboardWhenTapOutside()
    }

    // MARK: - UITextField events

    @IBAction func textFieldDidEndEditing(_ sender: Any) {
    }

    // MARK: - UIStepper events

    @IBAction func stepperDidChangeValue(_ sender: Any) {
    }

    // MARK: - UISlider events

    @IBAction func sliderDidChangeValue(_ sender: Any) {
    }

    // MARK: - UISegmentedControl events

    @IBAction func segmentedControlDidChangeValue(_ sender: Any) {
    }

    // MARK: - UIBarButtonItem events

    @IBAction func didTapBarButtonItem(_ sender: Any) {
    }
}
