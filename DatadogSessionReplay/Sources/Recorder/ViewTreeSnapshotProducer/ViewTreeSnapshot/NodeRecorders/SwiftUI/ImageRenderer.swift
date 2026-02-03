/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import Foundation
import UIKit

@available(iOS 13.0, tvOS 13.0, *)
internal final class ImageRenderer {
    private class Key: NSObject {
        private let contents: AnyImageRepresentable

        init(_ contents: some ImageRepresentable) {
            self.contents = AnyImageRepresentable(contents)
        }

        override var hash: Int {
            var hasher = Hasher()
            hasher.combine(contents)
            return hasher.finalize()
        }

        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? Key else {
                return false
            }
            return contents == other.contents
        }
    }

    private let cache = NSCache<Key, UIImage>()

    init() {
        cache.countLimit = 20
    }

    func image(for contents: some ImageRepresentable) -> UIImage? {
        let key = Key(contents)

        if let image = cache.object(forKey: key) {
            return image
        }

        guard let image = contents.makeImage() else {
            return nil
        }

        cache.setObject(image, forKey: key)

        return image
    }
}

#endif
