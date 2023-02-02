/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

func swizzle(originalClass: AnyClass,
             originalSelector: Selector,
             isOriginalSelectorClassMethod: Bool,
             swizzledClass: AnyClass,
             swizzledSelector: Selector,
             isSwizzledSelectorClassMethod: Bool) {
    guard let originalMethod = isOriginalSelectorClassMethod ?
        class_getClassMethod(originalClass, originalSelector) :
        class_getInstanceMethod(originalClass, originalSelector) else {
            return
    }

    guard let swizzledMethod = isSwizzledSelectorClassMethod ?
        class_getClassMethod(swizzledClass, swizzledSelector) :
        class_getInstanceMethod(swizzledClass, swizzledSelector) else {
            return
    }

    let didAddMethod = class_addMethod(isOriginalSelectorClassMethod ? object_getClass(originalClass)! : originalClass,
                                       originalSelector,
                                       method_getImplementation(swizzledMethod),
                                       method_getTypeEncoding(swizzledMethod))

    if didAddMethod {
        class_replaceMethod(isSwizzledSelectorClassMethod ? object_getClass(swizzledClass)! : swizzledClass,
                            swizzledSelector,
                            method_getImplementation(originalMethod),
                            method_getTypeEncoding(originalMethod))
    } else {
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
}

extension UIImage {
    static func swizzleInitializersIfNeeded() {
        guard !areInitializersSwizzled else {
            return
        }

        areInitializersSwizzled = true

        swizzle(originalClass: self,
                originalSelector: #selector(UIImage.init(named:)),
                isOriginalSelectorClassMethod: true,
                swizzledClass: self,
                swizzledSelector: #selector(UIImage.image(named:)),
                isSwizzledSelectorClassMethod: true)

        if #available(iOS 13.0, *) {
            swizzle(originalClass: self,
                    originalSelector: #selector(UIImage.init(named:in:with:)),
                    isOriginalSelectorClassMethod: true,
                    swizzledClass: self,
                    swizzledSelector: #selector(UIImage.image(named:in:with:)),
                    isSwizzledSelectorClassMethod: true)
        }
    }

    private static var areInitializersSwizzled = false

    @objc fileprivate class func image(named name: String) -> UIImage? {
        let image = self.image(named: name)
        image?.name = name

        return image
    }

    @available(iOS 13.0, *)
    @objc fileprivate class func image(named name: String,
                                       in bundle: Bundle,
                                       with config: UIImage.Configuration) -> UIImage? {
        let image = self.image(named: name, in: bundle, with: config)
        image?.name = name
        image?.bundle = bundle

        return image
    }
    
    private static var nameKey = 0
    private static var bundleKey = 1

    private(set) var name: String? {
        get { objc_getAssociatedObject(self, &UIImage.nameKey) as? String }
        set { objc_setAssociatedObject(self, &UIImage.nameKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    private(set) var bundle: Bundle? {
        get { objc_getAssociatedObject(self, &UIImage.bundleKey) as? Bundle }
        set { objc_setAssociatedObject(self, &UIImage.bundleKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}
