/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit
import Datadog
import AlamofireImage

internal extension UIImageView {
    private static let setupOnce: () = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        let imageDownloader = ImageDownloader(
            session: api.httpClient,
            imageCache: nil
        )
        UIImageView.af.sharedImageDownloader = imageDownloader
    }()

    func setImage(with url: URL) {
        _ = Self.setupOnce
        af.setImage(withURL: url)
    }
}
