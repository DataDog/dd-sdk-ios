//
//  ContenView+SectionsBuilding.swift
//  Catalog
//
//  Created by Barbara Personal on 2024-05-12.
//

import Foundation
import SwiftUI

extension ContentView {
    
    // MARK: - Build the sections
    
    var sectionContainer: SectionContainer {
        let controls = MenuSection(name: "Controls",
                                   state: .ready,
                                   view: AnyView(controls))
        let storeKit = MenuSection(name: "Store Kit",
                                   state: .notPublishable,
                                   view: AnyView(storeKit))
        let layouts = MenuSection(name: "Layouts",
                                  state: .ready,
                                  view: AnyView(layouts))
        let hierachicalViews = MenuSection(name: "Hierarchical Views",
                                           state: .ready,
                                           view: AnyView(hierachicalViews))
        let drawings = MenuSection(name: "Drawings",
                                   state: .ready,
                                   view: AnyView(drawings))
        let charts = MenuSection(name: "charts",
                                 state: .ready,
                                 view: AnyView(charts))
        let gestures = MenuSection(name: "Gestures",
                                   state: .ready,
                                   view: AnyView(gestures))
        let viewModifiers = MenuSection(name: "View Modifiers",
                                        state: .ready,
                                        view: AnyView(viewModifiers))
        let accessibility = MenuSection(name: "Accessibility",
                                        state: .ready,
                                        view: AnyView(accessibility))
        let statusBars = MenuSection(name: "Status Bars",
                                     state: .notPublishable,
                                     view: AnyView(statusBars))
        let stylingSection = MenuSection(name: "Styling",
                                         state: .ready,
                                         view: AnyView(stylingSection))
        let popovers = MenuSection(name: "Popovers",
                                   state: .ready,
                                   view: AnyView(popovers))
        let composedComponents = MenuSection(name: "Composed Components",
                                             state: .ready,
                                             view: AnyView(composedComponents))
        
        
        
        return SectionContainer(sections: [
            controls,
            storeKit,
            layouts,
            hierachicalViews,
            drawings,
            charts,
            gestures,
            viewModifiers,
            accessibility,
            statusBars,
            stylingSection,
            popovers,
            composedComponents
        ])
    }
    
}
