//
//  PropertiesAnimationsView.swift
//  Catalog
//
//  Created by Barbara Personal on 2024-05-26.
//

import SwiftUI

struct PropertiesAnimationsView: View, Comparable {
    
    // MARK: - Properties
    
    let id: String = "PropertiesAnimationsView"
    
    @State private var animate1 = false
    @State private var animate2 = false
    @State private var animate3 = false
    @State private var animate4 = false
    
    
    // MARK: - Body
    
    
    var body: some View {
        
        ScrollView {
            
            VStack(alignment: .leading) {
                
                // MARK: - animating local properties
                
                
                GroupBox {
                    VStack(alignment: .leading) {
                        Text( "Animating an array of images")
                            .fontWeight(.heavy)
                            .font(.title)
                        Text("Given an array of images, which together build a frame animation, they can be displayed in sequence, generating a lively effect. \n Press on top of the icons to play the animations.")
                            .fontWeight(.light)
                            .font(.title2)
                        HStack {
                            Spacer()
                            AnimatableView(images: [
                                UIImage(systemName: "hands.and.sparkles.fill")!,
                                UIImage(systemName: "hands.and.sparkles")!,
                                UIImage(systemName: "hands.clap.fill")!,
                                UIImage(systemName: "hands.clap")!,
                                UIImage(systemName: "hand.wave.fill")!,
                            ],
                                           duration: 5,
                                           frame: CGRect(x: 0, y: 0, width: 100, height: 100)
                            )
                            .frame(width: 100, height: 100)
                            Spacer()
                        }
                    }
                }
                .modifier(Divided())
                
                GroupBox {
                    VStack(alignment: .leading) {
                        Text( "Animating a toggle on a boolean")
                            .fontWeight(.heavy)
                            .font(.title)
                        Text("Using a boolean you can play around with different types of animations. Tap the image below to see how each animation looks like.")
                            .fontWeight(.light)
                            .font(.title2)
                        Button(action: {
                            withAnimation(.easeInOut(duration: 3)) {
                                self.animate3.toggle()
                            }
                        }) {
                            HStack {
                                Spacer()
                                Image(systemName: "hands.and.sparkles.fill")
                                    .resizable()
                                    .rotationEffect(.degrees(animate3 ? 90 : 0))
                                    .scaleEffect(animate3 ? 1.2 : 1)
                                    .frame(width: 100, height: 100)
                                Spacer()
                            }
                            .padding()
                            // end of h stack
                        }
                        // end of h stack
                    }
                }
                .modifier(Divided())
                
                // MARK: - rotation animated
                
                GroupBox {
                    VStack(alignment: .leading) {
                        Text( "Rotation animated")
                            .fontWeight(.heavy)
                            .font(.title)
                        Text("Using a rotation effect and changing the degrees of the angle you can achieve a different animation.")
                            .fontWeight(.light)
                            .font(.title2)
                        
                        
                        Button(action: {
                            self.animate1.toggle()
                        }) {
                            HStack {
                                Spacer()
                                Image(systemName: "hands.and.sparkles.fill")
                                    .resizable()
                                    .rotationEffect(.degrees(animate1 ? 90 : 0))
                                    .scaleEffect(animate1 ? 1.2 : 1)
                                    .frame(width: 100, height: 100)
                                    .animation(.easeInOut.repeatCount(3), value: animate1)
                                Spacer()
                            }
                            // end of h stack
                        }
                    }
                }
                .modifier(Divided())
                
                
                // MARK: - Spring rotation
                GroupBox {
                    VStack(alignment: .leading)  {
                        Text("Rotation animation with Spring")
                            .fontWeight(.heavy)
                            .font(.title)
                        Text("A different type of effect is achieved by using a spring animation.")
                            .fontWeight(.light)
                            .font(.title2)
                        
                        
                        
                        Button(action: {
                            self.animate2.toggle()
                        }) {
                            HStack {
                                Spacer()
                                Image(systemName: "hands.and.sparkles.fill")
                                    .resizable()
                                    .rotationEffect(.degrees(animate2 ? 90 : 0))
                                    .scaleEffect(animate2 ? 1.2 : 1)
                                    .frame(width: 100, height: 100)
                                    .animation(.spring().repeatCount(3), value: animate2)
                                Spacer()
                            }
                            // end of h stack
                        }
                    }
                    // end of h stack
                }
                .modifier(Divided())
                // end of group
                
                // MARK: - ripple
                GroupBox {
                    VStack(alignment: .leading)  {
                        Text("Ripple animation")
                            .fontWeight(.heavy)
                            .font(.title)
                        Text("Here's an example of how to use your custom defined animation to simulate a ripple effect on an image.")
                            .fontWeight(.light)
                            .font(.title2)
                        
                        Button(action: {
                            self.animate4.toggle()
                        }) {
                            HStack {
                                Spacer()
                                Image(systemName: "hands.and.sparkles.fill")
                                    .resizable()
                                    .rotationEffect(.degrees(animate4 ? 90 : 0))
                                    .scaleEffect(animate4 ? 1.2 : 1)
                                    .frame(width: 100, height: 100)
                                    .animation(.ripple(index: 2), value: animate4)
                                Spacer()
                            }
                            // end of h stack
                        }
                    }
                    // end of h stack
                }
                .modifier(Divided())
                // end of group
                
                ContributedByView(name: "Barbara Martina",
                                  link: "https://github.com/barbaramartina")
                .padding(.top, 80)
                
            }
            .padding(.vertical, Style.VerticalPadding.medium.rawValue)
            .padding(.horizontal, Style.HorizontalPadding.medium.rawValue)
            // end of list
        }
    }
    
}



#Preview {
    PropertiesAnimationsView()
}
