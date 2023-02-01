/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import UIKit

class ImageDataProvider {
    enum DataLoadingStatus: Encodable {
        case loading, loaded(_ base64: String), ignored
    }

    var cache = Cache<String, DataLoadingStatus>()

    var emptyImageData = "R0lGODlhAQABAIAAAP7//wAAACH5BAAAAAAALAAAAAABAAEAAAICRAEAOw=="

    func lazyBase64String(of imageView: UIImageView) -> String? {
        guard let image = imageView.image else {
            return emptyImageData
        }
        let tintColor = imageView.tintColor
        let hash = "\(image.hash)-\(String(describing: tintColor?.hash))"
        let dataLoadingStaus = cache[hash]
        switch dataLoadingStaus {
        case .loaded(let base64String):
            return base64String
        case .none:
            cache[hash] = .loading

            DispatchQueue.global(qos: .background).async { [weak self] in
                let bytesSizeLimit = 128000
                let data: Data?
                if let tintColor = tintColor, #available(iOS 13.0, *) {
                    data = image.withTintColor(tintColor).pngData()
                } else {
                    data = image.pngData()
                }
                var bytesSize = data?.count ?? 0
                if let base64String = data?.base64EncodedString(), bytesSize < bytesSizeLimit {
                    print("🏞️✅ Direct. Size: \(bytesSize / 1000) KB")
                    self?.cache[hash] = .loaded(base64String)
                }
                else {
                    let compressed = image.compressToTargetSize(bytesSizeLimit)
                    bytesSize = compressed?.count ?? 0
                    if let compressed = compressed, bytesSize < bytesSizeLimit {
                        print("🏞️✅ Compressed. Size: \(bytesSize / 1000) KB")
                        self?.cache[hash] = .loaded(compressed.base64EncodedString())
                    } else {
                        print("🏞️❌ Ignored. Size: \(bytesSize / 1000) KB")
                        self?.cache[hash] = .ignored
                    }
                }
            }
            return nil
        case .ignored:
            return emptyImageData
        case .loading:
            return nil
        }
    }
}

