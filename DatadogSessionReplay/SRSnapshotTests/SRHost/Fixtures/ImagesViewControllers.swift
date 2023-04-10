/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

internal class ImagesViewController: UIViewController {
    @IBOutlet weak var customImageView: UIImageView!

    override func viewDidLoad() {
        super.viewDidLoad()
        customImageView.image = UIImage(named: "dd_logo")?.withRenderingMode(.alwaysTemplate)
    }
}
