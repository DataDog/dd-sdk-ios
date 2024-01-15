/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

internal class CSPictureViewController: UIViewController {
    let sessionDelegate = CustomURLSessionDelegate()

    private lazy var session = URLSession(
        configuration: .default,
        delegate: sessionDelegate,
        delegateQueue: nil
    )

    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var successLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        successLabel.isHidden = true
    }

    @IBAction func didTapDownloadImage(_ sender: UIButton) {
        let enableSender = sender.disableUntilCompletion()

        let imageURL = URL(string: "https://imgix.datadoghq.com/img/about/presskit/usage/logousage_white.png")!
        var imageRequest = URLRequest(url: imageURL)
        imageRequest.cachePolicy = .reloadIgnoringLocalCacheData

        let imageTask = session.dataTask(with: imageRequest) { [weak self] data, _, error in
            if let error = error {
                // Crash the app, so we have obvious feedback in integration test
                fatalError("Failed to download image: \(error)")
            } else if let data = data {
                DispatchQueue.main.async {
                    enableSender()
                    self?.showImage(from: data)
                }
            } else {
                fatalError("Failed to download image with no clue")
            }
        }
        imageTask.resume()
    }

    private func showImage(from imageData: Data) {
        imageView.image = UIImage(data: imageData)
        successLabel.isHidden = false
    }
}
