/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

internal class ImagesViewController: UIViewController {
    @IBOutlet weak var customButton: UIButton!
    @IBOutlet weak var customImageView: UIImageView!
    @IBOutlet weak var contentImageView: UIImageView!
    @IBOutlet weak var contentHeightAspectFillImageView: UIImageView!
    @IBOutlet weak var contentWidthAspectFillImageView: UIImageView!

    override func viewDidLoad() {
        super.viewDidLoad()
        guard #available(iOS 13.0, *) else {
            return
        }

        let color = UIColor(white: 0, alpha: 0.05)
        customButton.setBackgroundImage(UIImage(color: color), for: .normal)

        let image = UIImage(named: "dd_logo", in: .module, with: nil)
        customImageView.image = image?.withRenderingMode(.alwaysTemplate)

        contentImageView.image = UIImage(color: color)

        let scaleWidthAspectFillImage = UIImage(named: "tree_aspect_fill_width_smaller", in: .module, with: nil)
        contentWidthAspectFillImageView.image = scaleWidthAspectFillImage

        let scaleHeightAspectFillImage = UIImage(named: "moon_aspect_fill_height_bigger", in: .module, with: nil)
        contentHeightAspectFillImageView.image = scaleHeightAspectFillImage
    }
}

fileprivate extension UIImage {
    convenience init?(color: UIColor, size: CGSize = CGSize(width: 1.0, height: 1.0)) {
        let rect = CGRect(origin: .zero, size: size)
        UIGraphicsBeginImageContextWithOptions(rect.size, false, 1.0)
        defer { UIGraphicsEndImageContext() }

        guard let context = UIGraphicsGetCurrentContext() else {
            return nil
        }
        context.setFillColor(color.cgColor)
        context.fill(rect)

        guard let cgImage = context.makeImage() else {
            return nil
        }
        self.init(cgImage: cgImage)
    }
}
