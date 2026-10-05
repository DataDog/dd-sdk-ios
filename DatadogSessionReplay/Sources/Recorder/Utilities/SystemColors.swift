/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit

/// Collection of system colors.
///
/// Contextual colors are light- and dark-mode sensitive and must be implemented as computed variables,
/// so they return different values upon `UIUserInterfaceStyle` change.
///
/// For older iOS versions that do not support `UIUserInterfaceStyle`, approximate fallbacks are provided.
/// See https://gist.github.com/ncreated/35bf4d69d83d1a5ab408ff29a77fc9ff for reference when updating this collection.
internal enum SystemColors {
    static let clear: CGColor = UIColor.clear.cgColor

    static var tertiarySystemFill: CGColor {
        return UIColor.tertiarySystemFill.cgColor
    }

    static var tertiarySystemBackground: CGColor {
        return UIColor.tertiarySystemBackground.cgColor
    }

    static var systemBackground: CGColor {
        return UIColor.systemBackground.cgColor
    }

    static var secondarySystemGroupedBackground: CGColor {
        return UIColor.secondarySystemGroupedBackground.cgColor
    }

    static var secondarySystemFill: CGColor {
        return UIColor.secondarySystemFill.cgColor
    }

    static var tintColor: CGColor {
        return UIColor.tintColor.cgColor
    }

    static var label: CGColor {
        return UIColor.label.cgColor
    }

    static var systemGreen: CGColor {
        return UIColor.systemGreen.cgColor
    }

    static var systemGray: UIColor {
        return UIColor.systemGray
    }

    static var systemBlue: UIColor {
        return UIColor.systemBlue
    }

    static var placeholderText: CGColor {
        return UIColor.placeholderText.cgColor
    }
}
#endif
