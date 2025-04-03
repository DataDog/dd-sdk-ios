//
//  Section.swift
//  Catalog
//
//  Created by Barbara Personal on 2024-05-12.
//

import Foundation
import SwiftUI

/// represents a section in the main menu
struct MenuSection: Identifiable {
    
    var id: String { name }
    
    /// is the section ready? or it still needs to be added
    enum State {
        case ready
        case notPublishable
        case needsContribution
    }
    
    let name: String
    let state: State
    let view: AnyView
}

/// Containing all the sections of the app
struct SectionContainer {
    let sections: [MenuSection]
    
    /// convenience variable to retrieve sections that are already finished and show views examples
    var readySections: [MenuSection] {
        sections.compactMap { section in
            guard section.state == .ready else { return nil }
            return section
        }
    }
}

