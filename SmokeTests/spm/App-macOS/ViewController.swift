/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import Cocoa

class ViewController: NSViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        DatadogSetup.initialize()
        DatadogSetup.enableAndTest(viewController: self)

        addLabel()
    }

    private func addLabel() {
        let label = NSTextField(labelWithString: "Testing...")
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 50)
        ])

        label.alignment = .center
    }

}
