/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import UIKit

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.SemanticObservationMapping {
    static let signedDistanceField = Self { layer, _, _ in
        guard layer.isSignedDistanceField else {
            return nil
        }

        return .init(semantics: .visualEffect(.compositorSupport))
    }

    static let destinationOutView = Self { layer, _, _ in
        guard layer.isDestinationOutView else {
            return nil
        }

        return .init(
            semantics: .visualEffect(.compositorSupport),
            ignoresSublayers: true
        )
    }

    static let portal = Self { layer, _, context in
        guard layer.isPortal else {
            return nil
        }

        guard (layer.value(forKey: "hidesSourceLayer") as? Bool) == true else {
            return .init(
                semantics: .visualEffect(.compositorSupport),
                ignoresSublayers: true
            )
        }

        guard let sourceLayer = layer.value(forKey: "sourceLayer") as? CALayer else {
            return .init(
                semantics: .visualEffect(.compositorSupport),
                ignoresSublayers: true
            )
        }

        context.hiddenPortalSourceReplayIDs.insert(sourceLayer.replayID)

        return .init(
            semantics: .visualEffect(
                .portal(
                    .init(
                        sourceLayer: CALayerReference(sourceLayer),
                        sourceRect: sourceLayer.convert(layer.bounds, from: layer),
                        isOpaque: sourceLayer.isOpaque
                    )
                )
            ),
            ignoresSublayers: true
        )
    }

    static let tabBarPlatter = Self { layer, _, _ in
        guard layer.isTabBarPlatter else {
            return nil
        }

        return .init(semantics: .visualEffect(.automaticCapsule))
    }

    static let glassGroup = Self { layer, _, _ in
        guard layer.isGlassGroup else {
            return nil
        }

        return .init(semantics: .visualEffect(.glassGroup), ignoresSublayers: true)
    }

    static let liquidLens = Self { layer, _, _ in
        guard layer.isLiquidLens else {
            return nil
        }

        return .init(semantics: .visualEffect(.liquidLens))
    }

    static let visualEffectBackdrop = Self { layer, _, _ in
        guard layer.isVisualEffectBackdrop else {
            return nil
        }

        return .init(
            semantics: .visualEffect(.backdrop),
            ignoresSublayers: true
        )
    }

    static let visualEffectBackground = Self { layer, _, _ in
        guard layer.isVisualEffectBackground else {
            return nil
        }

        // Visual effect containers may store their fallback background on the owning view
        let color: UIColor? = layer.superlayer
            .flatMap { superlayer in
                guard
                    let superview = superlayer.delegate as? UIView,
                    superview.bounds.size == layer.bounds.size,
                    let backgroundColor = superview.backgroundColor,
                    backgroundColor.cgColor.alpha > 0
                else {
                    return nil
                }
                return backgroundColor
            }

        return .init(
            semantics: .visualEffect(.background(color)),
            ignoresSublayers: true
        )
    }
}
#endif
