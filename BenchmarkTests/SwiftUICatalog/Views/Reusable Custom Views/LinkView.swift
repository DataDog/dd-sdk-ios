//
//  LinkView.swift
//  SwiftUICatalog
//
//  Created by Barbara Rodeker on 18.07.21.
//

import SwiftUI


struct Link<Destination> : View, Hashable, Identifiable where Destination : View {
    
    var id: String {
        return label
    }
    
    var destination: Destination
    var label: String
    var textColor: Color = .white
    
    var body: some View {
        NavigationLink(destination: destination) {
            Text(label)
                .font(.title2)
                .fontWeight(.light)
                .font(.title2)
                .foregroundColor(textColor)
        }
        .padding(.bottom, 5)
    }
    
    // MARK: - HASHABLE
    
    static func == (lhs: Link<Destination>, rhs: Link<Destination>) -> Bool {
        return lhs.label == rhs.label
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    
}
