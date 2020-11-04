/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit
import Datadog

internal extension UIImageView {
    private static var imageTaskKey: UInt8 = 0
    private var imageTask: URLSessionDataTask? {
        get {
            return objc_getAssociatedObject(self, &Self.imageTaskKey) as? URLSessionDataTask
        }
        set {
            objc_setAssociatedObject(self, &Self.imageTaskKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    func setImage(with url: URL) {
        imageTask?.cancel()
        let task = api.httpClient.dataTask(with: url) { [weak self] data, response, error in
            self?.imageTask = nil
            if let someData = data {
                let image = UIImage(data: someData)
                DispatchQueue.main.async {
                    self?.image = image
                }
            }
        }
        task.resume()
        imageTask = task
    }
}
