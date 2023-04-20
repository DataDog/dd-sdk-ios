/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

internal class ImagesViewController: UIViewController {
    @IBOutlet weak var customButton: UIButton!
    @IBOutlet weak var customImageView: UIImageView!
    @IBOutlet weak var tabBar: UITabBar!
    @IBOutlet weak var navigationBar: UINavigationBar!

    override func viewDidLoad() {
        super.viewDidLoad()

        let color = UIColor(white: 0, alpha: 0.05)
        customButton.setBackgroundImage(UIImage(color: color), for: .normal)

        tabBar.backgroundImage = UIImage(color: color)
        tabBar.selectedItem = tabBar.items?.first
        navigationBar.setBackgroundImage(UIImage(color: color), for: .default)

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
