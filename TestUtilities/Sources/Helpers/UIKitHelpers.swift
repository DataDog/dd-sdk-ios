/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

/// The library name for UIKit framework as it will appear in unsymbolicated stack trace.
///
/// This name may differ between OS runtimes.
public var uiKitLibraryName: String {
    let uiKitBundleURL = Bundle(for: UIViewController.self).bundleURL
    let uiKitFrameworkName = uiKitBundleURL.lastPathComponent // 'UIKitCore.framework' on iOS 12+; 'UIKit.framework' on iOS 11
    return String(uiKitFrameworkName.dropLast(".framework".count))
}
