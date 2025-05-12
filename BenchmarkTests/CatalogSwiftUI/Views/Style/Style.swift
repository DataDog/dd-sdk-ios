//
//  Style.swift
//  SwiftUICatalog
//
//  Created by Barbara Personal on 2024-04-13.
//

import Foundation
import SwiftUI

/// UI spacing, margings, colors, used accross the app
struct Style {
    
    let images: [Image] = [
        Image(systemName: "globe.europe.africa"),
        Image(systemName: "globe.central.south.asia.fill"),
        Image(systemName: "globe.europe.africa.fill"),
        Image(systemName: "globe.central.south.asia"),
        Image(systemName: "globe.americas.fill"),
        Image(systemName: "globe.americas")
    ]
    
    let colorPalette1: [Color] = [
        Color(red: 255 / 255, green: 93 / 255, blue: 89 / 255),
        Color(red: 255 / 255, green: 171 / 255, blue: 119 / 255),
        Color(red: 247 / 255, green: 243 / 255, blue: 154 / 255),
        Color(red: 113 / 255, green: 211 / 255, blue: 167 / 255),
        Color(red: 92 / 255, green: 199 / 255, blue: 207 / 255),
        Color(red: 110 / 255, green: 171 / 255, blue: 240 / 255),
        Color(red: 156 / 255, green: 148 / 255, blue: 248 / 255),
        Color(red: 189 / 255, green: 131 / 255, blue: 226 / 255)
    ]
    
    /// vertical view separation
    enum VerticalPadding: CGFloat {
        case small = 8
        case medium = 16
        case large = 24
    }
    /// horizontal view separation
    enum HorizontalPadding: CGFloat {
        case small = 8
        case medium = 16
        case large = 24
    }
}
