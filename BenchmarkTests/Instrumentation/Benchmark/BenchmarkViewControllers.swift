/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

internal class BenchmarkNavigationViewController: UINavigationController {
    override init(rootViewController: UIViewController) {
        super.init(rootViewController: rootViewController)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

internal class BenchmarkEndViewController: UIViewController {
    static let storyboardID = "BenchmarkEnd"

    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var closeButton: UIButton!

    var onClose: (() -> Void)? = nil

    @IBAction func didTapClose(_ sender: Any) { onClose?() }
}
