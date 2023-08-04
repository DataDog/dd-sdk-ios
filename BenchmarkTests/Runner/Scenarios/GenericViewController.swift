/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

internal class GenericViewController: UIViewController {
    var labelText: String = ""

    init(labelText: String) {
        self.labelText = labelText
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let label = UILabel()
        label.text = labelText
        label.textAlignment = .center
        label.font = UIFont.boldSystemFont(ofSize: 24)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .black

        view.backgroundColor = .white
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private var runningSchedules: [Schedule] = []

    func schedule(operation: @escaping () -> Void, every interval: TimeInterval) {
        runningSchedules.append(Schedule(interval: interval, operation: operation))
    }
}

internal class Schedule {
    private var timer: Timer!

    init(interval: TimeInterval, operation: @escaping () -> Void) {
        timer = Timer(timeInterval: interval, repeats: true) { _ in operation() }
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .common)
    }

    deinit {
        timer.invalidate()
    }
}
