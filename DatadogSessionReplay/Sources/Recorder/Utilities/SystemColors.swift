/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

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
        if #available(iOS 13.0, *) {
            return UIColor.tertiarySystemFill.cgColor
        } else {
            // Fallback to iOS 16.2 light mode color:
            return UIColor(red: 118 / 255, green: 118 / 255, blue: 128 / 255, alpha: 1).cgColor
        }
    }

    static var tertiarySystemBackground: CGColor {
        if #available(iOS 13.0, *) {
            return UIColor.tertiarySystemBackground.cgColor
        } else {
            // Fallback to iOS 16.2 light mode color:
            return UIColor(red: 255 / 255, green: 255 / 255, blue: 255 / 255, alpha: 1).cgColor
        }
    }

    static var systemBackground: CGColor {
        if #available(iOS 13.0, *) {
            return UIColor.systemBackground.cgColor
        } else {
            // Fallback to iOS 16.2 light mode color:
            return UIColor(red: 255 / 255, green: 255 / 255, blue: 255 / 255, alpha: 1).cgColor
        }
    }

    static var secondarySystemGroupedBackground: CGColor {
        if #available(iOS 13.0, *) {
            return UIColor.secondarySystemGroupedBackground.cgColor
        } else {
            // Fallback to iOS 16.2 light mode color:
            return UIColor(red: 255 / 255, green: 255 / 255, blue: 255 / 255, alpha: 1).cgColor
        }
    }

    static var secondarySystemFill: CGColor {
        if #available(iOS 13.0, *) {
            return UIColor.secondarySystemFill.cgColor
        } else {
            // Fallback to iOS 16.2 light mode color:
            return UIColor(red: 120 / 255, green: 120 / 255, blue: 128 / 255, alpha: 1).cgColor
        }
    }

    static var tintColor: CGColor {
        if #available(iOS 15.0, *) {
            return UIColor.tintColor.cgColor
        } else {
            // Fallback to iOS 16.2 light mode color:
            return UIColor(red: 0 / 255, green: 122 / 255, blue: 255 / 255, alpha: 1).cgColor
        }
    }

    static var label: CGColor {
        if #available(iOS 13.0, *) {
            return UIColor.label.cgColor
        } else {
            // Fallback to iOS 16.2 light mode color:
            return UIColor(red: 0 / 255, green: 0 / 255, blue: 0 / 255, alpha: 1).cgColor
        }
    }

    static var systemGreen: CGColor {
        return UIColor.systemGreen.cgColor
    }

    static var placeholderText: CGColor {
        if #available(iOS 13.0, *) {
            return UIColor.placeholderText.cgColor
        } else {
            // Fallback to iOS 16.2 light mode color:
            return UIColor(red: 197 / 255, green: 197 / 255, blue: 197 / 255, alpha: 1).cgColor
        }
    }
}
