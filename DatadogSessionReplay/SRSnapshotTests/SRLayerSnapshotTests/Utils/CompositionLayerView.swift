/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
@_spi(Internal)
@testable import DatadogSessionReplay

@available(iOS 13.0, *)
@MainActor
internal final class CompositionLayerView: UIView {
    private let contentView = UIView()

    init(
        _ layer: SRCompositionLayer,
        identifiedLayers: [Int64: SRCompositionLayer],
        identifiedWireframes: [Int64: SRWireframe],
        identifiedResources: [String: Resource],
        parentFrame: CGRect
    ) {
        super.init(frame: layer.absoluteFrame.offsetBy(dx: -parentFrame.minX, dy: -parentFrame.minY))
        backgroundColor = .clear
        contentView.frame = bounds
        contentView.backgroundColor = .clear
        addSubview(contentView)

        addViews(
            for: layer.children,
            parentFrame: layer.absoluteFrame,
            identifiedLayers: identifiedLayers,
            identifiedWireframes: identifiedWireframes,
            identifiedResources: identifiedResources
        )

        applyModifiers(layer.modifiers ?? [], identifiedResources: identifiedResources)
        applyCompositeOperation(layer.compositeOperation)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func addViews(
        for children: [SRCompositionLayerChild],
        parentFrame: CGRect,
        identifiedLayers: [Int64: SRCompositionLayer],
        identifiedWireframes: [Int64: SRWireframe],
        identifiedResources: [String: Resource]
    ) {
        for child in children {
            switch child.type {
            case .layer:
                guard let childLayer = identifiedLayers[child.id] else {
                    continue
                }
                if (childLayer.modifiers ?? []).isEmpty,
                   childLayer.compositeOperation == nil || childLayer.compositeOperation == .sourceOver {
                    // Plain groups share their parent's destination. An extra UIView would isolate
                    // descendant compositing operations from content painted before the group.
                    addViews(
                        for: childLayer.children,
                        parentFrame: parentFrame,
                        identifiedLayers: identifiedLayers,
                        identifiedWireframes: identifiedWireframes,
                        identifiedResources: identifiedResources
                    )
                } else {
                    contentView.addSubview(
                        CompositionLayerView(
                            childLayer,
                            identifiedLayers: identifiedLayers,
                            identifiedWireframes: identifiedWireframes,
                            identifiedResources: identifiedResources,
                            parentFrame: parentFrame
                        )
                    )
                }
            case .wireframe:
                guard
                    let wireframe = identifiedWireframes[child.id],
                    let view = WireframeView(
                        wireframe,
                        identifiedResources: identifiedResources,
                        parentFrame: parentFrame
                    )
                else {
                    continue
                }
                contentView.addSubview(view)
            }
        }
    }

    private func applyModifiers(
        _ modifiers: [SRCompositionLayerModifier],
        identifiedResources: [String: Resource]
    ) {
        for modifier in modifiers {
            switch modifier {
            case .compositionLayerClipModifier(let modifier):
                applyClipModifier(modifier)
            case .compositionLayerOpacityModifier(let modifier):
                alpha = CGFloat(modifier.value)
            case .compositionLayerColorMatrixModifier(let modifier):
                applyColorMatrixModifier(modifier)
            case .compositionLayerGaussianBlurModifier(let modifier):
                applyGaussianBlurModifier(modifier)
            case .compositionLayerShadowModifier(let modifier):
                applyShadowModifier(modifier)
            case .compositionLayerBrightnessBiasModifier(let modifier):
                applyBrightnessBiasModifier(modifier)
            case .compositionLayerSaturateModifier(let modifier):
                applySaturateModifier(modifier)
            case .compositionLayerMaskImageModifier(let modifier):
                applyMaskImageModifier(modifier, identifiedResources: identifiedResources)
            }
        }
    }

    private func applyCompositeOperation(_ compositeOperation: SRCompositionLayer.CompositeOperation?) {
        switch compositeOperation {
        case .destinationIn:
            layer.compositingFilter = "destIn"
        case .destinationOut:
            layer.compositingFilter = "destOut"
        case .plusDarker:
            layer.compositingFilter = "plusD"
        case .sourceOver, nil:
            break
        }
    }

    private func applyClipModifier(_ modifier: SRCompositionLayerClipModifier) {
        guard let path = CGPath.parse(modifier.path) else {
            return
        }

        let mask = CAShapeLayer()
        mask.frame = bounds
        mask.path = path
        switch modifier.fillRule {
        case .evenodd:
            mask.fillRule = .evenOdd
        case .nonzero, nil:
            mask.fillRule = .nonZero
        }
        contentView.layer.mask = mask
    }

    private func applyColorMatrixModifier(_ modifier: SRCompositionLayerColorMatrixModifier) {
        guard
            modifier.matrix.count == 20,
            let filter = NSObject.makeCAFilter(type: "colorMatrix")
        else {
            return
        }
        let matrix = CALayerSnapshot.ColorMatrix(
            m11: Float(modifier.matrix[0]),
            m12: Float(modifier.matrix[1]),
            m13: Float(modifier.matrix[2]),
            m14: Float(modifier.matrix[3]),
            m15: Float(modifier.matrix[4]),
            m21: Float(modifier.matrix[5]),
            m22: Float(modifier.matrix[6]),
            m23: Float(modifier.matrix[7]),
            m24: Float(modifier.matrix[8]),
            m25: Float(modifier.matrix[9]),
            m31: Float(modifier.matrix[10]),
            m32: Float(modifier.matrix[11]),
            m33: Float(modifier.matrix[12]),
            m34: Float(modifier.matrix[13]),
            m35: Float(modifier.matrix[14]),
            m41: Float(modifier.matrix[15]),
            m42: Float(modifier.matrix[16]),
            m43: Float(modifier.matrix[17]),
            m44: Float(modifier.matrix[18]),
            m45: Float(modifier.matrix[19])
        )
        filter.setValue(matrix.nsValue, forKey: "inputColorMatrix")
        appendFilter(filter)
    }

    private func applyGaussianBlurModifier(_ modifier: SRCompositionLayerGaussianBlurModifier) {
        guard let filter = NSObject.makeCAFilter(type: "gaussianBlur") else {
            return
        }

        filter.setValue(CGFloat(modifier.radius), forKey: "inputRadius")
        appendFilter(filter)
    }

    private func applyBrightnessBiasModifier(_ modifier: SRCompositionLayerBrightnessBiasModifier) {
        guard let filter = NSObject.makeCAFilter(type: "colorBrightness") else {
            return
        }

        filter.setValue(CGFloat(modifier.value), forKey: "inputAmount")
        appendFilter(filter)
    }

    private func applySaturateModifier(_ modifier: SRCompositionLayerSaturateModifier) {
        guard let filter = NSObject.makeCAFilter(type: "colorSaturate") else {
            return
        }

        filter.setValue(CGFloat(modifier.value), forKey: "inputAmount")
        appendFilter(filter)
    }

    private func applyShadowModifier(_ modifier: SRCompositionLayerShadowModifier) {
        layer.shadowColor = UIColor(hexString: modifier.color).cgColor
        layer.shadowOffset = CGSize(width: modifier.offsetX, height: modifier.offsetY)
        layer.shadowPath = modifier.path.flatMap(CGPath.parse)
        layer.shadowRadius = CGFloat(modifier.radius)
        layer.shadowOpacity = 1
    }

    private func applyMaskImageModifier(
        _ modifier: SRCompositionLayerMaskImageModifier,
        identifiedResources: [String: Resource]
    ) {
        guard
            let resource = identifiedResources[modifier.resourceId],
            let image = UIImage(data: resource.calculateData(), scale: UIScreen.main.scale)?.cgImage
        else {
            return
        }

        let mask = CALayer()
        mask.frame = bounds
        mask.contents = image
        mask.contentsGravity = .resize

        layer.mask = mask
    }

    private func appendFilter(_ filter: NSObject) {
        contentView.layer.filters = (contentView.layer.filters ?? []) + [filter]
    }
}

@available(iOS 13.0, *)
extension SRCompositionLayer {
    var absoluteFrame: CGRect {
        CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
    }

    var size: CGSize {
        CGSize(width: CGFloat(width), height: CGFloat(height))
    }
}

@available(iOS 13.0, *)
private extension NSObject {
    static func makeCAFilter(type: String) -> NSObject? {
        guard
            let filterClass = NSClassFromString("CAFilter"),
            let filter = (filterClass as AnyObject).perform(
                NSSelectorFromString("filterWithType:"),
                with: type
            )?
            .takeUnretainedValue() as? NSObject
        else {
            return nil
        }

        filter.perform(NSSelectorFromString("setDefaults"))
        return filter
    }
}

@available(iOS 13.0, *)
private extension CALayerSnapshot.ColorMatrix {
    var nsValue: NSValue {
        var value = self
        return withUnsafePointer(to: &value) {
            NSValue(bytes: $0, objCType: "{CAColorMatrix=ffffffffffffffffffff}")
        }
    }
}
