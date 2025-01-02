//
//  SensoryFeedbackInViews.swift
//  Catalog
//
//  Created by Barbara Personal on 2024-05-19.
//

import SwiftUI

struct SensoryFeedbackInViews: View {
    /// triggers the success sensory feedback
    @State private var success: Bool = false
    /// triggers the warning sensory feedback
    @State private var warning: Bool = false
    /// triggers the error sensory feedback
    @State private var error: Bool = false
    
    
    var body: some View {
        PageContainer(content:
                        VStack(alignment: .leading) {
            DocumentationLinkView(link: "https://developer.apple.com/documentation/swiftui/sensoryfeedback")
            Text("Sensory feedback")
                .fontWeight(.heavy)
                .font(.title)
            
            Text("Since iOS17 SwiftUI offers sensory feedback modifiers. To try out how each of the standard sensory feedback effect feels like, click on the buttons below. \nRemember that for hearing feedback, you have to activate it in your phone's Settings.")
                .fontWeight(.light)
                .font(.title2)
            
            HStack {
                successButton
                warningButton
            }
            HStack {
                errorButton
                alignmentButton
            }
            HStack {
                decreaseButton
                increaseButton
            }
            HStack {
                levelButton
                selectionButton
            }
            impactButtonSoft
            impactButtonSolid
            impactButtonRigid
        }
        )
    }
    
    private var successButton: some View {
        Button(action: {
            success.toggle()
        }, label: {
            Text("Success")
                .modifier(ButtonFontModifier())
        })
        .modifier(RoundedBordersModifier(radius: 10,
                                         lineWidth: 2))
        .padding(.leading, 2)
        .sensoryFeedback(.success, trigger: success)
    }
    
    private var warningButton: some View {
        Button(action: {
            success.toggle()
        }, label: {
            Text("Warning")
                .modifier(ButtonFontModifier())
        })
        .modifier(RoundedBordersModifier(radius: 10,
                                         lineWidth: 2))
        .padding(.leading, 2)
        .sensoryFeedback(.warning, trigger: warning)
    }
    
    private var errorButton: some View {
        Button(action: {
            success.toggle()
        }, label: {
            Text("Error")
                .modifier(ButtonFontModifier())
        })
        .modifier(RoundedBordersModifier(radius: 10,
                                         lineWidth: 2))
        .padding(.leading, 2)
        .sensoryFeedback(.error, trigger: error)
        
    }
    
    private var alignmentButton: some View {
        Button(action: {
            success.toggle()
        }, label: {
            Text("Alignment")
                .modifier(ButtonFontModifier())
        })
        .modifier(RoundedBordersModifier(radius: 10,
                                         lineWidth: 2))
        .padding(.leading, 2)
        .sensoryFeedback(.alignment, trigger: error)
        
    }
    private var decreaseButton: some View {
        Button(action: {
            success.toggle()
        }, label: {
            Text("Decrease")
                .modifier(ButtonFontModifier())
        })
        .modifier(RoundedBordersModifier(radius: 10,
                                         lineWidth: 2))
        .padding(.leading, 2)
        .sensoryFeedback(.decrease, trigger: error)
    }
    private var increaseButton: some View {
        Button(action: {
            success.toggle()
        }, label: {
            Text("Increase")
                .modifier(ButtonFontModifier())
        })
        .modifier(RoundedBordersModifier(radius: 10,
                                         lineWidth: 2))
        .padding(.leading, 2)
        .sensoryFeedback(.increase, trigger: error)
    }
    private var levelButton: some View {
        Button(action: {
            success.toggle()
        }, label: {
            Text("Level")
                .modifier(ButtonFontModifier())
        })
        .modifier(RoundedBordersModifier(radius: 10,
                                         lineWidth: 2))
        .padding(.leading, 2)
        .sensoryFeedback(.levelChange, trigger: error)
    }
    private var selectionButton: some View {
        Button(action: {
            success.toggle()
        }, label: {
            Text("Selection")
                .modifier(ButtonFontModifier())
        })
        .modifier(RoundedBordersModifier(radius: 10,
                                         lineWidth: 2))
        .padding(.leading, 2)
        .sensoryFeedback(.selection, trigger: error)
    }
    private var impactButtonRigid: some View {
        Button(action: {
            success.toggle()
        }, label: {
            Text("Impact rigid")
                .modifier(ButtonFontModifier())
        })
        .modifier(RoundedBordersModifier(radius: 10,
                                         lineWidth: 2))
        .padding(.leading, 2)
        .sensoryFeedback(.impact(flexibility: .rigid,
                                 intensity: 0.8), trigger: error)
    }
    private var impactButtonSoft: some View {
        Button(action: {
            success.toggle()
        }, label: {
            Text("Impact soft")
                .modifier(ButtonFontModifier())
        })
        .modifier(RoundedBordersModifier(radius: 10,
                                         lineWidth: 2))
        .padding(.leading, 2)
        .sensoryFeedback(.impact(flexibility: .soft,
                                 intensity: 0.8), trigger: error)
    }
    private var impactButtonSolid: some View {
        Button(action: {
            success.toggle()
        }, label: {
            Text("Impact solid")
                .modifier(ButtonFontModifier())
        })
        .modifier(RoundedBordersModifier(radius: 10,
                                         lineWidth: 2))
        .padding(.leading, 2)
        .sensoryFeedback(.impact(flexibility: .solid,
                                 intensity: 0.8), trigger: error)
    }
}

#Preview {
    SensoryFeedbackInViews()
}
