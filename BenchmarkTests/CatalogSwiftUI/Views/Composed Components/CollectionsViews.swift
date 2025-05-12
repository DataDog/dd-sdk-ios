//
//  CollectionsViews.swift
//  SwiftUICatalog
//
//  Created by Barbara Rodeker on 06.02.22.
//

import SwiftUI

struct CollectionsViews: View, Comparable {
    
    let id: String = "CollectionsViews"
    
    var body: some View {
        
        VStack {
            ContributionWantedView()
        }
        
    }
}

#Preview {
    
        CollectionsViews()
}
