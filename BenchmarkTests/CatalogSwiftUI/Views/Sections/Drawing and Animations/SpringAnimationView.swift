//
//  SpringAnimation.swift
//  Catalog
//
//  Created by Barbara Personal on 2024-05-28.
//

import SwiftUI

struct SpringAnimationView: View {
    @State private var isActive1 = false
    @State private var isActive2 = false
    @State private var isActive3 = false
    
    var body: some View {
        
        PageContainer(content:
                        
                        ScrollView {
            
            DocumentationLinkView(link: "https://developer.apple.com/documentation/swiftui/animation/spring")
            
            VStack(alignment: .leading) {
                Text("Since iOS17 spring animations can be applied to views and easily created.")
                    .fontWeight(.light)
                    .font(.title2)
                example1
                    .modifier(Divided())
                example2
                    .modifier(Divided())
                example3
                    .modifier(Divided())
            }
            
        })
    }
    
    private var example1: some View {
        GroupBox {
            Button(action: {
                withAnimation(.spring(.bouncy(extraBounce: 0.08),
                                      blendDuration: 10)) {
                    isActive1.toggle()
                }
            }, label: {
                Text("Bouncy spring")
                    .modifier(ButtonFontModifier())
            })
            .frame(maxWidth: .infinity)
            .modifier(RoundedBordersModifier(radius: 10,
                                             lineWidth: 2))
            Circle()
                .frame(width: isActive1 ? 200.0 : 10.0)
                .foregroundColor(.accentColor)
        }
    }
    private var example2: some View {
        GroupBox {
            Button(action: {
                withAnimation(.spring(.smooth,
                                      blendDuration: 10)) {
                    isActive2.toggle()
                }
            }, label: {
                Text("Smooth spring")
                    .modifier(ButtonFontModifier())
            })
            .frame(maxWidth: .infinity)
            .modifier(RoundedBordersModifier(radius: 10,
                                             lineWidth: 2))
            Circle()
                .frame(width: isActive2 ? 200.0 : 10.0)
                .foregroundColor(.accentColor)
        }
    }
    private var example3: some View {
        GroupBox {
            Button(action: {
                withAnimation(.spring(.snappy(extraBounce: 0.25),
                                      blendDuration: 10)) {
                    isActive3.toggle()
                }
            }, label: {
                Text("Snappy spring")
                    .modifier(ButtonFontModifier())
            })
            .frame(maxWidth: .infinity)
            .modifier(RoundedBordersModifier(radius: 10,
                                             lineWidth: 2))
            Circle()
                .frame(width: isActive3 ? 200.0 : 10.0)
                .foregroundColor(.accentColor)
        }
    }
}

#Preview {
    SpringAnimationView()
}

