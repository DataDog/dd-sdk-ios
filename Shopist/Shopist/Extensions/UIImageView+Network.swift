/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit
import AlamofireImage

internal extension UIImageView {
    func setImage(with url: URL) {
        rum?.startResourceLoading(resourceName: url.path, url: url, httpMethod: .GET)
        // randomizing cacheKey forces to make new request
        let cacheKey = UUID().uuidString
        af.setImage(withURL: url, cacheKey: cacheKey) { result in
            if let someError = (result.error ?? fakeError(onceIn: 20)) {
                rum?.stopResourceLoadingWithError(
                    resourceName: url.path,
                    error: someError,
                    source: .network,
                    httpStatusCode: 500
                )
            } else {
                rum?.stopResourceLoading(
                    resourceName: url.path,
                    kind: .image,
                    httpStatusCode: result.response?.statusCode ?? 200,
                    size: UInt64(result.data?.count ?? 0)
                )
            }
        }
    }
}
