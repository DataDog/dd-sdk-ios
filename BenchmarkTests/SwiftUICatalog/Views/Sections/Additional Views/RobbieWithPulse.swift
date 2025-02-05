//
//  RobbieWithPulse.swift
//  SwiftUICatalog
//
//  Created by Barbara Rodeker on 01.08.21.
//

import SwiftUI

struct RobbieWithPulseView: View, Comparable {
    
    let id: String = "RobbieWithPulseView"
    
    @State private var pulsing: Bool = false
    
    var body: some View {
        ZStack {
            Circle()
                .frame(width: 220, height: 220)
                .foregroundColor(Color("Medium", bundle: .module))
                .scaleEffect(pulsing ? 1.2 : 1.0)
                .opacity(pulsing ? 0.1 : 1.0)
                .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true).speed(0.5), value: pulsing)
                .onAppear() {
                    self.pulsing.toggle()
                }
            
            Image(systemName: "hands.and.sparkles.fill")
                .resizable()
                .scaledToFill()
                .frame(width: 200, height: 200)
                .clipShape(Circle())
            
        }
        .padding(24)
    }
    
    // MARK: - HASHABLE
    
    static func == (lhs: RobbieWithPulseView, rhs: RobbieWithPulseView) -> Bool {
        return lhs.hashValue == rhs.hashValue
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(pulsing)
    }
    
    
}

#Preview {
    
        RobbieWithPulseView()
    
}

