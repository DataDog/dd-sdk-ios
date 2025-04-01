//
//  TransitionsAnimationsView.swift
//  Catalog
//
//  Created by Barbara Personal on 2024-05-26.
//

import SwiftUI

struct TransitionsAnimationsView: View, Comparable {
    
    // MARK: - Properties
    
    let id: String = "TransitionsAnimationsView"
    
    @State private var animate1 = false { didSet { if animate1 == true { resetFlags(indexes: [2,3,4,5,6,7,8,9]) } } }
    @State private var animate2 = false { didSet { if animate2 == true { resetFlags(indexes: [1,3,4,5,6,7,8,9]) } } }
    @State private var animate3 = false { didSet { if animate3 == true { resetFlags(indexes: [1, 2,4,5,6,7,8,9]) } } }
    @State private var animate4 = false { didSet { if animate4 == true { resetFlags(indexes: [1,2,3,5,6,7,8,9]) } } }
    @State private var animate5 = false { didSet { if animate5 == true { resetFlags(indexes: [1,2,3,4,6,7,8,9]) } } }
    @State private var animate6 = false { didSet { if animate6 == true { resetFlags(indexes: [1,2,3,4,5,7,8,9]) } } }
    @State private var animate7 = false { didSet { if animate7 == true { resetFlags(indexes: [1,2,3,4,5,6,8,9]) } } }
    @State private var animate8 = false { didSet { if animate8 == true { resetFlags(indexes: [1,2,3,4,5,6,7,9]) } } }
    @State private var animate9 = false { didSet { if animate9 == true { resetFlags(indexes: [1,2,3,4,5,6,7,8]) } } }
    
    // MARK: - Body
    
    
    var body: some View {
        PageContainer(content: ScrollView {
            VStack(alignment: .leading) {
                HStack {
                    Text("Tap each button to see how the animation mentioned would look like, and then tap it again to see how the animation reverses.")
                        .fontWeight(.light)
                        .font(.title2)
                    Spacer()
                }
                
                HStack {
                    button1
                    button2
                    button3
                    button4
                }
                HStack {
                    button5
                    button6
                }
                HStack {
                    button7
                    button8
                }
                HStack {
                    button9
                }
                
                VStack(spacing: 0) {
                    if animate1 {
                        Image(systemName: "cloud.circle.fill")
                            .resizable()
                            .frame(width: 100, height: 100)
                            .transition(.slide)
                            .padding(100)
                    }
                    
                    if animate2 {
                        Image(systemName: "cloud.circle")
                            .resizable()
                            .frame(width: 100, height: 100)
                            .transition(.opacity)
                            .padding(100)
                    }
                    
                    if animate3 {
                        Image(systemName: "moon.stars.circle")
                            .resizable()
                            .frame(width: 100, height: 100)
                            .transition(.moveAndFade)
                            .padding(100)
                    }
                    
                    if animate4 {
                        Image(systemName: "moon.stars.circle.fill")
                            .resizable()
                            .frame(width: 100, height: 100)
                            .transition(.scale)
                            .padding(100)
                    }
                    if animate5 {
                        Image(systemName: "moon.haze.circle.fill")
                            .resizable()
                            .frame(width: 100, height: 100)
                            .transition(.move(edge: .bottom))
                            .padding(.vertical, 100)
                    }
                    if animate6 {
                        Image(systemName: "sparkles")
                            .resizable()
                            .frame(width: 100, height: 100)
                            .transition(.leadingBottom)
                            .padding(100)
                    }
                    if animate7 {
                        Image(systemName: "moon.stars")
                            .resizable()
                            .frame(width: 100, height: 100)
                            .transition(.trailingBottom)
                            .padding(100)
                    }
                    if animate8 {
                        Image(systemName: "moon.stars.fill")
                            .resizable()
                            .frame(width: 100, height: 100)
                            .transition(.push(from: .bottom))
                            .padding(100)
                    }
                    if animate9 {
                        Image(systemName: "moon.stars.circle")
                            .resizable()
                            .frame(width: 100, height: 100)
                            .transition(.blurReplace)
                            .padding(100)
                    }
                }
                .frame(maxWidth: .infinity, idealHeight: 250)
            }
        })
        
    }
    
    private func resetFlags(indexes: [Int]) {
        indexes.forEach { index in
            switch index {
            case 1: animate1 = false
            case 2: animate2 = false
            case 3: animate3 = false
            case 4: animate4 = false
            case 5: animate5 = false
            case 6: animate6 = false
            case 7: animate7 = false
            case 8: animate8 = false
            case 9: animate9 = false
            default: break
            }
        }
    }
    
    private var button1: some View {
        Button(action: {
            withAnimation {
                self.animate1.toggle()
            }
        }, label: {
            Text("Slide")
            
        })
        .buttonStyle(BorderedButtonStyle())
        
    }
    
    private var button2: some View {
        Button(action: {
            withAnimation {
                self.animate2.toggle()
            }
        }, label: {
            Text("Opacity")
        })
        .buttonStyle(BorderedButtonStyle())
        
    }
    
    private var button3: some View {
        Button(action: {
            withAnimation {
                self.animate3.toggle()
            }
        }, label: {
            Text("Fading")
        })
        .buttonStyle(BorderedButtonStyle())
        
    }
    
    private var button4: some View {
        Button(action: {
            withAnimation {
                self.animate4.toggle()
            }
        }, label: {
            Text("Scale")
        })
        .buttonStyle(BorderedButtonStyle())
    }
    
    private var button5: some View {
        Button(action: {
            withAnimation {
                self.animate5.toggle()
            }
        }, label: {
            Text("Move edge")
        })
        .buttonStyle(BorderedButtonStyle())
    }
    
    private var button6: some View {
        Button(action: {
            withAnimation {
                self.animate6.toggle()
            }
        }, label: {
            Text("Leading Bottom")
        })
        .buttonStyle(BorderedButtonStyle())
    }
    
    private var button7: some View {
        Button(action: {
            withAnimation {
                self.animate7.toggle()
            }
        }, label: {
            Text("Trailing Bottom")
        })
        .buttonStyle(BorderedButtonStyle())
    }
    
    private var button8: some View {
        Button(action: {
            withAnimation {
                self.animate8.toggle()
            }
        }, label: {
            Text("Push from Bottom")
        })
        .buttonStyle(BorderedButtonStyle())
    }
    
    private var button9: some View {
        Button(action: {
            withAnimation {
                self.animate9.toggle()
            }
        }, label: {
            Text("Blur replace")
        })
        .buttonStyle(BorderedButtonStyle())
    }
}


#Preview {
    TransitionsAnimationsView()
}
