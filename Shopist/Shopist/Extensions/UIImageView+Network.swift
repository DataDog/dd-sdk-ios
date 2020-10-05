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
        let imageDownloader = ImageDownloader(configuration: config, imageCache: nil)
        UIImageView.af.sharedImageDownloader = imageDownloader
    }()

    func setImage(with url: URL) {
        _ = Self.setupOnce
        Global.rum.startResourceLoading(resourceName: url.path, url: url, httpMethod: .GET)
        af.setImage(withURL: url) { result in
            if let someError = (result.error ?? fakeError(onceIn: 40)) {
                Global.rum.stopResourceLoadingWithError(
                    resourceName: url.path,
                    error: someError,
                    source: .network,
                    httpStatusCode: 500
                )
            } else {
                Global.rum.stopResourceLoading(
                    resourceName: url.path,
                    kind: .image,
                    httpStatusCode: result.response?.statusCode ?? 200,
                    size: UInt64(result.data?.count ?? 0)
                )
            }
        }
    }
}
