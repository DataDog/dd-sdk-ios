/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import CoreGraphics

@available(iOS 13.0, tvOS 13.0, *)
extension LayerSnapshot {
    var isOpaque: Bool {
        backgroundColor?.alpha == 1.0 && opacity == 1.0 &&
        !hasMask && cornerRadius == 0 && isAxisAligned
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension Array where Element == LayerSnapshot {
    func removingObscured() -> [LayerSnapshot] {
        guard !isEmpty else {
            return self
        }

        var opaqueFrames: [CGRect] = []
        var result: [LayerSnapshot] = []
        result.reserveCapacity(count)

        // Process front-to-back
        for snapshot in reversed() {
            let visibleFrame = snapshot.frame.intersection(snapshot.clipRect)

            guard !visibleFrame.isNull, !visibleFrame.isEmpty else {
                result.append(snapshot)
                continue
            }

            // Skip layers fully contained by an opaque layer in front
            let isObscured = opaqueFrames.contains {
                $0.contains(visibleFrame)
            }

            guard !isObscured else {
                continue
            }

            result.append(snapshot)

            // Record frame if this layer can occlude
            if snapshot.isOpaque {
                opaqueFrames.append(visibleFrame)
            }
        }

        // Restore back-to-front order
        return result.reversed()
    }
}
#endif
