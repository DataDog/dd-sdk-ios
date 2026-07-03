//
//  ViewController.swift
//  App macOS
//
//  Created by Miguel Arroz on 02/07/2026.
//  Copyright © 2026 Datadog. All rights reserved.
//

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
