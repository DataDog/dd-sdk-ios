/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

internal class ImagesViewController: UIViewController {
    @IBOutlet weak var customButton: UIButton!
    @IBOutlet weak var customImageView: UIImageView!

    override func viewDidLoad() {
        super.viewDidLoad()

        customButton.setBackgroundImage(UIImage(color: .lightGray), for: .normal)

        customImageView.image = UIImage(named: "dd_logo")?.withRenderingMode(.alwaysTemplate)
    }
}

fileprivate extension UIImage {
    convenience init?(color: UIColor, size: CGSize = CGSize(width: 1.0, height: 1.0)) {
        let rect = CGRect(origin: .zero, size: size)
        UIGraphicsBeginImageContextWithOptions(rect.size, false, 1.0)
        defer { UIGraphicsEndImageContext() }

        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        context.setFillColor(color.cgColor)
        context.fill(rect)

        guard let cgImage = context.makeImage() else { return nil }
        self.init(cgImage: cgImage)
    }
}
