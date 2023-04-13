//
//  File.swift
//  
//
//  Created by Maciej Burda on 13/04/2023.
//

import UIKit

extension SRTextPosition.Alignment {
    init(textAlignment: NSTextAlignment) {
        self.vertical = .center
        switch textAlignment {
        case .left:
            self.horizontal = .left
        case .center:
            self.horizontal = .center
        case .right:
            self.horizontal = .right
        case .justified:
            self.horizontal = .left
        default:
            if UIApplication.shared.userInterfaceLayoutDirection == .leftToRight {
                self.horizontal = .left
            } else {
                self.horizontal = .right
            }
        }
    }
}
